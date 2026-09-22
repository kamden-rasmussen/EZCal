# EZCal

A free, hackable, native macOS calendar for Google Calendar, inspired by Notion Calendar.

- **Google Calendar**: multiple accounts, day / week / month views, create / edit / delete / RSVP
- **iCloud & Apple Calendar accounts**: every calendar macOS already syncs (iCloud, Exchange, Fastmail, CalDAV) appears alongside Google, with no passwords or API keys. Events on both are de-duplicated.
- **Coworker overlay**: search your Google Workspace directory, click a person, and their calendar appears in your grid (full details if they share them with you, free/busy blocks if not)
- **Zoom in one click**: pick "Zoom" when creating an event, or hit "Add Zoom meeting" on an existing one. Real Zoom meetings are created through the Zoom API and attached to the event. Google Meet works too.
- **Availability check** while inviting people ("Alice is busy at this time")
- **Join buttons** on every event with a Zoom / Meet / Teams link, plus a menu bar item showing your next meeting
- Click or drag on the grid to create an event

Pure SwiftUI, no dependencies. Tokens live in your macOS Keychain and requests go straight from your Mac to Google/Zoom; there's no server.

## Build & run

Requires macOS 14+ and Xcode / Swift 5.9+.

```bash
scripts/build_app.sh --run        # builds build/EZCal.app and opens it
scripts/build_app.sh --install    # also copies it to /Applications
swift test                        # unit tests
open Package.swift                # or edit/debug in Xcode
```

