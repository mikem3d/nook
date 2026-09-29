#!/bin/bash
# Installs or updates Nook from source. Safe to re-run: re-running is how you update.
#
#   curl -fsSL https://raw.githubusercontent.com/mikem3d/nook/main/scripts/install.sh | bash
#   git clone https://github.com/mikem3d/nook.git && nook/scripts/install.sh
#
# It clones (or pulls) the repo, builds the release configuration, assembles Nook.app with
# scripts/bundle.sh and moves it into /Applications. It never touches anything outside its own
# source directory and the Nook.app it installed.
#
# Environment:
#   NOOK_SRC        source checkout            (default: ~/.nook/src)
#   NOOK_REPO       git URL to clone           (default: the public repo)
#   NOOK_REF        branch or tag to check out (default: main)
#   NOOK_APP_DIR    where Nook.app goes        (default: /Applications, else ~/Applications)
#   NOOK_YES=1      answer every prompt with its default and never wait for input
#   NOOK_LAUNCH=0   do not offer to launch at the end
set -euo pipefail

REPO_URL="${NOOK_REPO:-https://github.com/mikem3d/nook.git}"
REF="${NOOK_REF:-main}"
SRC="${NOOK_SRC:-$HOME/.nook/src}"
MIN_MACOS=14

bold=""; dim=""; red=""; reset=""
if [ -t 1 ]; then bold=$'\033[1m'; dim=$'\033[2m'; red=$'\033[31m'; reset=$'\033[0m'; fi

step() { printf '%s==>%s %s\n' "$bold" "$reset" "$*"; }
info() { printf '    %s\n' "$*"; }
note() { printf '%s    %s%s\n' "$dim" "$*" "$reset"; }
fail() { printf '%snook: %s%s\n' "$red" "$*" "$reset" >&2; exit 1; }

# Prompts go to the terminal, not stdout: under `curl … | bash` stdin is the script itself.
# With no usable terminal (a CI runner, a pipeline) every question takes its default silently.
TTY_OK=0
if { true >/dev/tty; } 2>/dev/null; then TTY_OK=1; fi

ask() {  # ask "question" [y|n] -> 0 for yes
    local prompt="$1" default="${2:-y}" reply hint
    [ "$default" = y ] && hint="[Y/n]" || hint="[y/N]"
    if [ -n "${NOOK_YES:-}" ] || [ "$TTY_OK" != 1 ]; then
        info "$prompt $hint $default"
        [ "$default" = y ]
        return
    fi
    printf '    %s %s ' "$prompt" "$hint" > /dev/tty
    read -r reply < /dev/tty || reply=""
    [ -z "$reply" ] && reply="$default"
    case "$reply" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

# Processes whose executable IS this binary. `pgrep -f` would also match any shell or editor
# with the path in its command line — including this script — so match the process name exactly
# and then compare the executable `ps` reports.
nook_pids() {
    local binary="$1" pid
    for pid in $(pgrep -x Nook 2>/dev/null || true); do
        [ "$(ps -o comm= -p "$pid" 2>/dev/null)" = "$binary" ] && printf '%s\n' "$pid"
    done
    return 0
}

# Quit the Nook running from one exact binary path. A quit Apple event is the polite way — it
# lets Nook save its agent list — but `quit app "Nook"` names an app, not a path, so it is only
# safe when the copy we care about is the only Nook running. Otherwise, and as the fallback,
# signal exactly the processes we found.
quit_nook() {
    local binary="$1" pids all
    pids="$(nook_pids "$binary")"
    [ -n "$pids" ] || return 0
    all="$(pgrep -x Nook 2>/dev/null || true)"
    if [ "$pids" = "$all" ]; then osascript -e 'quit app "Nook"' >/dev/null 2>&1 || true; fi
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        [ -n "$(nook_pids "$binary")" ] || return 0
        sleep 0.5
    done
    # shellcheck disable=SC2086  # deliberate word splitting: several pids
    kill -TERM $pids 2>/dev/null || true
    sleep 1
    # shellcheck disable=SC2086
    kill -KILL $pids 2>/dev/null || true
}

# --- 1. this Mac ------------------------------------------------------------------------------

step "Checking this Mac"

[ "$(uname -s)" = Darwin ] || fail "Nook is a macOS app; this is $(uname -s)."

OS_VERSION="$(sw_vers -productVersion)"
[ "${OS_VERSION%%.*}" -ge "$MIN_MACOS" ] \
    || fail "Nook needs macOS $MIN_MACOS or later; this Mac runs $OS_VERSION."

ARCH="$(uname -m)"
case "$ARCH" in
    arm64|x86_64) ;;
    *) fail "unsupported architecture $ARCH." ;;
