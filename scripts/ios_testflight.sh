#!/bin/bash
# Archives EZCaliOS and exports (or uploads) it for TestFlight. Usage: scripts/ios_testflight.sh
# Env: TEAM (default MN3744WT73), BUILD (CURRENT_PROJECT_VERSION; default timestamp yymmddHHMM so it always increases),
#      UPLOAD=1 uploads to App Store Connect and, with an API key, adds the build to the external "Testing" group (NO_DISTRIBUTE=1 skips); otherwise exports an .ipa to build/ios/export for inspection.
#      ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID: App Store Connect API key (.p8); use instead of an Apple ID signed into Xcode.
# Needs: Apple ID signed into Xcode or an API key (automatic signing creates the distribution cert/profiles), the app record and
# bundle IDs registered in App Store Connect, xcodegen, and Sources/EZCal/Core/Secrets.swift (compiled in).
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f Sources/EZCal/Core/Secrets.swift ] || { echo "Sources/EZCal/Core/Secrets.swift is missing; the app won't compile without it"; exit 1; }
TEAM="${TEAM:-MN3744WT73}"
BUILD="${BUILD:-$(date +%y%m%d%H%M)}"
UPLOAD="${UPLOAD:-0}"
AUTH=()
if [ -n "${ASC_KEY_PATH:-}" ]; then
  [ -f "$ASC_KEY_PATH" ] && [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ] \
    || { echo "ASC_KEY_PATH must be an existing .p8 and ASC_KEY_ID / ASC_ISSUER_ID must be set"; exit 1; }
  AUTH=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi
OUT=build/ios
ARCHIVE="$OUT/EZCaliOS.xcarchive"
rm -rf "$ARCHIVE" "$OUT/export"
mkdir -p "$OUT"

(cd Apps/iOS && xcodegen generate)
# Archive unsigned: an automatically signed archive wants a development profile, which needs a registered device, and
# Apple's cloud-managed distribution cert has no private key on this Mac (it signs at export). Unsigned archives drop
# the entitlements, so ad-hoc sign each bundle with its entitlements file; the export re-signs for distribution and
# keeps them (the app group is how the widget reads the app's data).
xcodebuild archive -project Apps/iOS/EZCaliOS.xcodeproj -scheme EZCaliOS \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM="$TEAM" CURRENT_PROJECT_VERSION="$BUILD"
APP="$ARCHIVE/Products/Applications/EZCaliOS.app"
codesign -f -s - --entitlements Apps/iOS/Widget/EZCalWidget.entitlements "$APP/PlugIns/EZCalWidget.appex"
codesign -f -s - --entitlements Apps/iOS/EZCaliOS.entitlements "$APP"

if [ "$UPLOAD" = 1 ]; then DEST=upload; else DEST=export; fi
cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>destination</key><string>$DEST</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -exportPath "$OUT/export" -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"}

if [ "$UPLOAD" = 1 ]; then
  echo "Uploaded build $BUILD to App Store Connect"
  if [ -n "${ASC_KEY_PATH:-}" ] && [ "${NO_DISTRIBUTE:-0}" != 1 ]; then scripts/ios_testflight_distribute.py "$BUILD"; fi
else echo "Exported $OUT/export (build $BUILD); rerun with UPLOAD=1 to upload"; fi
