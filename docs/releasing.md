# Releasing

Release (needs the Developer ID cert, the `ezcal-notary` notarytool profile, `Secrets.swift`, and `gh` with push access to the tap):

1. Bump `CFBundleShortVersionString`/`CFBundleVersion` in `Resources/Info.plist` and commit.
2. `make release VERSION=x.y.z`. This builds, signs, notarizes and staples, uploads the zip to a draft `ezcal-vX.Y.Z` release on `homebrew-tap`, bumps `Casks/ezcal.rb`, then publishes the release (so the in-app update checker never sees a release whose cask isn't bumped yet), and tags this repo `vX.Y.Z`. `PUBLISH=0` stops after the zip.

Notes: OAuth secrets are compiled into every binary, so rotate them if a build leaks. Homebrew only upgrades when the user runs it; EZCal (macOS) checks the tap's `ezcal-v*` releases on launch and every ~6h, shows an "Update available" pill, and has **Check for Updates…** in the app menu with the `brew` command to copy.
