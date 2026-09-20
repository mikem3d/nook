#!/usr/bin/env python3
"""End-to-end tests for tools/art. No image generator is called: inputs are the repo's
placeholder art, damaged by tests/synth.py to look like raw AI output.

  python3 tools/art/tests/run_tests.py            # exit code 0 = all passed

Outputs land in tools/art/out/test/ (git-ignored) so the previews can be looked at.
The real Sources/Nook/Assets folder is only read; install.py is pointed at a copy.
"""
from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
TOOLS = HERE.parent
sys.path[:0] = [str(TOOLS), str(HERE)]
import common as C  # noqa: E402
import normalize as N  # noqa: E402
import synth  # noqa: E402

OUT = TOOLS / "out" / "test"
PAL = OUT / "shared.hex"
results: list[tuple[str, bool, str]] = []


def run(tool: str, *args) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(TOOLS / tool), *map(str, args)], capture_output=True, text=True)


def check(name: str, ok: bool, detail: str = ""):
    results.append((name, bool(ok), detail))
    print(f"{'PASS' if ok else 'FAIL'}  {name}" + (f"   {detail}" if detail else ""))


def tree_hash(root: Path) -> str:
    h = hashlib.sha256()
    for p in sorted(root.rglob("*")):
        if p.is_file():
            h.update(str(p.relative_to(root)).encode()); h.update(p.read_bytes())
    return h.hexdigest()


def same(a: np.ndarray, b: np.ndarray) -> float:
    return float((a == b).all(-1).mean()) if a.shape == b.shape else 0.0


