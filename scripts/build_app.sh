#!/bin/bash
# Builds a release EZCal.app into ./build. Usage: scripts/build_app.sh [--install] [--run]
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/EZCal.app"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/EZCal"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/EZCal"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Stamp VERSION (and optional BUILD) into the built plist so tag, plist and app agree.
if [ -n "${VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD:-$VERSION}" "$APP/Contents/Info.plist"
fi
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Sign with a stable identity if you have one (keeps Keychain from re-prompting after every rebuild);
# otherwise fall back to ad-hoc. Override with CODESIGN_IDENTITY="Developer ID Application: ..."
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')}"
IDENTITY="${IDENTITY:--}"
codesign --force --entitlements Resources/EZCal.entitlements ${HARDENED:+--options runtime --timestamp} --sign "$IDENTITY" "$APP" >/dev/null
# Without the Calendars entitlement a hardened-runtime build is silently denied calendar access (no prompt).
codesign -d --entitlements - "$APP" 2>/dev/null | grep -q "personal-information.calendars" \
  || { echo "error: $APP is missing the Calendars entitlement"; exit 1; }
echo "Built $APP (signed with: $IDENTITY)"

for arg in "$@"; do
  case "$arg" in
    --install) rm -rf /Applications/EZCal.app && cp -R "$APP" /Applications/ && echo "Installed to /Applications" ;;
    --run) open "$APP" ;;
  esac
done
