#!/usr/bin/env python3
"""Render previews of an asset set so a candidate can be judged at a glance.

  preview.py --assets set/ -o out/preview/

Writes (all nearest-neighbour, default 4x):
  contact_sheet.png            every animation row, labelled with frames / fps / loop
  anim_<name>.gif              one GIF per animation at the manifest fps
  composite_<scene>.png         the chamber as the engine draws it: bg, props, ambient, character,
                                fg, the frame and its sealed connector pieces
  composite_<scene>_<anim>.gif  the same, animated (--anims, default idle_breathe and type; "type"
                                becomes the scene's own work pose if it declares one)
  stack_vertical.png            three chambers stacked with NO gap, ladders open: judge the seams
  stack_horizontal.png          two chambers side by side, tunnel open
  stack_mountain.png            every scene in a two-column mountain, all connectors open
  orbs.png                      the minimised orb per state, for each avatar variant

Files missing from the set fall back to Sources/Nook/Assets, so a new room can be
previewed with the current character and the other way round (disable with --no-fallback).
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common as C  # noqa: E402

BACKDROP = (58, 60, 72, 255)
CHECK = ((72, 74, 88, 255), (64, 66, 80, 255))
LABEL_W = 190


def up(img: Image.Image, k: int) -> Image.Image:
    return img.resize((img.width * k, img.height * k), Image.NEAREST)


def checker(w: int, h: int, cell: int = 4) -> Image.Image:
    yy, xx = np.mgrid[0:h, 0:w]
    a = np.where((((xx // cell) + (yy // cell)) % 2 == 0)[..., None], CHECK[0], CHECK[1]).astype(np.uint8)
    return Image.fromarray(a, "RGBA")


def contact_sheet(sheet: np.ndarray, man: dict, k: int) -> Image.Image:
    ch = man["character"]
    fw, fh = ch["frame"]
    rows = C.anim_rows(man)
    gap = 6
    W = LABEL_W + ch["columns"] * fw * k + gap
    H = len(rows) * (fh * k + gap) + gap + 44
    out = Image.new("RGBA", (W, H), BACKDROP)
    d = ImageDraw.Draw(out)
    for i, (name, spec) in enumerate(rows):
        y = gap + i * (fh * k + gap)
        d.text((8, y + 6), f"{spec['row']:02d} {name}", fill=(240, 240, 240, 255))
        d.text((8, y + 22), f"{spec['frames']} frames @ {spec['fps']} fps", fill=(170, 175, 190, 255))
        d.text((8, y + 38), "loops" if spec["looping"] else "plays once", fill=(170, 175, 190, 255))
        strip = Image.fromarray(np.ascontiguousarray(sheet[spec["row"] * fh:(spec["row"] + 1) * fh]), "RGBA")
        cell = checker(strip.width, fh)
        cell.alpha_composite(strip)
        out.paste(up(cell, k), (LABEL_W, y))
        for c in range(ch["columns"] + 1):  # frame boundaries; unused columns are dimmed
            d.line([(LABEL_W + c * fw * k, y), (LABEL_W + c * fw * k, y + fh * k - 1)], fill=(30, 30, 40, 255))
        if spec["frames"] < ch["columns"]:
            x0 = LABEL_W + spec["frames"] * fw * k
            d.rectangle([x0 + 1, y, LABEL_W + ch["columns"] * fw * k, y + fh * k - 1], fill=(40, 42, 52, 255))
    # palette actually used by the sheet
    cols = np.unique(sheet[sheet[..., 3] > 0][:, :3], axis=0)
    y = H - 38
    d.text((8, y + 8), f"{len(cols)} colours in sheet", fill=(240, 240, 240, 255))
    sw = max(6, min(24, (W - LABEL_W - gap) // max(1, len(cols))))
    for i, c in enumerate(cols[np.argsort(C.luma(cols))]):
        d.rectangle([LABEL_W + i * sw, y, LABEL_W + (i + 1) * sw - 2, y + 26], fill=tuple(int(v) for v in c) + (255,))
    return out


def save_gif(frames: list[Image.Image], path: Path, fps: float):
    path.parent.mkdir(parents=True, exist_ok=True)
    rgb = [f.convert("RGB") for f in frames]
    rgb[0].save(path, save_all=True, append_images=rgb[1:], duration=max(20, round(1000 / fps)), loop=0, disposal=1)


def anim_frames(sheet: np.ndarray, spec: dict, fw: int, fh: int) -> list[Image.Image]:
    return [Image.fromarray(np.ascontiguousarray(C.frame_of(sheet, spec["row"], c, fw, fh)), "RGBA") for c in range(spec["frames"])]


class Chamber:
    """Draws a scene the way RoomScene.swift does. Positions are bottom-left, from the canvas bottom-left."""

    def __init__(self, man: dict, find):
        self.man, self.find, self.cache = man, find, {}

    def img(self, rel: str | None) -> Image.Image | None:
        if rel and rel not in self.cache:
            path = self.find(rel)
            self.cache[rel] = Image.open(path).convert("RGBA") if path else None
        return self.cache.get(rel)

    def cell(self, rel: str, frame, index: int) -> Image.Image | None:
        sheet = self.img(rel)
        return sheet.crop((index * frame[0], 0, (index + 1) * frame[0], frame[1])) if sheet else None

    def put(self, canvas: Image.Image, im: Image.Image | None, pos):
        if im is not None:
            canvas.alpha_composite(im, (int(pos[0]), int(canvas.height - pos[1] - im.height)))

    def draw(self, scene: dict, actor: Image.Image | None, edges=(), tick: int = 0, avatar: int = 0) -> Image.Image | None:
        bg = self.img(scene["bg"])
        if bg is None or bg.size != tuple(self.man["canvas"]):
            return None
        out = bg.copy()
        layers = []
        props = {p["name"]: p for p in self.man.get("props") or []}
        for place in scene.get("props") or []:
            prop = props.get(place["name"])
            if prop and place["name"] != "hourglass":   # the engine hides the hourglass until a turn runs long
                layers.append((place.get("z", prop["z"]), self.cell(prop["sheet"], prop["frame"], min(prop["states"] // 2, prop["states"] - 1)), place["position"]))
        spots = {h["id"]: h for h in self.man.get("hotspots") or []}
        for place in scene.get("hotspots") or []:
            spot = spots.get(place["id"])
            if spot:   # idle, at its fullest level
                layers.append((place.get("z", spot["z"]), self.cell(spot["sheet"], spot["frame"], spot["levels"] - 1), place["position"]))
        for amb in scene.get("ambient") or []:
            pos = amb["position"]
            if amb.get("path"):
                to = amb["path"]["to"]
                pos = [(pos[0] + to[0]) // 2, (pos[1] + to[1]) // 2]
            layers.append((amb["z"], self.cell(amb["sheet"], amb["frame"], tick % amb["frames"]), pos))
        if actor is not None:
            layers.append((1, recolour(actor, self.man, avatar), [scene["feet"][0] - actor.width // 2, scene["feet"][1]]))
        layers.append((2, self.img(scene["fg"]), [0, 0]))
        for _, im, pos in sorted(layers, key=lambda l: l[0]):
            self.put(out, im, pos)
        frame = self.man.get("frame") or {}
        self.put(out, self.img(frame.get("overlay")), [0, 0])
        for edge, con in (frame.get("connectors") or {}).items():
            piece = con.get("open" if edge in edges else "sealed")
            if piece:
                self.put(out, self.img(piece["sprite"]), piece["position"])
        return out


def recolour(im: Image.Image, man: dict, avatar: int) -> Image.Image:
    """The engine's avatar palette swap (PaletteSwap.swift): exact colour match on the original pixels."""
    avatars = man.get("avatars") or []
    if not 0 < avatar < len(avatars):
        return im
    a = np.array(im)
    out = a.copy()
    for src, dst in avatars[avatar]["swap"].items():
        hit = (a[..., :3] == C.parse_hex(src)).all(-1) & (a[..., 3] == 255)
        out[hit, :3] = C.parse_hex(dst)
    return Image.fromarray(out, "RGBA")


