#!/bin/bash
# Archives EZCaliOS and exports (or uploads) it for TestFlight. Usage: scripts/ios_testflight.sh
# Env: TEAM (default MN3744WT73), BUILD (CURRENT_PROJECT_VERSION; default timestamp yymmddHHMM so it always increases),
#      UPLOAD=1 uploads to App Store Connect; otherwise exports an .ipa to build/ios/export for inspection.
# Needs: Apple ID signed into Xcode (automatic signing creates the distribution cert/profiles), the app record and
# bundle IDs registered in App Store Connect, xcodegen, and Sources/EZCal/Core/Secrets.swift (compiled in).
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f Sources/EZCal/Core/Secrets.swift ] || { echo "Sources/EZCal/Core/Secrets.swift is missing; the app won't compile without it"; exit 1; }
TEAM="${TEAM:-MN3744WT73}"
BUILD="${BUILD:-$(date +%y%m%d%H%M)}"
UPLOAD="${UPLOAD:-0}"
OUT=build/ios
ARCHIVE="$OUT/EZCaliOS.xcarchive"
rm -rf "$ARCHIVE" "$OUT/export"
mkdir -p "$OUT"

(cd Apps/iOS && xcodegen generate)
xcodebuild archive -project Apps/iOS/EZCaliOS.xcodeproj -scheme EZCaliOS \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" CURRENT_PROJECT_VERSION="$BUILD"

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
  -exportPath "$OUT/export" -allowProvisioningUpdates

if [ "$UPLOAD" = 1 ]; then echo "Uploaded build $BUILD to App Store Connect"; else echo "Exported $OUT/export (build $BUILD); rerun with UPLOAD=1 to upload"; fi
