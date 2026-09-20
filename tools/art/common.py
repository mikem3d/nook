"""Shared helpers for the Nook art tools: manifest, palettes, quantising, image IO.

Everything works on numpy arrays. An "index map" is a 2D int16 array of palette
indices where TRANSPARENT (-1) marks a fully transparent pixel. Working in
indices (not RGB) is what guarantees hard pixels, binary alpha and palette
compliance in the output.
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image

TOOLS = Path(__file__).resolve().parent
REPO = TOOLS.parents[1]
ASSETS = REPO / "Sources" / "Nook" / "Assets"
PALETTES = TOOLS / "palettes"
TRANSPARENT = -1
MAX_COLOURS = 32


# ---------- manifest ----------

def load_manifest(path=None) -> dict:
    """The current theme, in the shape the tools work with.

    `path` is Assets/manifest.json (the default; it names the theme) or a theme.json. Every file
    path in the result is relative to the Assets folder (themes/<id>/...), so a candidate set is
    still "a folder laid out like Sources/Nook/Assets". `rooms` is an alias of `scenes`, each with
    its own `feet`.
    """
    path = Path(path) if path else ASSETS / "manifest.json"
    with open(path) as f:
        data = json.load(f)
    prefix = ""
    if "theme" in data and "scenes" not in data:
        prefix = f"themes/{data['theme']}/"
        with open(path.parent / prefix / "theme.json") as f:
            data = json.load(f)
    elif path.parent.parent.name == "themes":
        prefix = f"themes/{path.parent.name}/"
    man = _prefixed(data, prefix)
    man["prefix"] = prefix
    for scene in man["scenes"]:
        scene.setdefault("feet", man["character"]["feet"])
    man["rooms"] = man["scenes"]
    return man


_PATH_KEYS = {"sheet", "sprite", "bg", "fg", "overlay", "back", "ring", "alert"}


def _prefixed(node, prefix):
    if isinstance(node, dict):
        return {k: prefix + v if k in _PATH_KEYS and isinstance(v, str) else _prefixed(v, prefix) for k, v in node.items()}
    if isinstance(node, list):
        return [_prefixed(v, prefix) for v in node]
    return node


def theme_palette(man: dict) -> np.ndarray | None:
    """The theme's own palette (theme.json "palette"), or None if it declares none."""
    cols = man.get("palette")
    return np.array([parse_hex(c) for c in cols], np.uint8) if cols else None


def asset_files(man: dict) -> list[str]:
    """Every image the theme declares, relative to the Assets folder, in a stable order."""
    out: list[str] = []

    def walk(node):
        if isinstance(node, dict):
            for k, v in node.items():
                if k in _PATH_KEYS and isinstance(v, str):
                    if v not in out:
                        out.append(v)
                else:
                    walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)
    walk({k: v for k, v in man.items() if k != "rooms"})
    return out


def anim_rows(manifest: dict) -> list[tuple[str, dict]]:
    """Animations sorted by sheet row: [(name, {row, frames, fps, looping}), ...]."""
    return sorted(manifest["character"]["animations"].items(), key=lambda kv: kv[1]["row"])


# ---------- image IO ----------

def load_rgba(path) -> np.ndarray:
    return np.array(Image.open(path).convert("RGBA"), dtype=np.uint8)


def save_rgba(arr: np.ndarray, path) -> None:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(arr.astype(np.uint8), "RGBA").save(path, optimize=True)


def index_to_rgba(idx: np.ndarray, pal: np.ndarray) -> np.ndarray:
    out = np.zeros(idx.shape + (4,), np.uint8)
    opaque = idx >= 0
    out[opaque, :3] = pal[idx[opaque]]
    out[opaque, 3] = 255
    return out


def rgba_to_index(rgba: np.ndarray, pal: np.ndarray, alpha_threshold=128) -> np.ndarray:
    h, w = rgba.shape[:2]
    idx = nearest_index(rgba[..., :3].reshape(-1, 3), pal).reshape(h, w).astype(np.int16)
    idx[rgba[..., 3] < alpha_threshold] = TRANSPARENT
    return idx


def frame_of(sheet: np.ndarray, row: int, col: int, fw: int, fh: int) -> np.ndarray:
    return sheet[row * fh:(row + 1) * fh, col * fw:(col + 1) * fw]


# ---------- palettes ----------

def parse_hex(s: str) -> tuple[int, int, int]:
    s = s.strip().lstrip("#")
    if len(s) != 6:
        raise ValueError(f"bad hex colour '{s}'")
    return int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16)


def read_hex_file(path) -> np.ndarray:
    """One RRGGBB per line. Lines starting with ';' are comments (Lospec/paint.net style)."""
    cols = []
    for line in Path(path).read_text().splitlines():
        line = line.strip()
        if not line or line.startswith(";"):
            continue
        cols.append(parse_hex(line.split()[0][-6:]))
    if not cols:
        raise ValueError(f"{path}: no colours found")
    return np.array(cols, np.uint8)


def write_hex_file(path, pal: np.ndarray, comment: str = "") -> None:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [f"; {c}" for c in comment.splitlines()] + ["%02x%02x%02x" % tuple(int(v) for v in c) for c in pal]
    path.write_text("\n".join(lines) + "\n")


