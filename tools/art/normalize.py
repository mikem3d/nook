#!/usr/bin/env python3
"""Turn raw AI "pixel art" into contract-sized Nook art (see docs/ART.md, docs/ART_PIPELINE.md).

  normalize.py room-bg         raw.png -o rooms/study_bg.png --palette sweetie16
  normalize.py room-fg         raw.png -o rooms/study_fg.png --palette sweetie16
  normalize.py character-frame raw.png -o ref.png            --palette sweetie16 --outline outer
  normalize.py character-strip raw.png -o strips/idle_sip.png --anim idle_sip --palette sweetie16
  normalize.py prop            raw.png -o mug.png            --palette sweetie16

Steps: detect the fake-pixel grid -> sample one colour per cell from its core by median or vote
(never averaging across cell borders) -> quantise to the shared palette -> binary alpha -> clean orphan
pixels -> optional 1px outline -> fit to the contract size.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common as C  # noqa: E402

T = C.TRANSPARENT
MODES = ("room-bg", "room-fg", "character-frame", "character-strip", "prop")


# ---------- grid detection ----------

def _edge_profile(rgb: np.ndarray, axis: int) -> np.ndarray:
    """Edge energy per pixel boundary along `axis` (1 = x). prof[i] is the boundary before pixel i."""
    d = np.abs(np.diff(rgb.astype(np.float32), axis=axis)).sum(-1)
    # keep strong edges only: sensor-style noise and JPEG 8x8 block seams are weak but
    # periodic, and would otherwise be mistaken for the art grid
    d[d < max(12.0, 6 * float(np.median(d)), 0.25 * float(np.percentile(d, 99.5)))] = 0
    # non-maximum suppression along the axis: a blurred edge several px wide collapses to
    # its centre, so the fold below stays sharp however soft the source is
    d = np.moveaxis(d, axis, 0)
    pad = np.pad(d, ((1, 1), (0, 0)))
    d = np.where((d >= pad[:-2]) & (d > pad[2:]), d, 0)
    d = np.moveaxis(d, 0, axis)
    prof = d.sum(axis=1 - axis)
    return np.concatenate([[0.0], prof])


def _fold_score(prof: np.ndarray, s: float, win: float) -> tuple[float, float]:
    """Fold the edge profile modulo s. Returns (score, phase).

    score = share of edge energy inside the best window of width `win` px, minus
    the share a uniform profile would give (win/s). True grids concentrate edges
    at one phase; the baseline stops small periods from winning by default.
    """
    total = prof.sum()
    if total <= 0:
        return 0.0, 0.0
    nb = max(4, int(np.ceil(s * 4)))
    pos = np.arange(len(prof), dtype=np.float64)
    bins = np.floor((pos % s) / s * nb).astype(int) % nb
    hist = np.bincount(bins, weights=prof, minlength=nb)
    wb = max(1, int(round(win / s * nb)))
    ring = np.concatenate([hist, hist[:wb - 1]]) if wb > 1 else hist
    sums = np.convolve(ring, np.ones(wb), mode="valid")[:nb]
    k = int(np.argmax(sums))
    # phase = energy-weighted circular mean of the boundary positions inside the best window
    inside = ((bins - k) % nb) < wb
    ang = (pos[inside] % s) / s * 2 * np.pi
    wgt = prof[inside]
    phase = (np.arctan2((wgt * np.sin(ang)).sum(), (wgt * np.cos(ang)).sum()) / (2 * np.pi) * s) % s
    return float(sums[k] / total - wb / nb), float(phase)


def detect_grid(rgb: np.ndarray, s_min: float = 2.5, s_max: float | None = None) -> dict:
    """Estimate the fake-pixel size (source px per art px) and the grid phase.

    Runs twice, on the raw image and on a lightly blurred copy (noise on soft, large
    fake pixels otherwise drowns the real edges), and keeps the more confident answer.
    Pass s_min/s_max to rule out harmonics when the expected size is roughly known.
    """
    from PIL import Image, ImageFilter
    h, w = rgb.shape[:2]
    s_max = s_max or max(s_min + 1, min(64.0, min(h, w) / 6))
    results = []
    for blur in (0.0, 1.5):
        img = rgb if not blur else np.array(Image.fromarray(rgb.astype(np.uint8), "RGB").filter(ImageFilter.GaussianBlur(blur)))
        px, py = _edge_profile(img, 1), _edge_profile(img, 0)

        def score(s, frac, px=px, py=py):
            win = frac * s
            (sx, fx), (sy, fy) = _fold_score(px, s, win), _fold_score(py, s, win)
            return sx + sy, fx, fy

        def kappa(s, win_px, px=px, py=py):
            """Concentration of edge energy within win_px of the grid lines: 0 = what scattered
            edges would give, 1 = every edge on the grid. Comparable across periods."""
            out = 0.0
            for prof in (px, py):
                nb = max(4, int(np.ceil(s * 4)))
                base = min(0.95, max(1, int(round(win_px / s * nb))) / nb)
                out += _fold_score(prof, s, win_px)[0] / (1 - base)
            return out / 2

        coarse = np.arange(s_min, s_max + 1e-9, 0.05)
        scores = np.array([score(s, 0.2)[0] for s in coarse])
        best = float(coarse[np.nonzero(scores >= 0.98 * scores.max())[0][-1]])
        # Harmonics. Every edge of a grid with period s also lies on s/2 and s/3, and most lie
        # on 2s. Compare neighbours with the SAME absolute window: move down only if the smaller
        # period explains clearly more edges, move up only if the larger one loses almost none.
        moved = True
        while moved:
            moved = False
            for k in (2, 3):
                c = best / k
                if c >= s_min and kappa(c, 0.2 * best) >= kappa(best, 0.2 * best) + 0.08:
                    best, moved = c, True
                    break
        moved = True
        while moved:
            moved = False
            for k in (5, 3, 2):
                c = best * k
                if c <= s_max and kappa(c, 0.2 * best) >= kappa(best, 0.2 * best) - 0.05:
                    best, moved = c, True
                    break
        fine = np.arange(max(s_min, best - 0.06), best + 0.06, 0.0005)
        fscores = [score(s, 0.12) for s in fine]
        i = int(np.argmax([f[0] for f in fscores]))
        sc, fx, fy = fscores[i]
        results.append({"scale": round(float(fine[i]), 4), "phase": [round(fx, 3), round(fy, 3)],
                        "confidence": round(sc / 2, 3), "preblur": blur})
    return max(results, key=lambda r: r["confidence"])


# ---------- sampling ----------

def _cells(n_src: int, s: float, phase: float) -> list[tuple[int, int]]:
    """Central pixel ranges for every grid cell along one axis.

    The central half of the cell, but never less than ~2 source px: tiny fake pixels
    need every sample they can get, large ones can afford to skip their soft rims.
    """
    keep = min(0.75, max(0.5, 2.0 / s))
    start = phase % s
    if start >= 0.5 * s:
        start -= s
    out = []
    x = start
    while x + 0.5 * s <= n_src:
        a = int(np.floor(x + (0.5 - keep / 2) * s + 0.5))
        b = int(np.floor(x + (0.5 + keep / 2) * s + 0.5))
        a = min(max(a, 0), n_src - 1)
        b = min(max(b, a + 1), n_src)
        out.append((a, b))
        x += s
    return out


def sample_median(rgba: np.ndarray, sx, sy, phase) -> np.ndarray:
    """Per-cell median colour (RGBA float). Used to derive an auto palette."""
    xs, ys = _cells(rgba.shape[1], sx, phase[0]), _cells(rgba.shape[0], sy, phase[1])
    out = np.zeros((len(ys), len(xs), 4), np.float32)
    for j, (y0, y1) in enumerate(ys):
        band = rgba[y0:y1]
        for i, (x0, x1) in enumerate(xs):
            out[j, i] = np.median(band[:, x0:x1].reshape(-1, 4), axis=0)
    return out


def sample_labels(labels: np.ndarray, n_labels: int, sx, sy, phase, method: str) -> np.ndarray:
    """One label per cell: the most common label in the cell's central half, or its centre pixel."""
    xs, ys = _cells(labels.shape[1], sx, phase[0]), _cells(labels.shape[0], sy, phase[1])
    out = np.zeros((len(ys), len(xs)), np.int16)
    for j, (y0, y1) in enumerate(ys):
        band = labels[y0:y1]
        for i, (x0, x1) in enumerate(xs):
            if method == "centre":
                out[j, i] = labels[(y0 + y1) // 2, (x0 + x1) // 2]
            else:
                out[j, i] = np.bincount(band[:, x0:x1].ravel(), minlength=n_labels).argmax()
    return out


# ---------- cleanup passes ----------

def _neighbours(idx: np.ndarray) -> np.ndarray:
    """Stack of the 8 neighbours of every pixel (edges replicate), shape (8, h, w)."""
    p = np.pad(idx, 1, mode="edge")
    h, w = idx.shape
    return np.stack([p[1 + dy:1 + dy + h, 1 + dx:1 + dx + w]
                     for dy in (-1, 0, 1) for dx in (-1, 0, 1) if (dy, dx) != (0, 0)])


def remove_orphans(idx: np.ndarray, level: str = "safe") -> tuple[np.ndarray, int]:
    """Replace isolated pixels (no 8-neighbour of the same colour) with the commonest neighbour.

    safe: only stray opaque specks floating in transparency and 1px pinholes in solid areas.
          Keeps 1px eyes, glints and stars: at 32x32 a single pixel is often the whole feature.
    all:  every isolated pixel, whatever it is. Check the preview afterwards.
    """
    if level == "off":
        return idx, 0
    nb = _neighbours(idx)
    isolated = ~(nb == idx[None]).any(0)
    if level == "safe":
        speck = (idx >= 0) & (nb == T).all(0)
        pinhole = (idx == T) & (nb != T).all(0)
        isolated &= speck | pinhole
    out = idx.copy()
    for y, x in zip(*np.nonzero(isolated)):
        vals, cnt = np.unique(nb[:, y, x], return_counts=True)
        out[y, x] = vals[int(np.argmax(cnt))]
    return out, int(isolated.sum())


def add_outline(idx: np.ndarray, dark: int, kind: str) -> np.ndarray:
    """outer: transparent pixels 4-adjacent to the sprite become dark. inner: the sprite's rim does."""
    if kind == "none":
        return idx
    op = np.pad(idx >= 0, 1)
    out = idx.copy()
    if kind == "outer":
        near = op[:-2, 1:-1] | op[2:, 1:-1] | op[1:-1, :-2] | op[1:-1, 2:]
        out[(idx == T) & near] = dark
    else:
        tr = ~np.pad(idx >= 0, 1, constant_values=True)
        near = tr[:-2, 1:-1] | tr[2:, 1:-1] | tr[1:-1, :-2] | tr[1:-1, 2:]
        out[(idx >= 0) & near] = dark
    return out


# ---------- fitting ----------

def bbox(mask: np.ndarray):
    ys, xs = np.nonzero(mask)
    if len(ys) == 0:
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def fit_canvas(idx: np.ndarray, w: int, h: int, opaque: bool, warn: list) -> np.ndarray:
    """Centre crop / pad to the canvas. Opaque layers pad by repeating the edge."""
    sh, sw = idx.shape
    if (sw, sh) == (w, h):
        return idx
    warn.append(f"native size {sw}x{sh} is not {w}x{h}: centre cropped/padded")
    x0, y0 = max(0, (sw - w) // 2), max(0, (sh - h) // 2)
    idx = idx[y0:y0 + h, x0:x0 + w]
    ph, pw = h - idx.shape[0], w - idx.shape[1]
    pad = ((ph // 2, ph - ph // 2), (pw // 2, pw - pw // 2))
    return np.pad(idx, pad, mode="edge") if opaque else np.pad(idx, pad, constant_values=T)


def place_in_frame(cell: np.ndarray, fw: int, fh: int, anchor: str, ground_row: int | None, warn: list, tag="") -> np.ndarray:
    """Put a sprite into an fw x fh frame: feet on the bottom edge, centred horizontally.

    anchor feet: centre of the lowest 3 rows goes to fw/2 (ignores arms, props, marks).
    anchor bbox: centre of the bounding box goes to fw/2.
    anchor cell: the strip cell's own centre goes to fw/2 (keeps the generator's motion).
    ground_row: row that lands on the bottom edge (None = this frame's lowest pixel).
    """
    out = np.full((fh, fw), T, np.int16)
    bb = bbox(cell >= 0)
    if bb is None:
        warn.append(f"{tag}empty frame")
        return out
    x0, y0, x1, y1 = bb
    if anchor == "feet":
        fx = np.nonzero((cell[max(y0, y1 - 3):y1] >= 0).any(0))[0]
        cx = (fx.min() + fx.max() + 1) / 2
    elif anchor == "bbox":
        cx = (x0 + x1) / 2
    else:
        cx = cell.shape[1] / 2
    dx = int(round(fw / 2 - cx))
    dy = fh - (y1 if ground_row is None else ground_row)
    clipped = 0
    ys, xs = np.nonzero(cell >= 0)
    ty, tx = ys + dy, xs + dx
    ok = (ty >= 0) & (ty < fh) & (tx >= 0) & (tx < fw)
    clipped = int((~ok).sum())
    out[ty[ok], tx[ok]] = cell[ys[ok], xs[ok]]
    if clipped:
        warn.append(f"{tag}{clipped} px fell outside the {fw}x{fh} frame and were clipped")
    return out


# ---------- pipeline ----------

def detect_key(rgba: np.ndarray, key: str, warn: list):
    """Returns the background key colour (r,g,b) or None if the source alpha should be used."""
    if key == "none":
        return None
    if key == "magenta":
        return (255, 0, 255)
    if key != "auto":
        return C.parse_hex(key)
    if (rgba[..., 3] < 128).mean() > 0.01:
        return None  # the source already has real transparency
    h, w = rgba.shape[:2]
    k = max(2, min(h, w) // 25)
    corners = np.stack([np.median(p[..., :3].reshape(-1, 3), axis=0) for p in
                        (rgba[:k, :k], rgba[:k, -k:], rgba[-k:, :k], rgba[-k:, -k:])])
    if np.ptp(corners, axis=0).max() > 40:
        warn.append("corner colours disagree; background key guess may be wrong (pass --key)")
    return tuple(int(v) for v in np.median(corners, axis=0))


def normalize(rgba: np.ndarray, mode: str, pal_spec: str = "auto", pal_refs=None, colours=C.MAX_COLOURS,
              scale=None, phase=None, sample="median", alpha_threshold=128, key="auto", outline="none",
              orphans="safe", frames=None, anchor="feet", ground="frame", fit_height=None,
              size=None, manifest=None) -> tuple[np.ndarray, dict]:
    man = manifest or C.load_manifest()
    cw, ch = man["canvas"]
    fw, fh = man["character"]["frame"]
    warn: list[str] = []
    transparent_mode = mode != "room-bg"
    h, w = rgba.shape[:2]

    # 1. grid
    rep: dict = {"mode": mode, "source": [w, h]}
    if scale:
        sx = sy = float(scale)
        ph = list(phase or (0.0, 0.0))
        rep["grid"] = {"scale": sx, "phase": ph, "confidence": None, "source": "override"}
    elif mode.startswith("room") and (w, h) == (cw, ch):
        sx = sy = 1.0; ph = [0.0, 0.0]
        rep["grid"] = {"scale": 1.0, "phase": ph, "confidence": None, "source": "already native"}
    else:
        g = detect_grid(rgba[..., :3])
        sx = sy = g["scale"]; ph = g["phase"]
        rep["grid"] = dict(g, source="detected")
        if g["confidence"] < 0.15:
            warn.append(f"weak pixel grid (confidence {g['confidence']}): the source may not be on a grid; check the result or pass --scale")
        if mode.startswith("room"):
            nat = (w / sx, h / sy)
            if abs(nat[0] - cw) / cw <= 0.04 and abs(nat[1] - ch) / ch <= 0.04:
                # full-frame image whose grid agrees with the canvas: lock to it exactly
                sx, sy, ph = w / cw, h / ch, [0.0, 0.0]
                rep["grid"].update(scale=[round(sx, 4), round(sy, 4)], phase=ph, source="detected, snapped to canvas")
            else:
                warn.append(f"detected grid gives {nat[0]:.0f}x{nat[1]:.0f} art pixels, not {cw}x{ch}: "
                            "resampled off-grid to the canvas, expect artefacts (regenerate at the right pixel size, or pass --scale)")
                sx, sy, ph = w / cw, h / ch, [0.0, 0.0]
                rep["grid"].update(source="off-grid fallback")

    # 2. background key and palette
    keyrgb = detect_key(rgba, key, warn) if transparent_mode else None
    rep["key"] = list(keyrgb) if keyrgb else None

    def build_palette(sx, sy):
        if pal_spec == "auto" and not pal_refs:
            med = sample_median(rgba, sx, sy, ph)
            keep = med[..., 3] >= alpha_threshold
            if keyrgb is not None:
                keep &= np.abs(med[..., :3] - np.array(keyrgb, np.float32)).sum(-1) > 90
            return C.merge_close(C.median_cut(np.round(med[keep][:, :3]).astype(np.uint8), colours))
        return C.load_palette(pal_spec, pal_refs, colours)

    def run(sx, sy):
        pal = build_palette(sx, sy)
        if len(pal) > C.MAX_COLOURS:
            warn.append(f"palette has {len(pal)} colours; the contract allows at most {C.MAX_COLOURS}")
        vote = np.vstack([pal, [keyrgb]]).astype(np.uint8) if keyrgb is not None else pal
        if sample == "median":
            med = sample_median(rgba, sx, sy, ph)
            lab = C.nearest_index(np.round(med[..., :3]).astype(np.uint8), vote).reshape(med.shape[:2])
            lab[med[..., 3] < alpha_threshold] = len(pal)
        else:
            labels = C.nearest_index(rgba[..., :3], vote).reshape(h, w)
            labels[rgba[..., 3] < alpha_threshold] = len(pal)
            lab = sample_labels(labels, len(pal) + 1, sx, sy, ph, sample)
        idx = lab.astype(np.int16)
        idx[idx >= len(pal)] = T
        if not transparent_mode and (idx == T).any():
            warn.append("room-bg source had transparent pixels; filled with the darkest palette colour")
            idx[idx == T] = C.darkest(pal)
        return pal, idx

    pal, idx = run(sx, sy)

    # 3. character scale fallback: the sprite must fit the frame
    if mode in ("character-frame", "character-strip"):
        bb = bbox(idx >= 0)
        if bb is None:
            raise SystemExit("error: nothing opaque found (wrong --key?)")
        content_h = bb[3] - bb[1]
        want = fit_height or (fh if content_h > fh else None)
        if want and content_h != want:
            f = content_h / want
            if not fit_height:
                warn.append(f"sprite is {content_h} art px tall on its own grid, frame is {fh}: resampled off-grid "
                            f"by x{f:.2f}. Prefer regenerating smaller, or reuse one --scale for every strip so rows match")
            sx, sy = sx * f, sy * f
            ph = [0.0, 0.0]
            pal, idx = run(sx, sy)
        rep["effective_scale"] = round(sx, 4)

    # 4. fit to the contract shape, then clean and outline
    dark = C.darkest(pal)

    def finish(a):
        a, n = remove_orphans(a, orphans)
        rep["orphans_removed"] = rep.get("orphans_removed", 0) + n
        return add_outline(a, dark, outline)

    if mode == "room-bg":
        out = finish(fit_canvas(idx, cw, ch, True, warn))
    elif mode == "room-fg":
        out = finish(fit_canvas(idx, cw, ch, False, warn))
    elif mode == "prop":
        bb = bbox(idx >= 0)
        if bb is None:
            raise SystemExit("error: nothing opaque found (wrong --key?)")
        out = idx[bb[1]:bb[3], bb[0]:bb[2]]
        if size:
            out = place_in_frame(out, size[0], size[1], "bbox", None, warn)
        out = finish(out)
    else:
        n = 1 if mode == "character-frame" else frames
        if not n:
            raise SystemExit("error: character-strip needs --frames N or --anim NAME")
        spans = C.split_columns(idx >= 0, n, use_gaps=True)
        bb = bbox(idx >= 0)
        ground_row = bb[3] if ground == "strip" else None
        cells = []
        for k, (x0, x1) in enumerate(spans):
            fr = place_in_frame(idx[:, x0:x1], fw, fh, anchor, ground_row, warn, tag=f"frame {k}: ")
            cells.append(finish(fr))
        out = np.concatenate(cells, axis=1)
        rep["frames"] = n

    used = np.unique(out[out >= 0])
    rep.update(output=[int(out.shape[1]), int(out.shape[0])], palette_size=int(len(pal)),
               colours_used=int(len(used)), warnings=warn)
    return C.index_to_rgba(out, pal), rep


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mode", choices=MODES)
    ap.add_argument("input")
    ap.add_argument("-o", "--output", required=True)
    ap.add_argument("--palette", default="auto", help=f"name ({', '.join(C.available_palettes())}), a .hex path, or 'auto'")
    ap.add_argument("--palette-ref", nargs="*", help="with --palette auto: derive the palette from these images (default: the input itself)")
    ap.add_argument("--colours", type=int, default=C.MAX_COLOURS, help="palette size for --palette auto")
    ap.add_argument("--scale", type=float, help="override: source pixels per art pixel")
    ap.add_argument("--phase", type=float, nargs=2, metavar=("X", "Y"), help="grid offset in source px, with --scale")
    ap.add_argument("--sample", choices=("median", "mode", "centre"), default="median",
                    help="per cell: channel median of the cell core (default, best against noise), most common palette colour, or the centre pixel")
    ap.add_argument("--alpha-threshold", type=int, default=128)
    ap.add_argument("--key", default="auto", help="background to key out: auto, none, magenta or RRGGBB")
    ap.add_argument("--outline", choices=("none", "outer", "inner"), default="none", help="1px darkest-colour outline (characters)")
    ap.add_argument("--orphans", choices=("off", "safe", "all"), default="safe")
    ap.add_argument("--frames", type=int, help="character-strip: number of frames")
    ap.add_argument("--anim", help="character-strip: take the frame count from the manifest")
    ap.add_argument("--anchor", choices=("feet", "bbox", "cell"), default="feet")
    ap.add_argument("--ground", choices=("frame", "strip"), default="frame",
                    help="frame: every frame's lowest pixel sits on the bottom edge (contract). strip: keep jumps")
    ap.add_argument("--fit-height", type=int, help="characters: force the sprite's height in art px (off-grid resample)")
    ap.add_argument("--size", type=int, nargs=2, metavar=("W", "H"), help="prop: pad to this size, bottom-centre")
    ap.add_argument("--manifest")
    ap.add_argument("--report", help="write a JSON report here")
    a = ap.parse_args(argv)

    man = C.load_manifest(a.manifest)
    frames = a.frames
    if a.anim:
        if a.anim not in man["character"]["animations"]:
            ap.error(f"unknown animation '{a.anim}'")
        frames = man["character"]["animations"][a.anim]["frames"]
    try:
        out, rep = normalize(C.load_rgba(a.input), a.mode, a.palette, a.palette_ref, a.colours, a.scale, a.phase,
                             a.sample, a.alpha_threshold, a.key, a.outline, a.orphans, frames, a.anchor,
                             a.ground, a.fit_height, a.size, man)
    except ValueError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2
    C.save_rgba(out, a.output)
    if a.report:
        Path(a.report).write_text(json.dumps(rep, indent=2))
    g = rep["grid"]
    print(f"{a.mode}: {rep['source'][0]}x{rep['source'][1]} -> {rep['output'][0]}x{rep['output'][1]}  "
          f"scale {g['scale']} ({g['source']}, confidence {g['confidence']})  "
          f"{rep['colours_used']}/{rep['palette_size']} colours  orphans removed {rep.get('orphans_removed', 0)}  -> {a.output}")
    for wmsg in rep["warnings"]:
        print(f"  warning: {wmsg}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
