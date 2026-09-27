# EZCal Deployment Plan

Goal: ship EZCal to a handful of friends and coworkers via a **Homebrew cask** and keep their installs current.

Homebrew never updates casks in the background on its own (`brew upgrade` is manual), so requirement 2 needs an in-app update check. The plan is: GitHub Releases host the builds, a personal tap publishes the cask, and the app checks GitHub for newer versions and helps the user run the upgrade.

## Decisions (made)

- **Signing:** paid Apple Developer ID plus notarization. No Gatekeeper workaround needed, and Keychain stays stable across updates.
- **Repos:** `ezcal` stays **private** (source and `Secrets.swift`). A **public** `homebrew-tap` repo holds `Casks/ezcal.rb` and also hosts the release zips on its Releases page, so the cask download and the in-app update check both work without auth.
- **Update UX:** the app shows "Update available, run `brew upgrade --cask ezcal`" with a copy button. Auto-running the upgrade is a later iteration.

## Prerequisites
- [ ] Enroll in the Apple Developer Program.
- [ ] Create a **Developer ID Application** certificate and install it in the login keychain.
- [ ] Store notarization credentials: `xcrun notarytool store-credentials "ezcal-notary"` (Apple ID, team ID, app-specific password).
- [ ] Create the public `homebrew-tap` repo.

## Tasks

### 1. Versioning
- [ ] Set `CFBundleShortVersionString` (e.g. `1.0.0`) and `CFBundleVersion` in `Resources/Info.plist`.
- [ ] Have `scripts/build_app.sh` accept a `VERSION` env var and stamp it into the built Info.plist so the tag, the plist and the app agree.
- [ ] Add `make version` to print the current version.

### 2. Release build
- [ ] Add `scripts/release.sh` and a `make release VERSION=x.y.z` target that:
  - builds and signs `build/EZCal.app` with the Developer ID via `CODESIGN_IDENTITY`
  - notarizes with `xcrun notarytool submit --keychain-profile ezcal-notary --wait` and staples the ticket (with the hardened runtime: `codesign --options runtime`)
  - zips with `ditto -c -k --keepParent build/EZCal.app build/EZCal-x.y.z.zip`
  - prints the SHA256 (`shasum -a 256`)
- [ ] Make sure the release is built from a machine or CI that has `Sources/EZCal/Core/Secrets.swift` (OAuth client IDs and secrets are compiled in).
- [ ] Confirm the Google OAuth consent screen is **Internal** or **published**, or friends will be signed out every 7 days. Add friends' Google accounts as test users if it stays in Testing.

### 3. Publish to GitHub Releases
- [ ] Create a tag `vX.Y.Z` and a GitHub Release with the zip attached on the tap repo (`gh release create vX.Y.Z build/EZCal-X.Y.Z.zip --repo <user>/homebrew-tap`).
- [ ] Optional: a GitHub Actions workflow that does this on tag push. Note it needs the OAuth secrets stored as repo secrets and `Secrets.swift` generated at build time, plus signing certificates if using Developer ID.

### 4. Homebrew tap
- [ ] Create a public repo named `homebrew-tap` (so users run `brew tap <user>/tap`).
- [ ] Add `Casks/ezcal.rb`:
  ```ruby
  cask "ezcal" do
    version "1.0.0"
    sha256 "<sha256 of zip>"

    url "https://github.com/<user>/homebrew-tap/releases/download/v#{version}/EZCal-#{version}.zip"
    name "EZCal"
    desc "Menu bar calendar with one-click Zoom and Meet"
    homepage "https://github.com/<user>/ezcal"

    depends_on macos: ">= :sonoma"

    app "EZCal.app"

    zap trash: [
      "~/Library/Preferences/<bundle-id>.plist",
    ]
  end
  ```
- [ ] Add a step to `make release` (or a script) that updates `version` and `sha256` in the cask and pushes to the tap repo.
- [ ] Test on a clean account: `brew tap <user>/tap && brew install --cask ezcal`.
- [ ] Friends' install instructions go in the README: `brew install --cask <user>/tap/ezcal`.

### 5. In-app update check
- [ ] Add an `UpdateChecker` service: on launch and every ~6 hours, `GET https://api.github.com/repos/<user>/homebrew-tap/releases/latest`, compare `tag_name` with `CFBundleShortVersionString`.
- [ ] Add a "Check for Updates…" menu item and an "Update available" indicator.
- [ ] Update action: show `brew upgrade --cask ezcal` with a copy button (or run it, then relaunch, in a later iteration).
- [ ] Unit test the version comparison (e.g. `1.10.0 > 1.9.0`) in `Tests/EZCalTests`.
- [ ] Add a "Launch at login" toggle if not present, so updates are picked up regularly.

### 6. Docs and cleanup
- [ ] README: add an **Install** section (tap + install + upgrade commands) and a **Releasing** section pointing here.
- [ ] Decide whether `Makefile` and `.claude/` (currently untracked) should be committed.
- [ ] Do a dry run: release `1.0.0`, install via brew, release `1.0.1`, confirm the app shows the update and `brew upgrade --cask ezcal` gets it.

## Risks and notes
- **OAuth secrets are embedded** in every distributed binary. Acceptable for a small trusted group, but they can be extracted. Rotate them if a build leaks.
- **Homebrew only upgrades when the user runs it** (or `brew upgrade` in a cron/autoupdate). The in-app check is what makes updates discoverable.
- Homebrew's `brew autoupdate` (from `homebrew/autoupdate`) can be suggested to friends who want fully automatic upgrades.
