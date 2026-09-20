#!/usr/bin/env python3
"""Character sheet assembly, strip splitting and contract validation.

  sheet.py split    strip.png --anim idle_sip -o frames/idle_sip/
  sheet.py assemble strips/ -o set/character/sheet.png [--fill-from old_sheet.png]
  sheet.py validate --assets set/ --palette sweetie16        # exit code 1 on any error
  sheet.py validate                                          # the installed theme, against its own palette

`validate` checks the whole theme layout (docs/ART.md): character sheet, portrait, scenes, props,
ambient strips, the frame and its connectors (including that they line up across a seam), the orb,
avatar swaps, and the shared palette. Without --palette it uses the palette in theme.json.

`assemble` reads, per animation in the manifest, either strips/<anim>.png (a
normalised strip, frames*32 x 32) or strips/<anim>/*.png (single 32x32 frames,
sorted by name).
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common as C  # noqa: E402

HEADER_ROWS = 11      # docs/ART.md: the header lintel covers the top 11 px
MIN_FRAME_PIXELS = 20


class Report:
    def __init__(self):
        self.items: list[dict] = []

    def add(self, level, where, code, msg):
        self.items.append({"level": level, "where": where, "code": code, "message": msg})

    def error(self, where, code, msg): self.add("error", where, code, msg)
    def warn(self, where, code, msg): self.add("warning", where, code, msg)

    @property
    def errors(self): return [i for i in self.items if i["level"] == "error"]
    @property
    def warnings(self): return [i for i in self.items if i["level"] == "warning"]

    def print(self, verbose=True):
        for i in self.items:
            if verbose or i["level"] == "error":
                print(f"  {i['level'].upper():7} {i['where']}: {i['message']}  [{i['code']}]")


# ---------- split / assemble ----------

def split_strip(strip: np.ndarray, n: int, use_gaps=False) -> list[np.ndarray]:
    spans = C.split_columns(strip[..., 3] >= 128, n, use_gaps)
    return [strip[:, x0:x1] for x0, x1 in spans]


def load_anim_frames(src: Path, name: str, n: int, fw: int, fh: int) -> list[np.ndarray] | None:
    strip, folder = src / f"{name}.png", src / name
    if strip.exists():
        a = C.load_rgba(strip)
        if a.shape[:2] != (fh, n * fw):
            raise ValueError(f"{strip}: is {a.shape[1]}x{a.shape[0]}, expected {n * fw}x{fh} ({n} frames of {fw}x{fh}). "
                             "Run it through normalize.py character-strip first")
        return [a[:, i * fw:(i + 1) * fw] for i in range(n)]
    if folder.is_dir():
        files = sorted(folder.glob("*.png"))
        if len(files) != n:
            raise ValueError(f"{folder}: has {len(files)} frames, manifest says {n}")
        frames = [C.load_rgba(f) for f in files]
        for f, a in zip(files, frames):
            if a.shape[:2] != (fh, fw):
                raise ValueError(f"{f}: is {a.shape[1]}x{a.shape[0]}, expected {fw}x{fh}")
        return frames
    return None


def assemble(src: Path, man: dict, fill_from: Path | None = None) -> tuple[np.ndarray, list[str]]:
    ch = man["character"]
    fw, fh = ch["frame"]
    sheet = np.zeros((ch["rows"] * fh, ch["columns"] * fw, 4), np.uint8)
    old = C.load_rgba(fill_from) if fill_from else None
    if old is not None and old.shape != sheet.shape:
        raise ValueError(f"{fill_from}: is {old.shape[1]}x{old.shape[0]}, expected {sheet.shape[1]}x{sheet.shape[0]}")
    notes = []
    for name, spec in C.anim_rows(man):
        frames = load_anim_frames(src, name, spec["frames"], fw, fh)
        r = spec["row"]
        if frames is None:
            if old is None:
                raise ValueError(f"no input for animation '{name}' (wanted {src}/{name}.png or {src}/{name}/*.png); "
                                 "use --fill-from SHEET to keep existing rows")
            sheet[r * fh:(r + 1) * fh] = old[r * fh:(r + 1) * fh]
            notes.append(f"row {r} {name}: kept from {fill_from}")
            continue
        for c, fr in enumerate(frames):
            sheet[r * fh:(r + 1) * fh, c * fw:(c + 1) * fw] = fr
        notes.append(f"row {r} {name}: {len(frames)} frames from {src}")
    return sheet, notes


# ---------- validation ----------

def foot_centre(frame: np.ndarray) -> float | None:
    """Centre (in px from the frame's left edge) of the opaque span in the lowest 3 rows."""
    cols = np.nonzero((frame[-3:, :, 3] > 0).any(0))[0]
    return None if len(cols) == 0 else (cols.min() + cols.max() + 1) / 2


def _check_alpha(rep, where, a):
    bad = int(((a[..., 3] != 0) & (a[..., 3] != 255)).sum())
    if bad:
        rep.error(where, "alpha", f"{bad} px have partial alpha; alpha must be 0 or 255")


def _colours(a) -> set:
    return {tuple(int(v) for v in c) for c in np.unique(a[a[..., 3] > 0][:, :3], axis=0)}


def _check_palette(rep, where, a, pal_set):
    if pal_set is None:
        return
    off = _colours(a) - pal_set
    if off:
        rgb = a[..., :3]
        worst = sorted(off, key=lambda c: -int(((rgb == c).all(-1) & (a[..., 3] > 0)).sum()))[:4]
        desc = []
        for c in worst:
            ys, xs = np.nonzero((rgb == c).all(-1) & (a[..., 3] > 0))
            desc.append("#%02x%02x%02x x%d first at (%d,%d)" % (*c, len(ys), xs[0], ys[0]))
        rep.error(where, "palette", f"{len(off)} colour(s) not in the palette: " + "; ".join(desc))


def _busyness(a) -> float:
    """Share of neighbouring pixel pairs that differ: 0 = flat, higher = busier."""
    if a.shape[0] < 2 or a.shape[1] < 2:
        return 0.0
    dx = (a[:, 1:] != a[:, :-1]).any(-1).mean()
    dy = (a[1:] != a[:-1]).any(-1).mean()
    return float((dx + dy) / 2)


def validate_sheet(rep: Report, path: Path, man: dict, pal_set, centre_tol=1.5, drift_tol=1.0):
    ch = man["character"]
    fw, fh = ch["frame"]
    where = str(path.name)
    a = C.load_rgba(path)
    want = (ch["rows"] * fh, ch["columns"] * fw)
    if a.shape[:2] != want:
        rep.error(where, "size", f"is {a.shape[1]}x{a.shape[0]}, expected {want[1]}x{want[0]} "
                                 f"({ch['columns']} columns x {ch['rows']} rows of {fw}x{fh})")
        return
    _check_alpha(rep, where, a)
    _check_palette(rep, where, a, pal_set)
    rim_dark, rim_total = 0, 0
    for name, spec in C.anim_rows(man):
        r, n = spec["row"], spec["frames"]
        if n > ch["columns"]:
            rep.error(name, "frames", f"manifest wants {n} frames but the sheet has {ch['columns']} columns")
            continue
        centres = []
        for c in range(ch["columns"]):
            fr = C.frame_of(a, r, c, fw, fh)
            op = fr[..., 3] > 0
            tag = f"{name}[{c}]"
            if c >= n:
                if op.any():
                    rep.error(tag, "extra-frame", f"column {c} should be empty: the manifest lists {n} frames for '{name}'")
                continue
            if op.sum() < MIN_FRAME_PIXELS:
                rep.error(tag, "empty-frame", f"frame is empty ({int(op.sum())} opaque px); '{name}' needs {n} frames")
                continue
            lowest = int(np.nonzero(op.any(1))[0].max())
            if lowest != fh - 1:
                rep.error(tag, "feet", f"lowest pixel is on row {lowest}, feet must touch the bottom edge (row {fh - 1})")
            fc = foot_centre(fr)
            if fc is not None:
                centres.append((c, fc))
                if abs(fc - fw / 2) > centre_tol:
                    rep.error(tag, "centre", f"feet are centred at x={fc:.1f}, expected {fw / 2:.1f} +/- {centre_tol}")
            if op[:, 0].any() or op[:, -1].any() or op[0].any():
                rep.warn(tag, "edge", "touches the left, right or top frame edge: possibly clipped")
            pad = np.pad(op, 1)
            rim = op & ~(pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:])
            rim[-1] = False  # the bottom edge is cut by the frame, not a drawn rim
            rim_total += int(rim.sum()); rim_dark += int((C.luma(fr)[rim] < 70).sum())
        if len(centres) > 1:
            xs = [x for _, x in centres]
            if max(xs) - min(xs) > drift_tol:
                rep.error(name, "drift", f"feet centre drifts {max(xs) - min(xs):.1f} px across the row "
                                         f"(per frame: {', '.join(f'{x:.1f}' for x in xs)}); limit {drift_tol}")
    if rim_total and rim_dark / rim_total < 0.8:
        rep.warn(where, "outline", f"only {rim_dark / rim_total:.0%} of silhouette edge pixels are dark; the contract asks for a "
                                   "hard 1px dark outline (normalize.py --outline outer)")


