#!/usr/bin/env python3
"""Tile scene composites into one sheet, so eight chambers can be judged against each other.

  gallery.py out/preview -o docs/art-pass/after-scenes-4x.png [--cols 2]

Eight chambers that each look good alone can still read as one template redressed eight times.
That only shows up side by side, which is what this writes.
"""
from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image

BACKDROP = (28, 28, 36, 255)
GAP = 6


def tile(paths: list[Path], cols: int) -> Image.Image:
    shots = [Image.open(p).convert("RGBA") for p in paths]
    cw, ch = max(s.width for s in shots), max(s.height for s in shots)
    rows = (len(shots) + cols - 1) // cols
    out = Image.new("RGBA", (cols * cw + (cols + 1) * GAP, rows * ch + (rows + 1) * GAP), BACKDROP)
    for i, s in enumerate(shots):
        r, c = divmod(i, cols)
        out.paste(s, (GAP + c * (cw + GAP), GAP + r * (ch + GAP)), s)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("folder", help="a preview folder written by preview.py")
    ap.add_argument("-o", "--out", required=True)
    ap.add_argument("--cols", type=int, default=2)
    ap.add_argument("--glob", default="composite_*.png")
    a = ap.parse_args()
    paths = sorted(Path(a.folder).glob(a.glob))
    if not paths:
        raise SystemExit(f"no {a.glob} in {a.folder}")
    out = Path(a.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    tile(paths, a.cols).save(out)
    print(f"{len(paths)} tiles -> {out}")


if __name__ == "__main__":
    main()
