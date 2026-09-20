#!/usr/bin/env python3
"""Synthetic stand-ins for AI output. No generator is called: we damage known-good art instead.

degrade(): upscale by a (possibly non-integer) factor, blur, add noise, JPEG round trip. This is
what "pixel-art-looking but off-grid" output looks like to the tools.
drift_row(): make later frames of one sheet row drift (resize, shift, recolour), like separately
generated animation frames do.
"""
from __future__ import annotations

import io
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import common as C  # noqa: E402

MAGENTA = (255, 0, 255)


def degrade(rgba: np.ndarray, factor: float = 7.3, blur: float = 0.18, noise: float = 6.0, jpeg: int = 88,
            background=MAGENTA, margin: int = 0, seed: int = 1) -> np.ndarray:
    """Returns an opaque RGBA image. Transparent areas become `background` (pass None to keep alpha)."""
    rng = np.random.default_rng(seed)
    img = Image.fromarray(rgba, "RGBA")
    if margin:
        big = Image.new("RGBA", (img.width + 2 * margin, img.height + 2 * margin), (0, 0, 0, 0))
        big.paste(img, (margin, margin))
        img = big
    if background is not None:
        bg = Image.new("RGBA", img.size, background + (255,))
        img = Image.alpha_composite(bg, img)
    size = (round(img.width * factor), round(img.height * factor))
    img = img.resize(size, Image.NEAREST).filter(ImageFilter.GaussianBlur(blur * factor))
    a = np.array(img).astype(np.float32)
    a[..., :3] += rng.normal(0, noise, a[..., :3].shape)
    a[..., :3] *= rng.uniform(0.97, 1.03, 3)  # slight colour cast
    img = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")
    if jpeg and background is not None:
        buf = io.BytesIO()
        img.convert("RGB").save(buf, "JPEG", quality=jpeg)
        img = Image.open(io.BytesIO(buf.getvalue())).convert("RGBA")
    return np.array(img)


def drift_row(sheet: np.ndarray, row: int, frames: int, fw: int = 32, fh: int = 32,
              grow: float = 0.06, shift: int = 1, recolour=(90, 140, 200)) -> np.ndarray:
    """Frame k of the row gets k*grow bigger and k*shift px to the right; in the second half of
    the row the most common colour (the shirt) turns into `recolour`. All colours stay inside
    the sheet's palette, like drift that survived normalisation would."""
    out = sheet.copy()
    for k in range(1, frames):
        fr = Image.fromarray(C.frame_of(sheet, row, k, fw, fh).copy(), "RGBA")
        s = 1 + grow * k
        big = fr.resize((round(fw * s), round(fh * s)), Image.NEAREST)
        canvas = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
        canvas.paste(big, ((fw - big.width) // 2 + shift * k, fh - big.height))
        a = np.array(canvas)
        if recolour and k >= frames // 2:
            cols, n = np.unique(a[a[..., 3] > 0][:, :3], axis=0, return_counts=True)
            a[(a[..., :3] == cols[int(np.argmax(n))]).all(-1) & (a[..., 3] > 0), :3] = recolour
        out[row * fh:(row + 1) * fh, k * fw:(k + 1) * fw] = a
    return out


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser(description="Degrade a clean pixel image so it looks like raw AI output.")
    ap.add_argument("input"); ap.add_argument("output")
    ap.add_argument("--factor", type=float, default=7.3)
    ap.add_argument("--margin", type=int, default=0)
    a = ap.parse_args()
    C.save_rgba(degrade(C.load_rgba(a.input), a.factor, margin=a.margin), a.output)
