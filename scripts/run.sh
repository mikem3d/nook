#!/bin/bash
# Bundles, then launches Nook.app. Arguments pass through: scripts/run.sh --demo ~/work/project
#
#   NOOK_CONFIG=debug scripts/run.sh ...     build the debug configuration instead of release
#
# Output from `open` goes to the system log, not this terminal. To watch NOOK_LOG=1 output run
# the binary inside the bundle directly: NOOK_LOG=1 dist/Nook.app/Contents/MacOS/Nook --demo
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/bundle.sh" "${NOOK_CONFIG:-release}"
# -n: a fresh instance, so the new build runs even if an old one is still open.
open -n "$ROOT/dist/Nook.app" --args "$@"