esac
info "macOS $OS_VERSION on $ARCH"

# A Swift toolchain: either full Xcode or the Command Line Tools. `swift --version` is the real
# test, because xcode-select can point at a path whose tools were removed.
if ! xcode-select -p >/dev/null 2>&1 || ! swift --version >/dev/null 2>&1; then
    fail "no Swift toolchain found. Install Apple's Command Line Tools and run this again:

      xcode-select --install

    (If you already have Xcode, run: sudo xcode-select -s /Applications/Xcode.app)"
fi
info "Swift $(swift --version 2>&1 | sed -n 's/.*Apple Swift version \([0-9.]*\).*/\1/p' | head -1)"

command -v git >/dev/null 2>&1 || fail "git not found. It ships with the Command Line Tools: xcode-select --install"

# --- 2. Claude Code ---------------------------------------------------------------------------

# Nook has no API key and talks to no service. Every window drives the user's own `claude`
# binary, so without Claude Code installed and logged in the windows open but nothing answers.
# Mirrors ClaudeLocator in Sources/Nook/AgentSession.swift.
find_claude() {
    local dir
    command -v claude 2>/dev/null && return 0
    for dir in "$HOME/.local/bin" "$HOME/.claude/local" /opt/homebrew/bin /usr/local/bin; do
        [ -x "$dir/claude" ] && { printf '%s\n' "$dir/claude"; return 0; }
    done
    return 1
}

step "Checking for Claude Code"
if CLAUDE_BIN="$(find_claude)"; then
    info "found $CLAUDE_BIN"
    note "Nook runs this binary; make sure you have logged in with it at least once."
else
    printf '%s' "$red" >&2
    cat >&2 <<'EOF'
    No `claude` command found.

    Nook does not talk to any API itself: every agent window runs YOUR copy of Claude Code.
    Without it, windows will open and no agent will ever answer. Install it first:

      curl -fsSL https://claude.ai/install.sh | bash

    then run `claude` once to log in, and run this installer again.
    Instructions: https://docs.claude.com/en/docs/claude-code/setup
EOF
    printf '%s' "$reset" >&2
    ask "Install Nook anyway?" n || exit 1
fi

# --- 3. source --------------------------------------------------------------------------------

# When the script is run from inside a checkout, build that checkout instead of cloning a second
# copy. Piped through bash there is no script file, so BASH_SOURCE is empty and we clone.
SELF="${BASH_SOURCE[0]:-}"
if [ -n "$SELF" ] && [ -f "$SELF" ]; then
    MAYBE="$(cd "$(dirname "$SELF")/.." && pwd)"
    if [ -f "$MAYBE/Package.swift" ] && grep -q 'name: "Nook"' "$MAYBE/Package.swift"; then
        SRC="$MAYBE"
        IN_PLACE=1
    fi
fi

if [ -n "${IN_PLACE:-}" ]; then
    step "Building from this checkout"
    info "$SRC"
elif [ -d "$SRC/.git" ]; then
    step "Updating $SRC"
    # Only repoint the remote when asked; otherwise a checkout installed from a fork keeps it.
    [ -z "${NOOK_REPO:-}" ] || git -C "$SRC" remote set-url origin "$REPO_URL"
    git -C "$SRC" fetch --quiet origin "$REF"
    # A hard reset is safe here: $SRC is the installer's own directory, not a working copy the
    # user edits. Anyone hacking on Nook runs the script from their own clone instead.
    git -C "$SRC" checkout --quiet --force --detach FETCH_HEAD
    info "at $(git -C "$SRC" rev-parse --short HEAD)"
