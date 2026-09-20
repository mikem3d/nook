#!/bin/bash
# Signs Nook.app with a Developer ID, has Apple notarise it, and staples the ticket, producing
# dist/Nook-<version>.zip that opens on any Mac without a Gatekeeper warning.
#
# One-time setup:
#   1. Join the Apple Developer Program and create a "Developer ID Application" certificate
#      (Xcode › Settings › Accounts › Manage Certificates). Check it is installed with:
#        security find-identity -v -p codesigning
#   2. Store notarisation credentials in the keychain under a profile name:
#        xcrun notarytool store-credentials nook-notary \
#          --apple-id you@example.com --team-id ABCDE12345 --password <app-specific password>
#      (app-specific passwords: https://account.apple.com › Sign-In and Security)
#   3. Pick the real bundle identifier; it is baked into the signature.
#
# Then:
#   NOOK_SIGN_ID="Developer ID Application: Your Name (ABCDE12345)" \
#   NOOK_NOTARY_PROFILE=nook-notary \
#   NOOK_BUNDLE_ID=com.yourdomain.nook \
#   scripts/notarize.sh
#
# Steps performed: release build and bundle (scripts/bundle.sh, hardened runtime, secure
# timestamp, Support/Nook.entitlements) -> zip -> notarytool submit --wait -> stapler staple ->
# Gatekeeper assessment -> final zip of the stapled app.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail() { echo "notarize: $*" >&2; exit 1; }

[ -n "${NOOK_SIGN_ID:-}" ] || fail "NOOK_SIGN_ID is not set. It must name a Developer ID Application identity, e.g.
  NOOK_SIGN_ID=\"Developer ID Application: Your Name (TEAMID)\"
List the identities you have with: security find-identity -v -p codesigning
See the setup notes at the top of this script."
[ "$NOOK_SIGN_ID" != "-" ] || fail "NOOK_SIGN_ID is \"-\" (ad-hoc). Apple only notarises Developer ID signatures."
[ -n "${NOOK_NOTARY_PROFILE:-}" ] || fail "NOOK_NOTARY_PROFILE is not set. Create one with:
  xcrun notarytool store-credentials <profile> --apple-id <id> --team-id <team> --password <app-specific password>"
security find-identity -v -p codesigning | grep -F -q "$NOOK_SIGN_ID" \
    || fail "no code-signing identity matching \"$NOOK_SIGN_ID\" in your keychains."
[ "${NOOK_BUNDLE_ID:-dev.nook.app}" != "dev.nook.app" ] \
    || echo "notarize: warning: still using the placeholder bundle id dev.nook.app (set NOOK_BUNDLE_ID)" >&2

VERSION="$(tr -d '[:space:]' < VERSION)"
APP="dist/Nook.app"
UPLOAD="dist/Nook-upload.zip"
FINAL="dist/Nook-$VERSION.zip"

scripts/bundle.sh release

echo "==> submitting to Apple (this usually takes a few minutes)"
rm -f "$UPLOAD" "$FINAL"
ditto -c -k --keepParent "$APP" "$UPLOAD"
xcrun notarytool submit "$UPLOAD" --keychain-profile "$NOOK_NOTARY_PROFILE" --wait \
    || fail "notarisation failed. Read the log with: xcrun notarytool log <submission id> --keychain-profile $NOOK_NOTARY_PROFILE"
rm -f "$UPLOAD"

echo "==> stapling"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

ditto -c -k --keepParent "$APP" "$FINAL"
echo "==> $ROOT/$FINAL"
