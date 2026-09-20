#!/usr/bin/env python3
"""Copy a validated asset set into Sources/Nook/Assets, backing up what it replaces.

  install.py set/ --palette sweetie16            # dry run: shows the plan, changes nothing
  install.py set/ --palette sweetie16 --apply    # really copy
  install.py --restore tools/art/backups/20260101-120000 --apply

DRY RUN BY DEFAULT: the Assets folder belongs to another engineer. The set must pass
`sheet.py validate` (and `consistency.py` if it contains a sheet) or nothing is copied.
Only files named in the manifest are copied; manifest.json itself is never touched.
A set may be partial (one room, or just the sheet).
"""
from __future__ import annotations

import argparse
import filecmp
import json
import shutil
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common as C  # noqa: E402
import consistency  # noqa: E402
import sheet as S  # noqa: E402


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("candidate", nargs="?", help="folder laid out like Sources/Nook/Assets")
    ap.add_argument("--dest", default=str(C.ASSETS))
    ap.add_argument("--palette", help="palette every pixel must belong to (strongly recommended)")
    ap.add_argument("--apply", action="store_true", help="actually copy; without it this is a dry run")
    ap.add_argument("--allow-drift", action="store_true", help="install even if consistency.py flags rows")
    ap.add_argument("--backup-dir", default=str(C.TOOLS / "backups"))
    ap.add_argument("--restore", help="copy a backup folder back into --dest")
    ap.add_argument("--manifest")
    a = ap.parse_args(argv)
    dest = Path(a.dest)
    mode = "APPLY" if a.apply else "DRY RUN"

    if a.restore:
        src = Path(a.restore)
        files = [p for p in src.rglob("*.png")]
        if not files:
            print(f"error: no PNG files under {src}", file=sys.stderr)
            return 2
        for p in files:
            rel = p.relative_to(src)
            print(f"[{mode}] restore {rel}")
            if a.apply:
                (dest / rel).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(p, dest / rel)
        return 0
    if not a.candidate:
        ap.error("give a candidate folder, or --restore BACKUP")

    cand = Path(a.candidate)
    man = C.load_manifest(a.manifest or dest / "manifest.json")
    if (cand / "manifest.json").exists() and json.loads((cand / "manifest.json").read_text()) != man:
        print("  note: the candidate's manifest.json differs from the installed one and is ignored; "
              "manifest changes go through the engine owner")

    print(f"validating {cand} ...")
    rep = S.validate_set(cand, man, a.palette)
    rep.print()
    if not a.palette:
        print("  WARNING no --palette given: palette membership was not checked, only the colour count")
    if rep.errors:
        print(f"REFUSED: {len(rep.errors)} validation error(s); nothing copied")
        return 1
    sheet_rel = man["character"]["sheet"]
    if (cand / sheet_rel).exists():
        crep = consistency.analyse(C.load_rgba(cand / sheet_rel), man, consistency.THRESHOLDS)
        if not crep["ok"]:
            print(consistency.summary_text(crep))
            if not a.allow_drift:
                print("REFUSED: consistency check flagged rows (use --allow-drift to override); nothing copied")
                return 1

    files = [f for f in [sheet_rel] + [r[k] for r in man["rooms"] for k in ("bg", "fg")] if (cand / f).exists()]
    stamp = time.strftime("%Y%m%d-%H%M%S")
    backup = Path(a.backup_dir) / stamp
    changed = 0
    for rel in files:
        src, dst = cand / rel, dest / rel
        if dst.exists() and filecmp.cmp(src, dst, shallow=False):
            print(f"[{mode}] same     {rel}")
            continue
        changed += 1
        if dst.exists():
            print(f"[{mode}] replace  {rel}   (backup -> {backup / rel})")
            if a.apply:
                (backup / rel).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(dst, backup / rel)
        else:
            print(f"[{mode}] new      {rel}")
        if a.apply:
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
    if a.apply:
        print(f"installed {changed} file(s) into {dest}" + (f"; undo with: install.py --restore {backup} --apply" if changed and backup.exists() else ""))
    else:
        print(f"dry run: {changed} file(s) would change in {dest}. Re-run with --apply to copy.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
