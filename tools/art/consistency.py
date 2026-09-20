#!/usr/bin/env python3
"""Quantify frame-to-frame drift in a character sheet and flag rows that look inconsistent.

  consistency.py set/character/sheet.png --json out/consistency.json
  consistency.py sheet.png --rows idle_sip think      # only these animations
  consistency.py sheet.png --set head_min=0.7         # override a threshold

Per frame, against the first frame of its row:
  iou         silhouette overlap (intersection over union of the alpha masks)
  area        silhouette area ratio: catches the character growing or shrinking
  palette     colour histogram distance, 0..1 (half the L1 distance of colour shares)
  com_dx/dy   centre-of-mass offset in px
  head        share of head-box pixels identical to the first frame's, best over +/-2 px shifts
And per row, its first frame against the sheet's reference frame (row 0, frame 0):
  ref_head, ref_palette, ref_area       catches rows generated separately that drifted apart

Exit code 1 if any row is flagged. Thresholds: see THRESHOLDS and docs/ART_PIPELINE.md.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common as C  # noqa: E402

# Calibrated on the hand-made placeholder sheet (legitimate motion must pass) and on
# synthetic drift (must fail). See docs/ART_PIPELINE.md "Thresholds" before changing.
THRESHOLDS = {
    "iou_min": 0.60,          # lowest silhouette IoU vs the row's first frame
    "area_min": 0.80,         # silhouette area ratio vs first frame
    "area_max": 1.25,
    "palette_max": 0.30,      # colour histogram distance vs first frame (props legitimately reach ~0.24)
    "com_dx_max": 2.5,        # px, horizontal centre-of-mass offset
    "com_dy_max": 3.0,        # px, vertical
    "head_min": 0.75,         # head-box match vs first frame
    "ref_head_min": 0.75,     # row's first frame vs the sheet reference frame
    "ref_palette_max": 0.30,
    "ref_area_min": 0.75,
    "ref_area_max": 1.40,
}
HEAD_SHIFT = 2


def head_box(frame: np.ndarray) -> tuple[int, int, int, int] | None:
    """(x0, y0, x1, y1) of the head. Uses the body column above the feet so marks floating
    beside the head (Zs, '!', sparkles) do not move the box."""
    fh, fw = frame.shape[:2]
    op = frame[..., 3] > 0
    feet = np.nonzero(op[-3:].any(0))[0]
    if len(feet) == 0:
        return None
    cx = int(round((feet.min() + feet.max() + 1) / 2))
    x0, x1 = max(0, cx - 7), min(fw, cx + 7)
    rows = np.nonzero(op[:, x0:x1].sum(1) >= 4)[0]
    if len(rows) == 0:
        return None
    top = int(rows.min())
    return x0, top, x1, top + max(4, int(round((fh - top) * 0.4)))


def head_match(ref: np.ndarray, frame: np.ndarray, box) -> tuple[float, tuple[int, int]]:
    x0, y0, x1, y1 = box
    target = ref[y0:y1, x0:x1]
    pad = np.pad(frame, ((HEAD_SHIFT,) * 2, (HEAD_SHIFT,) * 2, (0, 0)))
    best, shift = -1.0, (0, 0)
    for dy in range(-HEAD_SHIFT, HEAD_SHIFT + 1):
        for dx in range(-HEAD_SHIFT, HEAD_SHIFT + 1):
            cand = pad[y0 + dy + HEAD_SHIFT:y1 + dy + HEAD_SHIFT, x0 + dx + HEAD_SHIFT:x1 + dx + HEAD_SHIFT]
            m = float((cand == target).all(-1).mean())
            if m > best + 1e-9 or (abs(m - best) <= 1e-9 and abs(dx) + abs(dy) < abs(shift[0]) + abs(shift[1])):
                best, shift = m, (dx, dy)
    return best, shift


def _hist(frame: np.ndarray) -> dict:
    px = frame[frame[..., 3] > 0][:, :3]
    if len(px) == 0:
        return {}
    cols, n = np.unique(px, axis=0, return_counts=True)
    return {tuple(int(v) for v in c): k / len(px) for c, k in zip(cols, n)}


def hist_distance(a: dict, b: dict) -> float:
    return 0.5 * sum(abs(a.get(k, 0) - b.get(k, 0)) for k in set(a) | set(b))


def _com(op: np.ndarray):
    ys, xs = np.nonzero(op)
    return (float(xs.mean()), float(ys.mean())) if len(xs) else (0.0, 0.0)


def compare(ref: np.ndarray, frame: np.ndarray) -> dict:
    a, b = ref[..., 3] > 0, frame[..., 3] > 0
    union = (a | b).sum()
    (ax, ay), (bx, by) = _com(a), _com(b)
    box = head_box(ref)
    hm, hs = head_match(ref, frame, box) if box else (0.0, (0, 0))
    return {
        "iou": round(float((a & b).sum() / union) if union else 0.0, 3),
        "area": round(float(b.sum() / max(1, a.sum())), 3),
        "palette": round(hist_distance(_hist(ref), _hist(frame)), 3),
        "com_dx": round(bx - ax, 2), "com_dy": round(by - ay, 2),
        "head": round(hm, 3), "head_shift": list(hs),
    }


def analyse(sheet: np.ndarray, man: dict, thresholds: dict, only=None) -> dict:
    ch = man["character"]
    fw, fh = ch["frame"]
    t = thresholds
    rows = C.anim_rows(man)
    ref_name, ref_spec = rows[0]
    ref_frame = C.frame_of(sheet, ref_spec["row"], 0, fw, fh)
    out = {"reference": f"{ref_name}[0]", "thresholds": t, "rows": {}}
    for name, spec in rows:
        if only and name not in only:
            continue
        first = C.frame_of(sheet, spec["row"], 0, fw, fh)
        frames, flags = [], []
        for k in range(spec["frames"]):
            m = compare(first, C.frame_of(sheet, spec["row"], k, fw, fh))
            frames.append(m)
            tag = f"frame {k}"
            if m["iou"] < t["iou_min"]:
                flags.append(f"{tag}: silhouette IoU {m['iou']} < {t['iou_min']}")
            if not t["area_min"] <= m["area"] <= t["area_max"]:
                flags.append(f"{tag}: silhouette area x{m['area']} outside {t['area_min']}..{t['area_max']} (size drift)")
            if m["palette"] > t["palette_max"]:
                flags.append(f"{tag}: colour histogram distance {m['palette']} > {t['palette_max']} (colour drift)")
            if abs(m["com_dx"]) > t["com_dx_max"]:
                flags.append(f"{tag}: centre of mass moved {m['com_dx']} px sideways (limit {t['com_dx_max']})")
            if abs(m["com_dy"]) > t["com_dy_max"]:
                flags.append(f"{tag}: centre of mass moved {m['com_dy']} px vertically (limit {t['com_dy_max']})")
            if m["head"] < t["head_min"]:
                flags.append(f"{tag}: head matches the first frame by {m['head']} < {t['head_min']} (face or hair changed)")
        r = compare(ref_frame, first)
        ref = {"ref_head": r["head"], "ref_palette": r["palette"], "ref_area": r["area"]}
        if r["head"] < t["ref_head_min"]:
            flags.append(f"row vs {out['reference']}: head match {r['head']} < {t['ref_head_min']} (different-looking character)")
        if r["palette"] > t["ref_palette_max"]:
            flags.append(f"row vs {out['reference']}: colour histogram distance {r['palette']} > {t['ref_palette_max']}")
        if not t["ref_area_min"] <= r["area"] <= t["ref_area_max"]:
            flags.append(f"row vs {out['reference']}: silhouette area x{r['area']} outside {t['ref_area_min']}..{t['ref_area_max']} (different scale)")
        dxs = [f["com_dx"] for f in frames]; dys = [f["com_dy"] for f in frames]
        out["rows"][name] = {
            "row": spec["row"], "frames": frames, "vs_reference": ref,
            "summary": {"iou_min": min(f["iou"] for f in frames), "head_min": min(f["head"] for f in frames),
                        "palette_max": max(f["palette"] for f in frames),
                        "area_range": [min(f["area"] for f in frames), max(f["area"] for f in frames)],
                        "wobble_x": round(max(dxs) - min(dxs), 2), "wobble_y": round(max(dys) - min(dys), 2)},
            "flags": flags, "ok": not flags,
        }
    out["ok"] = all(r["ok"] for r in out["rows"].values())
    return out


def summary_text(rep: dict) -> str:
    lines = [f"{'animation':14} {'IoU>':>6} {'head>':>6} {'pal<':>6} {'area':>11} {'wobX':>5} {'wobY':>5} {'refHead':>8} {'refPal':>7}  result"]
    for name, r in rep["rows"].items():
        s, v = r["summary"], r["vs_reference"]
        lines.append(f"{name:14} {s['iou_min']:6.2f} {s['head_min']:6.2f} {s['palette_max']:6.2f} "
                     f"{s['area_range'][0]:5.2f}-{s['area_range'][1]:<5.2f} {s['wobble_x']:5.1f} {s['wobble_y']:5.1f} "
                     f"{v['ref_head']:8.2f} {v['ref_palette']:7.2f}  {'ok' if r['ok'] else 'FLAGGED'}")
        lines += [f"    - {f}" for f in r["flags"]]
    bad = [n for n, r in rep["rows"].items() if not r["ok"]]
    lines.append(f"{'CONSISTENT' if not bad else 'DRIFT'}: {len(bad)} of {len(rep['rows'])} rows flagged" + (f" ({', '.join(bad)})" if bad else ""))
    return "\n".join(lines)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("sheet")
    ap.add_argument("--manifest")
    ap.add_argument("--rows", nargs="*", help="only these animations")
    ap.add_argument("--set", nargs="*", default=[], metavar="KEY=VALUE", help="override thresholds")
    ap.add_argument("--json", help="write the full report here")
    a = ap.parse_args(argv)
    t = dict(THRESHOLDS)
    for kv in a.set:
        k, _, v = kv.partition("=")
        if k not in t:
            ap.error(f"unknown threshold '{k}'; known: {', '.join(t)}")
        t[k] = float(v)
    rep = analyse(C.load_rgba(a.sheet), C.load_manifest(a.manifest), t, a.rows)
    if a.json:
        Path(a.json).parent.mkdir(parents=True, exist_ok=True)
        Path(a.json).write_text(json.dumps(rep, indent=2))
    print(summary_text(rep))
    return 0 if rep["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
