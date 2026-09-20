#!/usr/bin/env python3
"""Palette helper.

  palette.py list
  palette.py extract ref1.png ref2.png -o palettes/mine.hex --colours 32   # median cut
  palette.py swatch sweetie16 -o out/sweetie16.png
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common as C  # noqa: E402


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list")
    s = sub.add_parser("extract"); s.add_argument("images", nargs="+"); s.add_argument("-o", "--output", required=True)
    s.add_argument("--colours", type=int, default=C.MAX_COLOURS)
    s = sub.add_parser("swatch"); s.add_argument("palette"); s.add_argument("-o", "--output", required=True)
    a = ap.parse_args(argv)
    if a.cmd == "list":
        for n in C.available_palettes():
            print(f"{n:12} {len(C.load_palette(n)):3} colours")
    elif a.cmd == "extract":
        pal = C.load_palette("auto", a.images, a.colours)
        C.write_hex_file(a.output, pal, f"median cut, {len(pal)} colours, from: " + ", ".join(Path(i).name for i in a.images))
        print(f"wrote {len(pal)} colours to {a.output}")
    else:
        pal = C.load_palette(a.palette)
        img = np.repeat(np.repeat(pal[None, :, :], 32, axis=0), 32, axis=1)
        Path(a.output).parent.mkdir(parents=True, exist_ok=True)
        Image.fromarray(img, "RGB").save(a.output)
        print(f"wrote {a.output}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except ValueError as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(2)