else
    [ ! -e "$SRC" ] || [ -d "$SRC" ] || fail "$SRC exists and is not a directory."
    if [ -d "$SRC" ] && [ -n "$(ls -A "$SRC" 2>/dev/null)" ]; then
        fail "$SRC is not empty and is not a git checkout. Move it aside, or set NOOK_SRC."
    fi
    step "Cloning $REPO_URL"
    mkdir -p "$(dirname "$SRC")"
    git clone --quiet --branch "$REF" "$REPO_URL" "$SRC"
    info "into $SRC"
fi

# --- 4. build ---------------------------------------------------------------------------------

# bundle.sh deletes and re-signs $SRC/dist/Nook.app. macOS kills a running process whose signed
# binary is replaced underneath it, so a Nook launched from this checkout (scripts/run.sh does
# that) must go first, or it dies without saving.
if [ -n "$(nook_pids "$SRC/dist/Nook.app/Contents/MacOS/Nook")" ]; then
    step "A Nook launched from this checkout is running"
    info "rebuilding replaces $SRC/dist/Nook.app underneath it, which macOS treats as a kill."
    if ask "Quit it first?" y; then
        quit_nook "$SRC/dist/Nook.app/Contents/MacOS/Nook"
    else
        fail "quit that Nook and run this again."
    fi
fi

step "Building Nook (this takes a few minutes the first time)"
( cd "$SRC" && swift build -c release )

step "Assembling Nook.app"
( cd "$SRC" && ./scripts/bundle.sh release )
BUILT="$SRC/dist/Nook.app"
[ -d "$BUILT" ] || fail "the bundle step did not produce $BUILT."

# --- 5. install -------------------------------------------------------------------------------

if [ -n "${NOOK_APP_DIR:-}" ]; then
    APP_DIR="$NOOK_APP_DIR"
    mkdir -p "$APP_DIR"
elif [ -w /Applications ]; then
    APP_DIR=/Applications
else
    APP_DIR="$HOME/Applications"
    mkdir -p "$APP_DIR"
    note "/Applications is not writable; installing to $APP_DIR"
fi
TARGET="$APP_DIR/Nook.app"

# Only ever replace a bundle that is actually Nook, so a mistyped NOOK_APP_DIR cannot delete
# somebody else's app.
if [ -e "$TARGET" ]; then
    ident="$(defaults read "$TARGET/Contents/Info" CFBundleName 2>/dev/null || echo "")"
    [ "$ident" = Nook ] || fail "$TARGET exists but is not Nook (CFBundleName=${ident:-none}). Refusing to replace it."
fi

# Only the copy we are about to replace matters; a Nook running from somewhere else is not ours
# to quit.
RUNNING="$TARGET/Contents/MacOS/Nook"
if [ -n "$(nook_pids "$RUNNING")" ]; then
    step "Nook is running from $TARGET"
    if ask "Quit it so the new build can replace it?" y; then
        quit_nook "$RUNNING"
    else
        fail "cannot replace $TARGET while it is running. Quit Nook and run this again."
    fi
fi

step "Installing $TARGET"
STAGE="$APP_DIR/.Nook.app.new.$$"
rm -rf "$STAGE"
# ditto preserves the bundle's symlinks, resource forks and signature; cp -R does not.
ditto "$BUILT" "$STAGE"
rm -rf "$TARGET"
mv "$STAGE" "$TARGET"
# A locally built app carries no quarantine attribute, so Gatekeeper never prompts. Clear it
# anyway in case the source tree itself arrived as a download.
xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true

VERSION="$(defaults read "$TARGET/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "?")"

# --- 6. what now ------------------------------------------------------------------------------

cat <<EOF

${bold}Nook $VERSION is installed at $TARGET${reset}

  • Nook has no Dock icon. It lives in the menu bar (the stacked-windows icon) and puts a
    small "+" orb in a corner of your screen.
  • Click the ${bold}+${reset} orb, pick a project folder, and an agent window appears there.
  • ${bold}Settings…${reset} is in the menu bar icon's menu, along with New Agent and Quit.
  • The first time you use push-to-talk, "look at this", or approvals, macOS will ask for the
    microphone, screen recording and notifications. See docs/INSTALL.md for what each is for.
  • To update: run this installer again. To remove it: $SRC/scripts/uninstall.sh

EOF

if [ "${NOOK_LAUNCH:-1}" != 0 ] && ask "Launch Nook now?" y; then
    open "$TARGET"
    info "launched; look for the menu bar icon."
fi
