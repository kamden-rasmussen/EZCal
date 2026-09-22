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
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Sign with a stable identity if you have one (keeps Keychain from re-prompting after every rebuild);
# otherwise fall back to ad-hoc. Override with CODESIGN_IDENTITY="Developer ID Application: ..."
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')}"
IDENTITY="${IDENTITY:--}"
codesign --force --sign "$IDENTITY" "$APP" >/dev/null
echo "Built $APP (signed with: $IDENTITY)"

for arg in "$@"; do
  case "$arg" in
    --install) rm -rf /Applications/EZCal.app && cp -R "$APP" /Applications/ && echo "Installed to /Applications" ;;
    --run) open "$APP" ;;
  esac
done
