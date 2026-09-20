#!/usr/bin/env python3
"""Render previews of an asset set so a candidate can be judged at a glance.

  preview.py --assets set/ -o out/preview/

Writes (all nearest-neighbour, default 4x):
  contact_sheet.png            every animation row, labelled with frames / fps / loop
  anim_<name>.gif              one GIF per animation at the manifest fps
  composite_<room>.png         room bg + character + room fg at the manifest feet position
  composite_<room>_<anim>.gif  the same, animated (--anims, default idle_breathe and type)

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


def composite(bg: Image.Image, fg: Image.Image | None, frame: Image.Image, man: dict) -> Image.Image:
    """Same placement as RoomScene.swift: the frame's bottom centre sits at character.feet,
    measured from the canvas bottom-left."""
    cw, ch_ = man["canvas"]
    fw, fh = man["character"]["frame"]
    fx, fy = man["character"]["feet"]
    out = bg.copy()
    out.alpha_composite(frame, (int(fx - fw // 2), int(ch_ - fy - fh)))
    if fg is not None:
        out.alpha_composite(fg)
    return out


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
    for room in man["rooms"]:
        bgp, fgp = find(room["bg"]), find(room["fg"])
        if bgp is None or sheet is None:
            continue
        bg = Image.open(bgp).convert("RGBA")
        fg = Image.open(fgp).convert("RGBA") if fgp else None
        if bg.size != tuple(man["canvas"]) or (fg and fg.size != tuple(man["canvas"])):
            print(f"  skipped room {room['id']}: layer size is not {man['canvas']}")
            continue
        first = anim_frames(sheet, C.anim_rows(man)[0][1], fw, fh)[0]
        p = out / f"composite_{room['id']}.png"
        up(composite(bg, fg, first, man), k).save(p); written.append(p)
        for name in a.anims:
            spec = man["character"]["animations"].get(name)
            if not spec:
                continue
            p = out / f"composite_{room['id']}_{name}.gif"
            save_gif([up(composite(bg, fg, fr, man), k) for fr in anim_frames(sheet, spec, fw, fh)], p, spec["fps"])
            written.append(p)
    print(f"wrote {len(written)} preview files to {out}/")
    return 0 if written else 1


if __name__ == "__main__":
    sys.exit(main())
