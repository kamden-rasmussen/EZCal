# iOS TODO

- [ ] **Create a Google OAuth client of type "iOS"** (Google Cloud Console → APIs & Services → Credentials → Create credentials → OAuth client ID → iOS, bundle ID `com.ezcal.app.ios`), in the same project as the existing macOS client so the consent screen and scopes are shared.
  - Paste the client ID into your local `Sources/EZCal/Core/Secrets.swift` as `googleIOSClientID` (see `Secrets.swift.example`).
  - The redirect scheme is the reversed client ID (`com.googleusercontent.apps.<id>`); set `GOOGLE_IOS_URL_SCHEME` to it in `Apps/iOS/Config/Local.xcconfig` (read by `Info.plist`).
  - The sign-in UI (Settings, connect screen) is done (#174); it stays disabled until the client ID is set. Then test sign-in on a device, plus Google create/edit/delete/recurring/guests end to end.
- [ ] Register the `ezcal:/oauth2redirect` redirect URI in the Zoom app.