def available_palettes() -> list[str]:
    return sorted(p.stem for p in PALETTES.glob("*.hex"))


def load_palette(spec: str, refs=None, colours: int = MAX_COLOURS) -> np.ndarray:
    """spec: a name in palettes/, a path to a .hex file, or 'auto' (median cut over refs)."""
    if spec == "auto":
        if not refs:
            raise ValueError("--palette auto needs at least one reference image")
        px = []
        for r in refs:
            a = load_rgba(r)
            px.append(a[a[..., 3] >= 128][:, :3])
        return median_cut(np.concatenate(px), colours)
    p = Path(spec)
    if not p.exists():
        p = PALETTES / f"{spec}.hex"
    if not p.exists():
        raise ValueError(f"palette '{spec}' not found; available: {', '.join(available_palettes())}, auto, or a .hex path")
    return read_hex_file(p)


def median_cut(pixels: np.ndarray, n: int) -> np.ndarray:
    """Median cut over an (M,3) uint8 array. Returns exact colours if there are <= n of them."""
    uniq, counts = np.unique(pixels.reshape(-1, 3), axis=0, return_counts=True)
    if len(uniq) <= n:
        return uniq.astype(np.uint8)
    boxes = [(uniq.astype(np.int32), counts)]
    while len(boxes) < n:
        # split the box with the largest (range * population) that still has > 1 colour
        best, best_score = -1, -1
        for i, (c, k) in enumerate(boxes):
            if len(c) < 2:
                continue
            score = int((c.max(0) - c.min(0)).max()) * float(np.sqrt(k.sum()))
            if score > best_score:
                best, best_score = i, score
        if best < 0:
            break
        c, k = boxes.pop(best)
        ch = int(np.argmax(c.max(0) - c.min(0)))
        order = np.argsort(c[:, ch], kind="stable")
        c, k = c[order], k[order]
        cut = int(np.searchsorted(np.cumsum(k), k.sum() / 2))
        cut = min(max(cut, 1), len(c) - 1)
        boxes += [(c[:cut], k[:cut]), (c[cut:], k[cut:])]
    pal = [np.round((c * k[:, None]).sum(0) / k.sum()) for c, k in boxes]
    return np.unique(np.array(pal, np.uint8), axis=0)


def merge_close(pal: np.ndarray, threshold: float = 14.0) -> np.ndarray:
    """Greedily merge palette entries closer than `threshold` (RGB distance). Noise in a source
    makes median cut spend several entries on one intended colour; this folds them back."""
    groups: list[list[np.ndarray]] = []
    for c in pal.astype(np.float32):
        for g in groups:
            if np.linalg.norm(np.mean(g, axis=0) - c) < threshold:
                g.append(c)
                break
        else:
            groups.append([c])
    return np.unique(np.array([np.round(np.mean(g, axis=0)) for g in groups], np.uint8), axis=0)


def nearest_index(rgb: np.ndarray, pal: np.ndarray, chunk: int = 1 << 16) -> np.ndarray:
    """Nearest palette index per pixel using the 'redmean' weighted RGB distance."""
    rgb = rgb.reshape(-1, 3).astype(np.float32)
    p = pal.astype(np.float32)
    out = np.empty(len(rgb), np.int16)
    for s in range(0, len(rgb), chunk):
        a = rgb[s:s + chunk, None, :]
        d = a - p[None]
        rm = (a[..., 0] + p[None, :, 0]) / 2
        dist = (2 + rm / 256) * d[..., 0] ** 2 + 4 * d[..., 1] ** 2 + (2 + (255 - rm) / 256) * d[..., 2] ** 2
        out[s:s + chunk] = np.argmin(dist, axis=1)
    return out


def darkest(pal: np.ndarray) -> int:
    luma = pal.astype(np.float32) @ np.array([0.299, 0.587, 0.114], np.float32)
    return int(np.argmin(luma))


def luma(rgb: np.ndarray) -> np.ndarray:
    return rgb[..., :3].astype(np.float32) @ np.array([0.299, 0.587, 0.114], np.float32)


# ---------- strips ----------

def split_columns(opaque: np.ndarray, n: int, use_gaps: bool = True) -> list[tuple[int, int]]:
    """Split a strip into n (x0, x1) column ranges.

    If use_gaps and the opaque mask has exactly n runs separated by empty columns,
    use those runs (robust to uneven spacing from a generator). Otherwise divide
    the width evenly.
    """
    w = opaque.shape[1]
    if use_gaps:
        cols = opaque.any(axis=0)
        runs, start = [], None
        for x, on in enumerate(cols):
            if on and start is None:
                start = x
            elif not on and start is not None:
                runs.append((start, x)); start = None
        if start is not None:
            runs.append((start, w))
        # merge runs separated by tiny gaps (detached sparkles, Zs) until n remain
        while len(runs) > n:
            gaps = [runs[i + 1][0] - runs[i][1] for i in range(len(runs) - 1)]
            i = int(np.argmin(gaps))
            runs[i:i + 2] = [(runs[i][0], runs[i + 1][1])]
        if len(runs) == n:
            return runs
    edges = [round(i * w / n) for i in range(n + 1)]
    return [(edges[i], edges[i + 1]) for i in range(n)]
