# EZCal iOS

XcodeGen project (`project.yml`). Sources are in `Sources/`; shared code is compiled from `../../Sources/EZCal/{Core,Store,Services}`.
This build reads on-device calendars (iCloud etc.) via EventKit. Google Calendar works once an iOS OAuth client is configured (below); Zoom is not set up on iOS yet (see GitHub issue #37).

## Google sign-in
Sign-in is disabled (with a hint in Settings and on the connect screen) until `googleIOSClientID` is set.
1. Create an OAuth client of type "iOS" for bundle ID `com.ezcal.app.ios` (see `TODO.md`) and put its client ID in `Sources/EZCal/Core/Secrets.swift` as `googleIOSClientID`.
2. Put the reversed client ID in `Apps/iOS/Config/Local.xcconfig` (gitignored): `GOOGLE_IOS_URL_SCHEME = com.googleusercontent.apps.<id>`. `Info.plist` reads it into `CFBundleURLTypes`; the default placeholder in `Base.xcconfig` keeps builds working without it.
3. Rebuild. Settings > Google accounts adds, re-signs-in and removes accounts.

## Simulator
`make ios-test` runs the UI tests (demo data, in-memory).

## Run on your iPhone
1. On the phone: Settings > Privacy & Security > Developer Mode > on (restarts the phone). Trust the Mac when prompted.
2. Find your Team ID (developer.apple.com > Membership) and either
   - `cp Apps/iOS/Config/Local.xcconfig.example Apps/iOS/Config/Local.xcconfig` and edit it (gitignored), or
   - pass `TEAM=ABCDE12345` to make.
3. Get the device id: `xcrun devicectl list devices`.
4. `make ios-device DEVICE=<udid> TEAM=<team id>` builds, signs (automatic signing), installs and launches.
   Alternatively `cd Apps/iOS && xcodegen generate && open EZCaliOS.xcodeproj`, pick your phone and Run.
5. First launch: if iOS says "Untrusted Developer", go to Settings > General > VPN & Device Management > your Apple ID > Trust.
6. Tap "Connect calendars" and allow full calendar access.

The bundle id `com.ezcal.app.ios` must be unique to your team; change it in `project.yml` if signing complains.
The app icon is `Sources/Assets.xcassets/AppIcon.appiconset/icon-1024.png` (opaque, full-bleed; iOS applies the rounded mask).

## TestFlight
iPhone-only build. Prerequisites:
- Your Apple ID is signed into Xcode (Settings > Accounts) so automatic signing can create the distribution cert and profiles.
- The app record exists in App Store Connect, and the bundle IDs `com.ezcal.app.ios` and `com.ezcal.app.ios.widget` plus the App Group `group.com.ezcal.app` are registered in the developer portal.

Commands:
- `make ios-testflight` archives and exports an .ipa to `build/ios/export` for inspection.
- `make ios-testflight UPLOAD=1` uploads the build to App Store Connect.
- `TEAM=<team id>` (default `MN3744WT73`) and `BUILD=<n>` (build number; default a `yymmddHHMM` timestamp) are optional.
