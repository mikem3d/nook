#!/bin/bash
# Removes Nook.app, then asks — separately, and defaulting to keeping — about your data.
#
#   scripts/uninstall.sh
#
# Your agents, tasks, schedules and settings are NOT removed unless you say yes to each prompt,
# so uninstalling and reinstalling keeps your setup.
#
# Environment:
#   NOOK_APP_DIR    look here for Nook.app instead of the usual places
#   NOOK_SRC        the source checkout                  (default: ~/.nook/src)
#   NOOK_BUNDLE_ID  preferences domain                   (default: dev.nook.app)
#   NOOK_YES=1      take every default without asking (app removed, data kept)
set -euo pipefail

BUNDLE_ID="${NOOK_BUNDLE_ID:-dev.nook.app}"
SRC="${NOOK_SRC:-$HOME/.nook/src}"
DATA="$HOME/Library/Application Support/Nook"

bold=""; dim=""; reset=""
if [ -t 1 ]; then bold=$'\033[1m'; dim=$'\033[2m'; reset=$'\033[0m'; fi
step() { printf '%s==>%s %s\n' "$bold" "$reset" "$*"; }
info() { printf '    %s\n' "$*"; }
note() { printf '%s    %s%s\n' "$dim" "$*" "$reset"; }

ask() {  # ask "question" [y|n] -> 0 for yes
    local prompt="$1" default="${2:-n}" reply hint
    [ "$default" = y ] && hint="[Y/n]" || hint="[y/N]"
    if [ -n "${NOOK_YES:-}" ] || [ ! -r /dev/tty ]; then
        info "$prompt $hint $default"
        [ "$default" = y ]
        return
    fi
    printf '    %s %s ' "$prompt" "$hint" > /dev/tty
    read -r reply < /dev/tty || reply=""
    [ -z "$reply" ] && reply="$default"
    case "$reply" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

# --- the app ----------------------------------------------------------------------------------

if [ -n "${NOOK_APP_DIR:-}" ]; then
    CANDIDATES=("$NOOK_APP_DIR/Nook.app")
else
    CANDIDATES=("/Applications/Nook.app" "$HOME/Applications/Nook.app")
fi

found=0
for app in "${CANDIDATES[@]}"; do
    [ -d "$app" ] || continue
    # Never delete a bundle that is not Nook, whatever the path says.
    name="$(defaults read "$app/Contents/Info" CFBundleName 2>/dev/null || echo "")"
    if [ "$name" != Nook ]; then
        note "skipping $app: CFBundleName is ${name:-unset}, not Nook"
        continue
    fi
    found=1
    # Only this copy: a Nook running from a different path is not the one being removed.
    running="$app/Contents/MacOS/Nook"
    if pgrep -qf "$running"; then
        step "Quitting Nook"
        osascript -e 'quit app "Nook"' >/dev/null 2>&1 || true
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            pgrep -qf "$running" || break
            sleep 0.5
        done
        pgrep -qf "$running" && pkill -f "$running" || true
    fi
    step "Removing $app"
    rm -rf "$app"
done
[ "$found" = 1 ] || step "No Nook.app found in ${CANDIDATES[*]}"

# --- your data, one question at a time --------------------------------------------------------

if [ -d "$DATA" ]; then
    printf '\n'
    step "Agent list, tasks, schedules and caches"
    info "$DATA"
    if ask "Delete them? (keeping them means a reinstall picks up where you left off)" n; then
        rm -rf "$DATA"
        info "deleted."
    else
        info "kept."
    fi
fi

if defaults read "$BUNDLE_ID" >/dev/null 2>&1; then
    printf '\n'
    step "Settings (hotkeys, voice, quiet mode)"
    info "preferences domain $BUNDLE_ID"
    if ask "Delete them?" n; then
        defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
        rm -f "$HOME/Library/Preferences/$BUNDLE_ID.plist"
        info "deleted."
    else
        info "kept."
    fi
fi

if [ -d "$SRC/.git" ]; then
    printf '\n'
    step "Source checkout the installer made"
    info "$SRC"
    if ask "Delete it?" n; then
        rm -rf "$SRC"
        rmdir "$(dirname "$SRC")" 2>/dev/null || true
        info "deleted."
    else
        info "kept."
    fi
fi

printf '\n'
note "macOS keeps its record of the microphone, screen recording and notification permissions"
note "you granted; they are in System Settings › Privacy & Security if you want them gone."
