#!/bin/bash
# Builds, signs (Developer ID), notarizes and zips EZCal. Usage: VERSION=1.0.0 scripts/release.sh
# Needs: Developer ID Application cert in keychain, `xcrun notarytool store-credentials ezcal-notary`,
# and Sources/EZCal/Core/Secrets.swift (compiled in).
set -euo pipefail
cd "$(dirname "$0")/.."
: "${VERSION:?Set VERSION=x.y.z}"
PROFILE="${NOTARY_PROFILE:-ezcal-notary}"
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')}"
[ -n "$IDENTITY" ] || { echo "No Developer ID Application identity found"; exit 1; }

VERSION="$VERSION" HARDENED=1 CODESIGN_IDENTITY="$IDENTITY" scripts/build_app.sh
ZIP="build/EZCal-$VERSION.zip"
ditto -c -k --keepParent build/EZCal.app "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple build/EZCal.app
rm "$ZIP" && ditto -c -k --keepParent build/EZCal.app "$ZIP"   # re-zip with the stapled ticket
spctl --assess --type execute -v build/EZCal.app
echo "Built $ZIP"
shasum -a 256 "$ZIP"
