# iOS TODO

- [ ] **Create a Google OAuth client of type "iOS"** (Google Cloud Console → APIs & Services → Credentials → Create credentials → OAuth client ID → iOS, bundle ID `com.ezcal.app.ios`), in the same project as the existing macOS client so the consent screen and scopes are shared.
  - Paste the client ID into your local `Sources/EZCal/Core/Secrets.swift` as `googleIOSClientID` (see `Secrets.swift.example`).
  - The redirect scheme is the reversed client ID (`com.googleusercontent.apps.<id>`); add it to `CFBundleURLTypes` in `Apps/iOS/Info.plist` if the sign-in callback doesn't return to the app.
- [ ] Register the `ezcal:/oauth2redirect` redirect URI in the Zoom app.