def work_anim(man: dict, scene: dict, name: str) -> str:
    other = (scene.get("animations") or {}).get(name)
    return other if other in man["character"]["animations"] else name


def orbs(ch: Chamber, man: dict, k: int) -> Image.Image | None:
    orb, p = man.get("orb") or {}, man.get("portrait")
    if not p or not orb.get("ring"):
        return None
    size, states = orb.get("size", 28), sorted(p["states"].items(), key=lambda kv: kv[1])
    n = max(len(man.get("avatars") or []), 1)
    out = Image.new("RGBA", ((size + 4) * len(states) + 4, (size + 4) * n + 4), BACKDROP)
    for row in range(n):
        for col, (state, index) in enumerate(states):
            cell = Image.new("RGBA", (size, size))
            ch.put(cell, ch.img(orb.get("back")), [0, 0])
            ch.put(cell, recolour(ch.cell(p["sheet"], p["frame"], index), man, row), orb.get("portraitPosition", [4, 4]))
            ch.put(cell, ch.img(orb["ring"]), [0, 0])
            if state == "alert":
                ch.put(cell, ch.img(orb.get("alert")), [0, 0])
            if state == "working" and orb.get("work"):
                ch.put(cell, ch.cell(orb["work"]["sheet"], orb["work"]["frame"], 2), orb["work"]["position"])
            if orb.get("gem"):
                ch.put(cell, ch.img(orb["gem"]["sprite"]), orb["gem"]["position"])
            out.alpha_composite(cell, (4 + col * (size + 4), 4 + row * (size + 4)))
    return up(out, k)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--assets", default=str(C.ASSETS), help="folder laid out like Sources/Nook/Assets")
    ap.add_argument("-o", "--output", required=True)
    ap.add_argument("--scale", type=int, default=4)
    ap.add_argument("--anims", nargs="*", default=["idle_breathe", "type"], help="animations for the composite GIFs")
    ap.add_argument("--no-fallback", action="store_true")
    ap.add_argument("--manifest")
    a = ap.parse_args(argv)
    man = C.load_manifest(a.manifest)
    root, out, k = Path(a.assets), Path(a.output), a.scale
    fw, fh = man["character"]["frame"]

    def find(rel: str) -> Path | None:
        for base in [root] + ([] if a.no_fallback else [C.ASSETS]):
            if (base / rel).exists():
                if base != root:
                    print(f"  note: {rel} not in {root}, using the installed one")
                return base / rel
        return None

    written = []
    sheet_path = find(man["character"]["sheet"])
    sheet = C.load_rgba(sheet_path) if sheet_path else None
    want = (man["character"]["rows"] * fh, man["character"]["columns"] * fw)
    if sheet is not None and sheet.shape[:2] != want:
        print(f"error: {sheet_path} is {sheet.shape[1]}x{sheet.shape[0]}, expected {want[1]}x{want[0]}", file=sys.stderr)
        return 2
    if sheet is not None:
        p = out / "contact_sheet.png"
        p.parent.mkdir(parents=True, exist_ok=True)
        contact_sheet(sheet, man, k).save(p); written.append(p)
        for name, spec in C.anim_rows(man):
            frames = []
            for fr in anim_frames(sheet, spec, fw, fh):
                cell = checker(fw, fh); cell.alpha_composite(fr)
                frames.append(up(cell, k))
            p = out / f"anim_{name}.gif"
            save_gif(frames, p, spec["fps"]); written.append(p)
    if sheet is not None:
        ch = Chamber(man, find)
        rows = man["character"]["animations"]
        def actor(name, col=0):
            return anim_frames(sheet, rows[name], fw, fh)[col % rows[name]["frames"]]
        for scene in man["scenes"]:
            still = ch.draw(scene, actor("idle_breathe"))
            if still is None:
                print(f"  skipped scene {scene['id']}: bg missing or not {man['canvas']}")
                continue
            p = out / f"composite_{scene['id']}.png"
            up(still, k).save(p); written.append(p)
            for name in a.anims:
                if name not in rows:
                    continue
                staged = work_anim(man, scene, name)
                p = out / f"composite_{scene['id']}_{name}.gif"
                save_gif([up(ch.draw(scene, fr, tick=i), k) for i, fr in enumerate(anim_frames(sheet, rows[staged], fw, fh))], p, rows[staged]["fps"])
                written.append(p)

        # Chambers butted together exactly as docked windows are: no gap, connectors open where they touch.
        scenes = man["scenes"]
        cw, ch_ = man["canvas"]
        def grid(cells, cols):
            n_rows = (len(cells) + cols - 1) // cols
            sheet_ = Image.new("RGBA", (cw * cols, ch_ * n_rows))
            for i, scene in enumerate(cells):
                col, row = i % cols, i // cols
                edges = {e for e, on in (("top", row > 0), ("bottom", i + cols < len(cells)), ("left", col > 0),
                                         ("right", col + 1 < cols and i + 1 < len(cells))) if on}
                im = ch.draw(scene, actor(work_anim(man, scene, "type"), i), edges, tick=i, avatar=i)
                if im is not None:
                    sheet_.alpha_composite(im, (col * cw, row * ch_))
            return up(sheet_, k)
        for name, cells, cols in (("stack_vertical", scenes[:3], 1), ("stack_horizontal", scenes[:2], 2), ("stack_mountain", scenes, 2)):
            p = out / f"{name}.png"
            grid(cells, cols).save(p); written.append(p)
        orb_sheet = orbs(ch, man, k)
        if orb_sheet is not None:
            p = out / "orbs.png"
            orb_sheet.save(p); written.append(p)
    print(f"wrote {len(written)} preview files to {out}/")
    return 0 if written else 1


if __name__ == "__main__":
    sys.exit(main())