def validate_room(rep: Report, room: dict, root: Path, man: dict, pal_set):
    cw, ch_ = man["canvas"]
    for layer in ("bg", "fg"):
        path = root / room[layer]
        where = room[layer]
        if not path.exists():
            continue
        a = C.load_rgba(path)
        if a.shape[:2] != (ch_, cw):
            rep.error(where, "size", f"is {a.shape[1]}x{a.shape[0]}, expected {cw}x{ch_}")
            continue
        _check_alpha(rep, where, a)
        _check_palette(rep, where, a, pal_set)
        op = a[..., 3] > 0
        if layer == "bg":
            if not op.all():
                rep.error(where, "opaque", f"background must be fully opaque; {int((~op).sum())} px are transparent")
            top = _busyness(a[:HEADER_ROWS])
            if top > 0.10:
                rep.warn(where, "header", f"top {HEADER_ROWS} rows are busy ({top:.2f}); the header bar covers them, keep them calm")
            ur = _busyness(a[HEADER_ROWS:32, cw * 5 // 8:])
            if ur > 0.15:
                rep.warn(where, "bubble", f"upper right is busy ({ur:.2f}); the speech bubble sits there")
        else:
            if op.all():
                rep.error(where, "transparent", "foreground is fully opaque; it must be transparent except the desk and props")
            elif not op.any():
                rep.warn(where, "empty", "foreground is empty")
            else:
                fx, fy = (int(v) for v in room.get("feet", man["character"]["feet"]))
                cols = op[ch_ - fy - 16:ch_ - fy, max(0, fx - 16):fx + 16]
                if not (cols.mean(1) > 0.9).any():
                    rep.warn(where, "bench", "nothing solid in front of the character; a bench should hide the boots")


def _sized(rep, root, rel, want, pal_set, what) -> np.ndarray | None:
    """Loads root/rel if present and checks size (w, h), alpha and palette."""
    if not rel or not (root / rel).exists():
        return None
    a = C.load_rgba(root / rel)
    if want and a.shape[:2] != (want[1], want[0]):
        rep.error(rel, "size", f"is {a.shape[1]}x{a.shape[0]}, expected {want[0]}x{want[1]} ({what})")
        return None
    _check_alpha(rep, rel, a)
    _check_palette(rep, rel, a, pal_set)
    return a


def validate_theme(rep: Report, root: Path, man: dict, pal_set):
    """Everything beyond the sheet and the scene layers: portrait, props, ambient, frame, orb, avatars."""
    cw, ch_ = man["canvas"]
    p = man.get("portrait")
    if p:
        n = max(p["states"].values()) + 1
        a = _sized(rep, root, p["sheet"], (p["frame"][0] * n, p["frame"][1]), pal_set, f"{n} heads of {p['frame'][0]}x{p['frame'][1]}")
        if a is not None:
            for state, i in p["states"].items():
                if not (a[:, i * p["frame"][0]:(i + 1) * p["frame"][0], 3] > 0).any():
                    rep.error(p["sheet"], "empty-frame", f"portrait frame {i} ({state}) is empty")
    for prop in man.get("props") or []:
        w, h = prop["frame"]
        _sized(rep, root, prop["sheet"], (w * prop["states"], h), pal_set, f"{prop['states']} states of {w}x{h}")
    names = {prop["name"] for prop in man.get("props") or []}
    for scene in man["scenes"]:
        for place in scene.get("props") or []:
            if place["name"] not in names:
                rep.error(scene["id"], "prop", f"places '{place['name']}', which the theme does not declare")
        for amb in scene.get("ambient") or []:
            w, h = amb["frame"]
            _sized(rep, root, amb["sheet"], (w * amb["frames"], h), pal_set, f"{amb['frames']} frames of {w}x{h}")
            if amb["fps"] > 6:
                rep.error(amb["sheet"], "fps", f"ambient fps {amb['fps']} > 6 would raise the window's frame rate")
        for default, other in (scene.get("animations") or {}).items():
            if other not in man["character"]["animations"]:
                rep.error(scene["id"], "animation", f"replaces '{default}' with '{other}', which the character sheet does not have")

    frame = man.get("frame") or {}
    _sized(rep, root, frame.get("overlay"), (cw, ch_), pal_set, "the canvas")
    pieces = {}
    for edge, con in (frame.get("connectors") or {}).items():
        for kind in ("open", "sealed"):
            piece = con.get(kind)
            if piece:
                a = _sized(rep, root, piece["sprite"], None, pal_set, "")
                if a is not None:
                    pieces[edge, kind] = (a, piece["position"])
    # Seams: windows abut with no gap and any scene meets any other, so the open pieces must agree.
    if ("top", "open") in pieces and ("bottom", "open") in pieces:
        (up, up_pos), (down, down_pos) = pieces["top", "open"], pieces["bottom", "open"]
        if up_pos[0] != down_pos[0] or up.shape[1] != down.shape[1]:
            rep.error("connectors", "seam", f"ladder shaft differs: top x={up_pos[0]} w={up.shape[1]}, bottom x={down_pos[0]} w={down.shape[1]}")
        elif up_pos[1] + up.shape[0] != ch_ or down_pos[1] != 0:
            rep.error("connectors", "seam", "the top piece must reach the top edge and the bottom piece the bottom edge")
        elif not (up[0] == down[-1]).all():
            rep.error("connectors", "seam", "top row of the top piece differs from the bottom row of the bottom piece")
    if ("left", "open") in pieces and ("right", "open") in pieces:
        (west, west_pos), (east, east_pos) = pieces["left", "open"], pieces["right", "open"]
        if west_pos[1] != east_pos[1] or west.shape[0] != east.shape[0]:
            rep.error("connectors", "seam", f"tunnel mouth differs: left y={west_pos[1]} h={west.shape[0]}, right y={east_pos[1]} h={east.shape[0]}")
        elif west_pos[0] != 0 or east_pos[0] + east.shape[1] != cw:
            rep.error("connectors", "seam", "the left piece must start at x=0 and the right piece end at the right edge")
        elif not (west[:, 0] == east[:, -1]).all():
            rep.error("connectors", "seam", "outer column of the left piece differs from the outer column of the right piece")

    orb = man.get("orb") or {}
    size = orb.get("size", 28)
    for key in ("back", "ring", "alert"):
        a = _sized(rep, root, orb.get(key), (size, size), pal_set, "the orb")
        if a is not None:
            yy, xx = np.mgrid[0:size, 0:size]
            outside = (xx + 0.5 - size / 2) ** 2 + (yy + 0.5 - size / 2) ** 2 > (size / 2) ** 2
            if (a[..., 3][outside] > 0).any():
                rep.error(orb[key], "circle", "has pixels outside the inscribed circle; an orb window has no other shape")
    if orb.get("gem"):
        _sized(rep, root, orb["gem"]["sprite"], None, pal_set, "")
    if orb.get("work"):
        w, h = orb["work"]["frame"]
        _sized(rep, root, orb["work"]["sheet"], (w * orb["work"]["frames"], h), pal_set, f"{orb['work']['frames']} frames of {w}x{h}")

    sheet_path = root / man["character"]["sheet"]
    used = _colours(C.load_rgba(sheet_path)) if sheet_path.exists() else None
    for avatar in man.get("avatars") or []:
        for src, dst in avatar["swap"].items():
            s_rgb, d_rgb = C.parse_hex(src), C.parse_hex(dst)
            if used is not None and s_rgb not in used:
                rep.warn(avatar["id"], "swap", f"swaps #{src}, which the character sheet does not use")
            if pal_set is not None and d_rgb not in pal_set:
                rep.error(avatar["id"], "swap", f"swaps to #{dst}, which is not in the palette")


def validate_set(root: Path, man: dict, palette: str | None, complete=False, centre_tol=1.5, drift_tol=1.0) -> Report:
    rep = Report()
    pal_set = None
    pal = C.load_palette(palette) if palette else C.theme_palette(man)
    if pal is not None:
        pal_set = {tuple(int(v) for v in c) for c in pal}
        if len(pal_set) > C.MAX_COLOURS:
            rep.error(palette or "theme.json", "palette-size", f"palette has {len(pal_set)} colours, the contract allows at most {C.MAX_COLOURS}")
    files = C.asset_files(man)
    present = [f for f in files if (root / f).exists()]
    for f in files:
        if f not in present:
            (rep.error if complete else rep.warn)(f, "missing", "not in this set")
    if not present:
        rep.error(str(root), "missing", "no manifest assets found here")
        return rep
    if man["character"]["sheet"] in present:
        validate_sheet(rep, root / man["character"]["sheet"], man, pal_set, centre_tol, drift_tol)
    for room in man["rooms"]:
        validate_room(rep, room, root, man, pal_set)
    validate_theme(rep, root, man, pal_set)
    allc = set()
    for f in present:
        allc |= _colours(C.load_rgba(root / f))
    if len(allc) > C.MAX_COLOURS:
        rep.error("set", "colour-count", f"{len(allc)} distinct colours across {len(present)} files; "
                                         f"the shared palette allows at most {C.MAX_COLOURS}")
    return rep


# ---------- CLI ----------

def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--manifest")
    sub = ap.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("split", help="cut a horizontal strip into frames")
    s.add_argument("strip"); s.add_argument("-o", "--output", required=True, help="output folder")
    s.add_argument("--frames", type=int); s.add_argument("--anim")
    s.add_argument("--gaps", action="store_true", help="cut at transparent gaps instead of equal widths")

    s = sub.add_parser("assemble", help="build character/sheet.png from strips or frames")
    s.add_argument("source"); s.add_argument("-o", "--output", required=True)
    s.add_argument("--fill-from", help="existing sheet to take missing rows from")

    s = sub.add_parser("validate", help="check a sheet or a whole asset set against the manifest")
    s.add_argument("--assets", help="folder laid out like Sources/Nook/Assets (default: that folder)")
    s.add_argument("--sheet", help="validate just this sheet file")
    s.add_argument("--palette", help="palette name or .hex path every pixel must belong to")
    s.add_argument("--complete", action="store_true", help="missing files are errors")
    s.add_argument("--centre-tol", type=float, default=1.5)
    s.add_argument("--drift-tol", type=float, default=1.0)
    s.add_argument("--json", help="write the findings here")
    a = ap.parse_args(argv)
    man = C.load_manifest(a.manifest)

    try:
        if a.cmd == "split":
            n = a.frames or (man["character"]["animations"][a.anim]["frames"] if a.anim else None)
            if not n:
                ap.error("split needs --frames N or --anim NAME")
            out = Path(a.output)
            for i, fr in enumerate(split_strip(C.load_rgba(a.strip), n, a.gaps)):
                C.save_rgba(fr, out / f"{i:02d}.png")
            print(f"split {a.strip} into {n} frames -> {out}/")
            return 0
        if a.cmd == "assemble":
            sheet, notes = assemble(Path(a.source), man, Path(a.fill_from) if a.fill_from else None)
            C.save_rgba(sheet, a.output)
            print("\n".join(notes) + f"\nwrote {a.output} ({sheet.shape[1]}x{sheet.shape[0]})")
            return 0
        if a.sheet:
            rep = Report()
            pal_set = {tuple(int(v) for v in c) for c in C.load_palette(a.palette)} if a.palette else None
            validate_sheet(rep, Path(a.sheet), man, pal_set, a.centre_tol, a.drift_tol)
            target = a.sheet
        else:
            target = a.assets or str(C.ASSETS)
            rep = validate_set(Path(target), man, a.palette, a.complete, a.centre_tol, a.drift_tol)
    except (ValueError, KeyError, FileNotFoundError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 2
    rep.print()
    if a.json:
        Path(a.json).write_text(json.dumps(rep.items, indent=2))
    ok = not rep.errors
    print(f"{'PASS' if ok else 'FAIL'}: {target}  ({len(rep.errors)} errors, {len(rep.warnings)} warnings)")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
