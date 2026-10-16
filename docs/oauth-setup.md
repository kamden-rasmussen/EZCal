# Setting up your own OAuth clients

EZCal signs in to Google and Zoom with OAuth clients that are compiled into the app at build time (see `Sources/EZCal/Core/Secrets.swift.example`). If you build EZCal yourself, create your own and put them in `Secrets.swift` (gitignored). Apple Calendar, Reminders and `.ics` subscriptions need no setup.

## 1. Google (optional if you only use Apple Calendar, ~5 min)

1. Go to <https://console.cloud.google.com/> and create a project (e.g. "EZCal").
2. **APIs & Services → Library**: enable **Google Calendar API** and **People API**.
3. **APIs & Services → OAuth consent screen** (or "Google Auth Platform"):
   - User type **Internal** if you're on Google Workspace (no verification needed and no test-user limits), otherwise **External** and add yourself as a test user.
4. **Credentials → Create credentials → OAuth client ID → Application type: Desktop app.**
5. Copy `Sources/EZCal/Core/Secrets.swift.example` to `Sources/EZCal/Core/Secrets.swift` (gitignored) and paste the **Client ID** and **Client secret** into `googleClientID`/`googleClientSecret`. Rebuild, then click **Sign in with Google**.

Notes:
- Coworker search uses the Workspace directory (`directory.readonly`). Personal Gmail accounts have no directory, but you can still add people by typing their email.
- If your organization restricts third-party apps, an admin may need to allow your OAuth client.
- External apps in "Testing" mode have refresh tokens that expire after 7 days. Use **Internal**, or publish the app, to avoid re-signing in.

## 2. Zoom (optional, for one-click Zoom links)

1. Go to <https://marketplace.zoom.us/develop/create> and create a **General app** → **User-managed**.
2. **OAuth redirect URL**: `http://localhost:48291/callback` (also add it to the allow list).
3. **Scopes**: `meeting:write:meeting`, `meeting:update:meeting`, `meeting:delete:meeting`.
4. Paste the **Client ID** and **Client secret** into `zoomClientID`/`zoomClientSecret` in the same `Secrets.swift`. Rebuild, then click **Connect Zoom** in Settings → Zoom.

You don't need to publish the Zoom app; leaving it in development works for your own account. If your Zoom admin restricts app installs, ask them to pre-approve it.

Meeting defaults (waiting room, mute on entry, join before host, host/participant video, passcode) live in Settings → Zoom; each event's editor starts from those and lets you change them before the meeting is created. "Remove Zoom link" on an event deletes the Zoom meeting and strips it from the event. If Zoom rejects EZCal's token (revoked or expired), the next Zoom action shows an error with a one-click **Reconnect Zoom** — in the banner at the top of the window, in Settings → Zoom, or right in the editor.
