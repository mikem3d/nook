#!/bin/bash
# Builds Nook with SwiftPM and assembles a signed dist/Nook.app.
#
#   scripts/bundle.sh [debug|release]        (default: release)
#
# Environment:
#   NOOK_BUNDLE_ID   bundle identifier          (default: dev.nook.app, a placeholder)
#   NOOK_SIGN_ID     codesign identity          (default: "-", ad-hoc)
#
# macOS kills a process that asks for the microphone or speech recognition without usage strings
# in an Info.plist, so voice only works from this bundle, never from `swift run`.
# Notifications are the same: macOS files them, and the user's permission for them, under the bundle
# identifier, so keep NOOK_BUNDLE_ID stable between builds. An ad-hoc signature is enough; no
# entitlement or Info.plist key is needed (time-sensitive delivery would need a paid account's
# provisioning profile, so Nook does not use it).
set -euo pipefail

CONFIG="${1:-release}"
case "$CONFIG" in debug|release) ;; *) echo "usage: $0 [debug|release]" >&2; exit 2 ;; esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUNDLE_ID="${NOOK_BUNDLE_ID:-dev.nook.app}"
SIGN_ID="${NOOK_SIGN_ID:--}"
VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
APP="dist/Nook.app"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

echo "==> assembling $APP ($VERSION, build $BUILD)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Nook" "$APP/Contents/MacOS/Nook"

# SwiftPM's generated Bundle.module looks for Nook_Nook.bundle at the .app's root, where code
# signing does not allow it. Art.init (Manifest.swift) looks in Contents/Resources first.
cp -R "$BIN/Nook_Nook.bundle" "$APP/Contents/Resources/Nook_Nook.bundle"

sed -e "s/__BUNDLE_ID__/$BUNDLE_ID/" -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" \
    Support/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# The icon is drawn by a script; rebuild it only when that script changes.
ICNS=".build/icon/AppIcon.icns"
if [ ! -f "$ICNS" ] || [ scripts/make_icon.swift -nt "$ICNS" ]; then
    echo "==> drawing icon"
    rm -rf .build/icon && mkdir -p .build/icon
    swift scripts/make_icon.swift .build/icon/AppIcon.iconset
    iconutil -c icns .build/icon/AppIcon.iconset -o "$ICNS"
fi
cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"

echo "==> signing ($([ "$SIGN_ID" = "-" ] && echo ad-hoc || echo "$SIGN_ID"))"
SIGN_ARGS=(--force --deep --options runtime --entitlements Support/Nook.entitlements --sign "$SIGN_ID")
# A Developer ID signature needs a secure timestamp to be notarised; ad-hoc cannot have one.
[ "$SIGN_ID" = "-" ] || SIGN_ARGS+=(--timestamp)
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --deep --strict "$APP"

echo "==> $ROOT/$APP"
