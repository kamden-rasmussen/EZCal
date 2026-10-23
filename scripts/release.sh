#!/bin/bash
# Builds, signs (Developer ID), notarizes and zips EZCal. Usage: VERSION=1.0.0 scripts/release.sh
# Needs: Developer ID Application cert in keychain, `xcrun notarytool store-credentials ezcal-notary`,
# and Sources/EZCal/Core/Secrets.swift (compiled in), plus `gh` logged in with push access to the tap.
# Publishes to the tap's GitHub Releases, bumps Casks/ezcal.rb (draft release -> bump cask -> publish release), and tags this repo. PUBLISH=0 stops after the zip.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${VERSION:?Set VERSION=x.y.z}"
TAP="${TAP_REPO:-kamden-rasmussen/homebrew-tap}"
TAG="ezcal-v$VERSION"
SRC="${SRC_REPO:-kamden-rasmussen/EZCal}"
PUBLISH="${PUBLISH:-1}"
if [ "$PUBLISH" = 1 ]; then
  [ -z "$(git status --porcelain)" ] || { echo "Working tree is dirty; commit first"; exit 1; }
  git fetch -q origin && [ -n "$(git branch -r --contains HEAD)" ] || { echo "HEAD isn't pushed; the release notes link to it"; exit 1; }
  git rev-parse "v$VERSION" >/dev/null 2>&1 && { echo "Tag v$VERSION already exists"; exit 1; }
  gh release view "$TAG" --repo "$TAP" >/dev/null 2>&1 && { echo "Release $TAG already exists on $TAP"; exit 1; }
fi
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

[ "$PUBLISH" = 1 ] || exit 0
SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')
# The in-app update checker treats any visible ezcal-v* release as "new version available" and tells users to
# run `brew upgrade`, so the release must not be visible until the cask points at it. Order: draft release
# (asset uploaded, so the cask URL resolves) -> bump + push cask -> make the release visible.
# Notes link back to the source. They use the commit (the v$VERSION tag is only pushed at the very end).
FULL=$(git rev-parse HEAD)
NOTES="EZCal $VERSION, built from [$SRC@v$VERSION](https://github.com/$SRC/commit/$FULL) (\`${FULL:0:7}\`)."
PREV=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)
[ -z "$PREV" ] || NOTES="$NOTES"$'\n\n'"Changes since $PREV: https://github.com/$SRC/compare/$PREV...$FULL"
gh release create "$TAG" "$ZIP" --repo "$TAP" --title "EZCal $VERSION" --notes "$NOTES" --draft

TMP=$(mktemp -d)
gh repo clone "$TAP" "$TMP" -- --quiet
sed -i '' -E "s/^  version \".*\"/  version \"$VERSION\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/; s|^  homepage \".*\"|  homepage \"https://github.com/$SRC\"|" "$TMP/Casks/ezcal.rb"
git -C "$TMP" commit -qam "ezcal $VERSION"
git -C "$TMP" push -q
rm -rf "$TMP"

gh release edit "$TAG" --repo "$TAP" --draft=false

git tag "v$VERSION" && git push origin "v$VERSION"
echo "Released $VERSION. Users: brew update && brew upgrade --cask ezcal"