def main() -> int:
    shutil.rmtree(OUT, ignore_errors=True)
    OUT.mkdir(parents=True)
    man = C.load_manifest()
    fw, fh = man["character"]["frame"]
    assets_before = tree_hash(C.ASSETS)
    files = [man["character"]["sheet"]] + [r[k] for r in man["rooms"] for k in ("bg", "fg")]

    # ---- 1. palettes
    sizes = {n: len(C.load_palette(n)) for n in C.available_palettes()}
    check("bundled palettes load and hold 16..32 colours", sizes and all(16 <= v <= 32 for v in sizes.values()), str(sizes))
    r = run("palette.py", "extract", *[C.ASSETS / f for f in files], "-o", PAL, "--colours", 32)
    pal = C.load_palette(str(PAL))
    check("palette auto (median cut) over all placeholders -> <= 32 colours", r.returncode == 0 and len(pal) <= 32, f"{len(pal)} colours")

    # reference = placeholders snapped to the extracted palette (a no-op while they stay within 32 colours)
    ref = {f: C.index_to_rgba(C.rgba_to_index(C.load_rgba(C.ASSETS / f), pal), pal) for f in files}

    # ---- 2. grid detection
    bg = C.load_rgba(C.ASSETS / man["rooms"][0]["bg"])
    strip = C.load_rgba(C.ASSETS / files[0])[fh:2 * fh, :6 * fw]
    errs = []
    for f in (3, 4, 5.5, 7.3, 8, 10.67, 13.5, 16, 20):
        for img in (synth.degrade(bg, f), synth.degrade(strip, f, margin=6)):
            errs.append(abs(N.detect_grid(img[..., :3])["scale"] - f) / f)
        sharp = np.array(Image.fromarray(strip).resize((round(strip.shape[1] * f), round(fh * f)), Image.NEAREST))
        errs.append(abs(N.detect_grid(sharp[..., :3])["scale"] - f) / f)
    check("grid detection within 1% at 9 scales x (room, strip, unblurred strip)", max(errs) < 0.01, f"worst error {max(errs):.2%}")

    # ---- 3. round trip: placeholder -> degrade -> normalize -> assemble -> validate
    raw, cand = OUT / "raw", OUT / "set"
    factors = [7.3, 8, 10.67]
    worst = {}
    for i, room in enumerate(man["rooms"]):
        for layer, mode in (("bg", "room-bg"), ("fg", "room-fg")):
            rel = room[layer]
            src = raw / f"{room['id']}_{layer}.png"
            C.save_rgba(synth.degrade(ref[rel], factors[i % 3], seed=i), src)
            r = run("normalize.py", mode, src, "-o", cand / rel, "--palette", PAL)
            if r.returncode:
                print(r.stdout, r.stderr)
            worst[rel] = same(C.load_rgba(cand / rel), ref[rel])
    sheet_src = ref[files[0]]
    for i, (name, spec) in enumerate(C.anim_rows(man)):
        row = sheet_src[spec["row"] * fh:(spec["row"] + 1) * fh, :spec["frames"] * fw]
        src = raw / f"strip_{name}.png"
        C.save_rgba(synth.degrade(row, factors[i % 3], margin=5, seed=10 + i), src)
        r = run("normalize.py", "character-strip", src, "-o", OUT / "strips" / f"{name}.png", "--anim", name, "--palette", PAL)
        if r.returncode:
            print(r.stdout, r.stderr)
    r = run("sheet.py", "assemble", OUT / "strips", "-o", cand / files[0])
    check(f"sheet.py assemble builds the sheet from {len(man['character']['animations'])} normalised strips", r.returncode == 0, r.stdout.strip().splitlines()[-1] if r.stdout else r.stderr)
    worst[files[0]] = same(C.load_rgba(cand / files[0]), ref[files[0]])
    detail = ", ".join(f"{'/'.join(Path(k).parts[-2:])} {v:.2%}" for k, v in worst.items())
    check("round trip reproduces the source art (>= 99.5% of pixels per file, sheet >= 99.9%)",
          min(worst.values()) >= 0.995 and worst[files[0]] >= 0.999, detail)
    for f in C.asset_files(man):            # the rest of the theme rides along untouched
        if not (cand / f).exists():
            (cand / f).parent.mkdir(parents=True, exist_ok=True); shutil.copy(C.ASSETS / f, cand / f)
    r = run("sheet.py", "validate", "--assets", cand, "--complete", "--json", OUT / "validate.json")
    check("sheet.py validate passes the round-tripped set", r.returncode == 0, r.stdout.strip().splitlines()[-1])
    r = run("sheet.py", "validate", "--complete")
    check("sheet.py validate passes the installed theme against its own palette (<= 32 colours, seams line up)",
          r.returncode == 0 and "0 errors" in r.stdout, r.stdout.strip().splitlines()[-1])
    theme_files = C.asset_files(man)
    seam = OUT / "bad_seam"
    for f in theme_files:
        (seam / f).parent.mkdir(parents=True, exist_ok=True); shutil.copy(C.ASSETS / f, seam / f)
    piece = man["frame"]["connectors"]["bottom"]["open"]["sprite"]
    a = C.load_rgba(seam / piece); a[-1, 2:4] = a[-1, 5]; C.save_rgba(a, seam / piece)
    r = run("sheet.py", "validate", "--assets", seam)
    check("validate rejects: a ladder that does not line up across the seam", r.returncode == 1 and "[seam]" in r.stdout,
          next((l.strip() for l in r.stdout.splitlines() if "[seam]" in l), "")[:150])
    ring = man["orb"]["ring"]
    a = C.load_rgba(seam / ring); a[0, 0] = a[14, 1]; C.save_rgba(a, seam / ring)
    r = run("sheet.py", "validate", "--assets", seam)
    check("validate rejects: orb art outside the circle", r.returncode == 1 and "[circle]" in r.stdout)

    # ---- 4. validation catches broken sheets
    good = C.load_rgba(cand / files[0])
    def broken(code, mutate):
        a = good.copy(); a = mutate(a)
        p = OUT / "broken" / f"{code}.png"; C.save_rgba(a, p)
        r = run("sheet.py", "validate", "--sheet", p, "--palette", PAL)
        line = next((l.strip() for l in r.stdout.splitlines() if f"[{code}]" in l), "")
        check(f"validate rejects: {code}", r.returncode == 1 and bool(line), line[:150])
    def shift(a, row, col, dx, dy):
        fr = a[row * fh:(row + 1) * fh, col * fw:(col + 1) * fw].copy()
        fr = np.roll(fr, (dy, dx), (0, 1))
        a[row * fh:(row + 1) * fh, col * fw:(col + 1) * fw] = fr
        return a
    def blank(a): a[2 * fh:3 * fh, 3 * fw:4 * fw] = 0; return a
    def extra(a): a[8 * fh:9 * fh, 5 * fw:6 * fw] = a[:fh, :fw]; return a
    def offpal(a): a[10, 12, :3] = (1, 254, 3); return a
    def soft(a): a[10, 12, 3] = 128; return a
    broken("size", lambda a: a[:, :-fw])
    broken("empty-frame", blank)
    broken("extra-frame", extra)
    broken("feet", lambda a: shift(a, 1, 2, 0, -2))
    broken("centre", lambda a: shift(a, 6, 1, 3, 0))
    broken("drift", lambda a: shift(shift(a, 4, 1, 1, 0), 4, 2, -1, 0))
    broken("palette", offpal)
    broken("alpha", soft)

    # ---- 5. consistency
    r = run("consistency.py", cand / files[0], "--json", OUT / "consistency_clean.json")
    check("consistency.py passes the round-tripped sheet", r.returncode == 0, r.stdout.strip().splitlines()[-1])
    drift = OUT / "drift_sheet.png"
    C.save_rgba(synth.drift_row(good, man["character"]["animations"]["idle_sip"]["row"], 6), drift)
    r = run("consistency.py", drift, "--json", OUT / "consistency_drift.json")
    rep = json.loads((OUT / "consistency_drift.json").read_text())
    flagged = [n for n, v in rep["rows"].items() if not v["ok"]]
    check("consistency.py flags exactly the drifting row, exit code 1", r.returncode == 1 and flagged == ["idle_sip"],
          f"flagged {flagged}, {len(rep['rows']['idle_sip']['flags'])} reasons, e.g. {rep['rows']['idle_sip']['flags'][0]}")
    for kind, kw in (("size only", dict(grow=0.04, shift=0, recolour=None)), ("position only", dict(grow=0, shift=1, recolour=None)),
                     ("colour only", dict(grow=0, shift=0))):
        p = OUT / f"drift_{kind.split()[0]}.png"
        C.save_rgba(synth.drift_row(good, 1, 6, **kw), p)
        r = run("consistency.py", p, "--rows", "idle_sip")
        check(f"consistency.py flags {kind} drift", r.returncode == 1, r.stdout.strip().splitlines()[1].strip()[2:110])

    # ---- 6. outline, orphans, single frame, prop, split
    idle = sheet_src[:fh, :fw]
    C.save_rgba(synth.degrade(idle, 12, margin=6), raw / "ref_frame.png")
    r = run("normalize.py", "character-frame", raw / "ref_frame.png", "-o", OUT / "ref_frame.png", "--palette", PAL, "--outline", "outer")
    fr = C.load_rgba(OUT / "ref_frame.png")
    op = fr[..., 3] > 0
    pad = np.pad(op, 1)
    rim = op & ~(pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:]); rim[-1] = False
    check("character-frame + --outline outer: 32x32, every rim pixel dark", fr.shape[:2] == (fh, fw) and (C.luma(fr)[rim] < 70).all(),
          f"{int(rim.sum())} rim px, size {fr.shape[1]}x{fr.shape[0]}")
    speck = C.rgba_to_index(ref[files[0]][:fh, :fw], pal)
    speck[1, 1] = 3; speck[2, 29] = 5; speck[20, 15] = C.TRANSPARENT  # two specks, one pinhole
    cleaned, n = N.remove_orphans(speck, "safe")
    check("orphan pass removes stray specks and pinholes, keeps the art", n == 3 and (cleaned == C.rgba_to_index(ref[files[0]][:fh, :fw], pal)).all(), f"{n} removed")
    mug = np.zeros((12, 12, 4), np.uint8); mug[3:10, 2:8] = (245, 245, 235, 255); mug[5:8, 8:10] = (245, 245, 235, 255)
    C.save_rgba(synth.degrade(mug, 9, margin=3), raw / "prop.png")
    r = run("normalize.py", "prop", raw / "prop.png", "-o", OUT / "prop.png", "--palette", PAL)
    pr = C.load_rgba(OUT / "prop.png")
    check("prop mode crops to the object with binary alpha", pr.shape[:2] == (7, 8) and set(np.unique(pr[..., 3])) <= {0, 255}, f"{pr.shape[1]}x{pr.shape[0]}")
    r = run("sheet.py", "split", OUT / "strips" / "idle_sip.png", "--anim", "idle_sip", "-o", OUT / "frames" / "idle_sip")
    fr_files = sorted((OUT / "frames" / "idle_sip").glob("*.png"))
    check("sheet.py split cuts a strip into manifest frame count", len(fr_files) == 6 and all(Image.open(f).size == (fw, fh) for f in fr_files), f"{len(fr_files)} frames")
    first_bg = raw / f"{man['rooms'][0]['id']}_bg.png"
    r = run("normalize.py", "room-bg", first_bg, "-o", OUT / "auto_bg.png", "--palette", "auto", "--colours", "16")
    ncol = len(np.unique(C.load_rgba(OUT / "auto_bg.png")[..., :3].reshape(-1, 3), axis=0))
    check("--palette auto without a reference derives <= N colours from the input", r.returncode == 0 and ncol <= 16, f"{ncol} colours")
    r = run("normalize.py", "room-bg", first_bg, "-o", OUT / "pico_bg.png", "--palette", "pico8")
    check("named palette (pico8) output is palette compliant", set(map(tuple, np.unique(C.load_rgba(OUT / "pico_bg.png")[..., :3].reshape(-1, 3), axis=0)))
          <= set(map(tuple, C.load_palette("pico8"))))

    # ---- 7. preview
    r = run("preview.py", "--assets", cand, "-o", OUT / "preview", "--no-fallback")
    gifs = sorted((OUT / "preview").glob("anim_*.gif"))
    def total_ms(path):  # Pillow merges identical neighbouring frames and sums their durations
        im = Image.open(path); t = 0
        for i in range(im.n_frames):
            im.seek(i); t += im.info["duration"]
        return t
    durs = {g.stem[5:]: total_ms(g) for g in gifs}
    fps_ok = all(abs(durs[n] - 1000 * s["frames"] / s["fps"]) <= 10 * s["frames"] for n, s in man["character"]["animations"].items())
    comps = list((OUT / "preview").glob("composite_*"))
    cs = Image.open(OUT / "preview" / "contact_sheet.png")
    n_anims, n_rooms = len(man["character"]["animations"]), len(man["rooms"])
    check("preview.py writes contact sheet, one GIF per animation at manifest fps, scene composites",
          r.returncode == 0 and len(gifs) == n_anims and fps_ok and len(comps) == 3 * n_rooms and cs.width >= 8 * fw * 4,
          f"{len(gifs)} gifs, {len(comps)} composites, contact sheet {cs.width}x{cs.height}")
    r = run("preview.py", "-o", OUT / "preview_theme")
    stack = OUT / "preview_theme" / "stack_vertical.png"
    cw, ch_ = man["canvas"]
    check("preview.py composites stacked chambers with open connectors, and the orbs",
          r.returncode == 0 and stack.exists() and Image.open(stack).size == (cw * 4, ch_ * 3 * 4)
          and all((OUT / "preview_theme" / n).exists() for n in ("stack_horizontal.png", "stack_mountain.png", "orbs.png")))

    # ---- 8. install (against a COPY of the assets folder)
    dest = OUT / "fake_assets"
    shutil.copytree(C.ASSETS, dest)
    before = tree_hash(dest)
    r = run("install.py", cand, "--dest", dest, "--backup-dir", OUT / "backups")
    check("install.py is a dry run by default and changes nothing", r.returncode == 0 and tree_hash(dest) == before and "dry run" in r.stdout, r.stdout.strip().splitlines()[-1])
    r = run("install.py", cand, "--dest", dest, "--backup-dir", OUT / "backups", "--apply")
    installed = all((dest / f).read_bytes() == (cand / f).read_bytes() for f in files)
    backups = list((OUT / "backups").glob("*/"))
    backed = bool(backups) and all((backups[0] / f).read_bytes() == (C.ASSETS / f).read_bytes() for f in files)
    check(f"install.py --apply copies {len(files)} files and backs up the originals", r.returncode == 0 and installed and backed, r.stdout.strip().splitlines()[-1][:120])
    r = run("install.py", "--restore", backups[0], "--dest", dest, "--apply")
    check("install.py --restore puts the originals back", tree_hash(dest) == before)
    bad = OUT / "bad_set"
    shutil.copytree(cand, bad); C.save_rgba(shift(good.copy(), 1, 2, 0, -2), bad / files[0])
    r = run("install.py", bad, "--dest", dest, "--apply")
    check("install.py refuses a set that fails validation", r.returncode == 1 and tree_hash(dest) == before and "REFUSED" in r.stdout)
    shutil.rmtree(bad); shutil.copytree(cand, bad); shutil.copy(drift, bad / files[0])
    r = run("install.py", bad, "--dest", dest, "--apply")
    check("install.py refuses a set whose sheet drifts", r.returncode == 1 and tree_hash(dest) == before and "REFUSED" in r.stdout)

    check("the real Sources/Nook/Assets folder was not modified", tree_hash(C.ASSETS) == assets_before)

    failed = [n for n, ok, _ in results if not ok]
    print(f"\n{len(results) - len(failed)}/{len(results)} passed" + (f"; FAILED: {failed}" if failed else ""))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