If you have an Apple Development certificate the script signs with it automatically, which stops Keychain from re-asking for permission after every rebuild. Otherwise it signs ad-hoc (works fine, you'll just see a Keychain prompt per rebuild; click "Always Allow").

## One-time setup

You bring your own API credentials, so the app is free and nothing is shared with anyone else.

### 0. iCloud / Apple Calendar (optional, zero setup)

Click **Use my iCloud / Apple Calendar accounts** on the welcome screen (or Settings → Accounts) and allow calendar access. EZCal reads whatever accounts you've added in System Settings → Internet Accounts, so to add iCloud, Exchange, etc., add them there.

Limits versus Google calendars: EventKit doesn't let apps invite people or set your RSVP, so those controls and Google Meet are hidden for Apple calendars, and Zoom meetings on them aren't auto-deleted when you delete the event. Coworker overlay is Google-only.

### 1. Google (optional if you only use Apple Calendar, ~5 min)

1. Go to <https://console.cloud.google.com/> and create a project (e.g. "EZCal").
2. **APIs & Services → Library**: enable **Google Calendar API** and **People API**.
3. **APIs & Services → OAuth consent screen** (or "Google Auth Platform"):
   - User type **Internal** if you're on Google Workspace (no verification needed and no test-user limits), otherwise **External** and add yourself as a test user.
4. **Credentials → Create credentials → OAuth client ID → Application type: Desktop app.**
5. Copy the **Client ID** and **Client secret** into EZCal's welcome screen (or Settings → Accounts), then click **Sign in with Google**.

Notes:
- Coworker search uses the Workspace directory (`directory.readonly`). Personal Gmail accounts have no directory, but you can still add people by typing their email.
- If your organization restricts third-party apps, an admin may need to allow your OAuth client.
- External apps in "Testing" mode have refresh tokens that expire after 7 days. Use **Internal**, or publish the app, to avoid re-signing in.

### 2. Zoom (optional, for one-click Zoom links)

1. Go to <https://marketplace.zoom.us/develop/create> and create a **General app** → **User-managed**.
2. **OAuth redirect URL**: `http://localhost:48291/callback` (also add it to the allow list).
3. **Scopes**: `meeting:write:meeting`, `meeting:update:meeting`, `meeting:delete:meeting`.
4. Copy the **Client ID** and **Client secret** into EZCal Settings → Zoom, then **Connect Zoom**.

You don't need to publish the Zoom app; leaving it in development works for your own account. If your Zoom admin restricts app installs, ask them to pre-approve it.

## How coworker overlay works

Add people with the **+** next to *Coworkers* in the sidebar. For each person EZCal tries, in order:

1. **Full events**: works if they've shared their calendar with you (or your org shares calendars org-wide).
2. **Free/busy blocks**: if only availability is shared, you'll see dashed "Alice · Busy" blocks and an eye-slash icon in the sidebar.
3. Otherwise the person gets a warning icon: they haven't shared anything.

Each person gets their own color. The same meeting on several calendars is shown once. Coworker events are drawn lighter with an outline and prefixed with their name.

## Keyboard

Everything is reachable without a mouse. Press **?** in the app for the cheat sheet and **⌘K** for the command palette (search events, jump to dates like "next friday", show/hide a coworker, run any command).

| Move around | |
|---|---|
| **T** | Today |
| **[** / **]** | Previous / next period |
| **G** | Go to date… |
| **D** / **5** / **W** / **M** | Day / Work week (Mon–Fri) / Week / Month |
| **/** or **⌘K** | Command palette |

| Events | |
|---|---|
| **N** or **⌘N** | New event |
| **↓ ↑** | Next / previous event (focus ring shows selection) |
| **→ ←** | Same time on the next / previous day |
| **↩** | Open event |
| **J** | Join the focused event's video call (or your next meeting) |

| On an open event | |
|---|---|
| **E** | Edit |
| **Z** | Add Zoom meeting |
| **Y / M / N** | RSVP yes / maybe / no |
| **⌫** | Delete |
| **esc** | Close |

Editing or deleting a recurring event first asks **This event** / **This and following events** / **All events** — pick one with **↑ ↓** + **↩**, or jump straight to it with **1 / 2 / 3**.

| In the editor | |
|---|---|
| **⌘↩** | Save |
| **esc** | Cancel |
| **⌃1 / ⌃2 / ⌃3** | Zoom / Google Meet / none |
| **⌃A** | All-day |

Also: **P** add coworker, **⌘\** toggle sidebar, **⌘⇧W** hide weekends, **⌘R** refresh, **⌘,** settings. Every action is in the *Calendar* and *Event* menus too. Mouse shortcuts: click the grid for a new event at that time, drag for a range, double-click a day header for day view.

Colors, spacing and type live in `Sources/EZCal/Core/Theme.swift`; the design source is the "EZCal Design" canvas. Light and dark mode follow the system.

## Project layout

```
Sources/EZCal/
  EZCalApp.swift            app entry, window, menu commands, menu bar item
  Core/Models.swift         Source / CalEvent / EventDraft, meeting-link detection
  Core/Util.swift           colors, RFC3339, Keychain, AppSettings
  Services/OAuth.swift      PKCE + loopback redirect, token refresh (Google & Zoom)
  Services/GoogleAPI.swift  Calendar, FreeBusy, People (directory) + event mapping
  Services/ZoomAPI.swift    create / update / delete Zoom meetings
  Services/EventKitService.swift  iCloud & system calendars via EventKit
  Store/CalendarStore.swift all app state: fetching, overlay merge, save/delete/RSVP
  Core/Theme.swift          design tokens, keycaps, button styles
  Store/Commands.swift      keyboard focus navigation + command palette items
  Views/                    TimeGridView, MonthView, Sidebar, editor, detail, palette, shortcuts, settings
Tests/EZCalTests/           layout, parsing, mapping, OAuth loopback tests
scripts/                    build_app.sh, make_icon.swift
```

Handy places to tweak: overlay/event styling in `EventBlock` (`TimeGridView.swift`), the collision layout in `EventLayout`, the palette in `Palette` (`Util.swift`), what gets written into the event when Zoom is attached in `CalendarStore.zoomBlock`.

## Known limitations / ideas

- "This and following events" (edit or delete) on Google splits the series by truncating the old RRULE and inserting a new one; this doesn't handle all-day recurring events' `UNTIL` correctly yet.
- Creating a recurring event only offers a few fixed patterns (daily, weekly, monthly, every weekday) — no custom RRULE builder.
- Deleting less than the whole series never detaches its Zoom meeting (only "All events" does).
- No drag-to-move / resize of existing events yet.
- No desktop notifications for upcoming meetings yet (the menu bar item shows the next one).
- Zoom meetings are created with Zoom's default settings; add fields to the `settings` dictionary in `ZoomAPI.createMeeting` (waiting room, mute on entry, etc.).
- Moving an event to another calendar isn't supported in the editor.

## License

MIT
