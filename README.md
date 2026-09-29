# EZCal

A free, hackable, native macOS calendar for Google Calendar, inspired by Notion Calendar.

- **Google Calendar**: multiple accounts, day / week / month views, create / edit / delete / RSVP
- **iCloud & Apple Calendar accounts**: every calendar macOS already syncs (iCloud, Exchange, Fastmail, CalDAV) appears alongside Google, with no passwords or API keys. Events on both are de-duplicated.
- **Subscribe to .ics calendars**: paste a `webcal://` or `https://` link (a sports schedule, a shared team calendar, a holiday list) and it shows up in the sidebar, read-only, refreshing itself in the background.
- **Coworker overlay**: search your Google Workspace directory, click a person, and their calendar appears in your grid (full details if they share them with you, free/busy blocks if not)
- **Zoom in one click**: pick "Zoom" when creating an event, or hit "Add Zoom meeting" on an existing one, with your own defaults (waiting room, mute on entry, join before host, host/participant video, passcode) editable per event. Real Zoom meetings are created through the Zoom API and attached to the event, deleted when you delete the event or remove the link, and updated if you move the event's time. Google Meet works too.
- **Availability check** while inviting people ("Alice is busy at this time")
- **Find a time** (⌘F in the editor, or ⌘K → "Find a time for coworkers"): lists the best slots where every attendee you can see is free, with a per-day availability grid; people whose calendars aren't shared show as "unknown" and never block a slot
- **Join buttons** on every event with a Zoom / Meet / Teams link, plus a menu bar item showing your next meeting
- **Meeting reminders**: opt-in notifications a few minutes before each meeting, with a Join button when it has a video link and Open to jump to it in EZCal. Turn on in Settings → General; works while the window is closed as long as EZCal is running (menu bar item).
- Click or drag on the grid to create an event
- **Tasks**: due-dated Apple Reminders show up right in the grid (a chip in the all-day row, or a small timed marker), with a checkbox to complete them and quick-add via ⌘K (`task: call dentist tomorrow 3pm`)
- **Multi-window**: ⌘⇧N opens a second window (e.g. to compare two weeks) with its own date/view/selection state

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

Limits versus Google calendars: EventKit doesn't let apps invite people or set your RSVP, so those controls and Google Meet are hidden for Apple calendars. Coworker overlay is Google-only.

### 0.5 Subscribe to a calendar URL (optional, zero setup)

Settings → Accounts → **Add calendar by URL…** (also in ⌘K and the Calendar menu), then paste a `webcal://` or `https://` link — a sports league's schedule, a shared team calendar, a public holiday feed. It appears in the sidebar like any other calendar, refreshes itself alongside your other calendars, and is read-only (no editor, RSVP or delete). A feed that's temporarily unreachable shows a warning icon next to its name instead of losing its events or blocking your other calendars.

Recurring events (RRULE) are expanded for daily/weekly/monthly/yearly frequencies with COUNT, UNTIL, INTERVAL and BYDAY (including "2nd Tuesday of the month" style rules); very old Outlook-style time zone names (rather than IANA ones like `America/New_York`) aren't recognized and fall back to your Mac's local time zone.

Google and Zoom sign-in both need an OAuth client, but there's no Settings UI for pasting one in — the client ID/secret are baked into the app at build time (see `Sources/EZCal/Core/Secrets.swift.example`), so everyone who runs a given build shares the same OAuth client and just clicks **Sign in**. If you're building EZCal yourself, create your own and drop them in:

### 1. Google (optional if you only use Apple Calendar, ~5 min)

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

### 2. Zoom (optional, for one-click Zoom links)

1. Go to <https://marketplace.zoom.us/develop/create> and create a **General app** → **User-managed**.
2. **OAuth redirect URL**: `http://localhost:48291/callback` (also add it to the allow list).
3. **Scopes**: `meeting:write:meeting`, `meeting:update:meeting`, `meeting:delete:meeting`.
4. Paste the **Client ID** and **Client secret** into `zoomClientID`/`zoomClientSecret` in the same `Secrets.swift`. Rebuild, then click **Connect Zoom** in Settings → Zoom.

You don't need to publish the Zoom app; leaving it in development works for your own account. If your Zoom admin restricts app installs, ask them to pre-approve it.

Meeting defaults (waiting room, mute on entry, join before host, host/participant video, passcode) live in Settings → Zoom; each event's editor starts from those and lets you change them before the meeting is created. "Remove Zoom link" on an event deletes the Zoom meeting and strips it from the event. If Zoom rejects EZCal's token (revoked or expired), the next Zoom action shows an error with a one-click **Reconnect Zoom** — in the banner at the top of the window, in Settings → Zoom, or right in the editor.

### How EZCal remembers an Apple Calendar event's Zoom meeting

EventKit (iCloud/Apple Calendar) has no field for arbitrary app metadata, so there's nowhere obvious to store "this event's Zoom meeting is #123". EZCal keeps the id in a single hidden line appended to the event's notes — two zero-width spaces bracketing `EZCAL-ZOOM:<id>` — which `EventKitService` strips out before showing notes anywhere in the app or re-adds when saving. This was chosen over a local id-to-event map (keyed by EventKit's `eventIdentifier`) because the marker travels with the event itself: it survives EZCal being reinstalled, another device editing the same iCloud event, and EventKit occasionally reassigning identifiers, all of which would silently orphan a local map. The formatting/parsing lives in `ZoomNotes` (`Services/ZoomAPI.swift`) and is unit-tested in `Tests/EZCalTests/ZoomTests.swift`.

### 3. Reminders (optional, for tasks in the grid)

Settings → Accounts → **Enable Reminders access** (or wait for the prompt the first time you quick-add a task). EZCal reads every list from Reminders.app the same way it reads Apple Calendar, via EventKit — no setup, no API keys. Toggle lists on/off from the sidebar's **Tasks** section, same as calendars.

Tasks with no due date aren't shown in the grid (there's nowhere to put them); give a task a due date in Reminders, or via quick-add, to see it. There's no dedicated task editor yet — quick-add and the checkbox cover creating and completing a task, anything else (notes, priority, moving lists) happens in Reminders.app.

## Install & releasing

Install: `brew install --cask kamden-rasmussen/tap/ezcal`. Update: `brew update && brew upgrade --cask ezcal`.

Release (needs the Developer ID cert, the `ezcal-notary` notarytool profile, `Secrets.swift`, and `gh` with push access to the tap):

1. Bump `CFBundleShortVersionString`/`CFBundleVersion` in `Resources/Info.plist` and commit.
2. `make release VERSION=x.y.z`. This builds, signs, notarizes and staples, uploads the zip to a `ezcal-vX.Y.Z` release on `homebrew-tap`, bumps `Casks/ezcal.rb`, and tags this repo `vX.Y.Z`. `PUBLISH=0` stops after the zip.

Notes: OAuth secrets are compiled into every binary, so rotate them if a build leaks. Homebrew only upgrades when the user runs it.

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

| Move or resize the focused event | |
|---|---|
| **⌥↑ / ⌥↓** | Move 15 minutes earlier / later |
| **⌥⇧↑ / ⌥⇧↓** | Resize (bottom edge) 15 minutes shorter / longer |

Editing or deleting a recurring event first asks **This event** / **This and following events** / **All events** — pick one with **↑ ↓** + **↩**, or jump straight to it with **1 / 2 / 3**.

| In the editor | |
|---|---|
| **⌘↩** | Save |
| **esc** | Cancel |
| **⌃1 / ⌃2 / ⌃3** | Zoom / Google Meet / none |
| **⌃A** | All-day |
| **⌘F** | Find a time everyone is free |

| In "Find a time" | |
|---|---|
| **↓ ↑** | Move between slots |
| **↩** | Use the selected slot |
| **esc** | Close |

| Tasks | |
|---|---|
| `task: <text>` in **⌘K** | Quick-add a task, e.g. `task: call dentist tomorrow 3pm` (the date/time is optional) |
| click | Toggle a task's checkbox to complete / reopen it |

Also: **P** add coworker, **⌘\** toggle sidebar, **⌘⇧W** hide weekends, **⌘R** refresh, **⌘,** settings, **⌘⇧N** new window. Every action is in the *Calendar* and *Event* menus too. Mouse/trackpad shortcuts: click the grid for a new event at that time, drag for a range, double-click a day header for day view, drag an event block to move it (snaps to 15 minutes, drag onto another day column in day/work week/week view to move it there) or drag its bottom edge to resize it (15-minute minimum); **esc** cancels a drag mid-gesture. A two-finger swipe left/right (or a horizontal scroll wheel) glides a day at a time — the further you pull, the more days it advances — rather than jumping a whole week or month, and works the same in every view. Read-only events and coworker overlays aren't draggable, and moving a recurring event only moves that occurrence.

## Multi-window

**⌘⇧N** (or File → New Window) opens another EZCal window. Each window gets its own `CalendarStore`, so the anchor date, view mode (day/week/month), keyboard focus and any open sheet are independent per window — handy for comparing two weeks side by side. Accounts, Google/Zoom credentials, calendar and Reminders-list selections are shared, because they're all persisted to the same `UserDefaults`/Keychain/EventKit store and each window reads them on launch; what *isn't* shared live is the in-memory event cache — each window fetches its own copy of events, so an edit made in one window shows up in the other after its next periodic refresh (or **⌘R**) rather than instantly. Sidebar show/hide state is technically per-window state too (each store has its own `hidden` set), but since it's persisted, a freshly opened window starts from whatever was last saved.

This trades a little memory/network duplication for a much smaller, more reviewable change than splitting `CalendarStore` into a shared-data object plus a separate per-window navigation object — that split is the natural next step if the duplicate fetches become a real problem.

Colors, spacing and type live in `Sources/EZCal/Core/Theme.swift`; the design source is the "EZCal Design" canvas. Light and dark mode follow the system.

## Working hours & a second time zone

Settings → **Hours & zones** sets your working days and hours (default Mon–Fri 9:00–17:00): hours outside that range are shaded in the day/week grid, and the grid opens scrolled to the start of your working day instead of the top of the clock.

The same tab picks an optional **secondary time zone** (e.g. "PT" or "CET"), shown as a second hour gutter next to the usual one; hovering an event also shows its time in that zone. Toggle it on/off quickly from **⌘K** → "Show/Hide time zone".

## Project layout

```
Sources/EZCal/
  EZCalApp.swift            app entry, window, menu commands, menu bar item
  Core/Models.swift         Source / CalEvent / EventDraft, meeting-link detection
  Core/Util.swift           colors, RFC3339, Keychain, AppSettings
  Core/WorkingHours.swift   working days/hours model + grid shading math
  Core/TimeZoneMath.swift   secondary time zone conversion, labels, DST-safe offsets
  Services/OAuth.swift      PKCE + loopback redirect, token refresh (Google & Zoom)
  Services/GoogleAPI.swift  Calendar, FreeBusy, People (directory) + event mapping
  Services/ZoomAPI.swift    create / update / delete Zoom meetings
  Services/EventKitService.swift  iCloud & system calendars, and Reminders/tasks, via EventKit
  Services/SlotFinder.swift pure "find a time" slot-search logic (no I/O)
  Services/NotificationPlanner.swift  pure "which events get which reminder" logic (unit tested)
  Services/NotificationService.swift  UNUserNotificationCenter: permission, scheduling, Join/Open actions
  Core/ICSParser.swift      pure-Swift iCalendar (.ics) parser + RRULE expansion
  Services/ICSService.swift .ics subscription fetch/cache (conditional GET, disk cache)
  Store/CalendarStore.swift all app state: fetching, overlay merge, save/delete/RSVP
  Store/TasksStore.swift    tasks data model + behavior (permission, fetch, quick-add, completion)
  Store/TaskQuickAdd.swift  pure "task: …" text parser used by the command palette
  Core/Theme.swift          design tokens, keycaps, button styles
  Core/EventDragMath.swift  snap/time math for dragging & resizing events
  Store/Commands.swift      keyboard focus navigation + command palette items
  Store/EventDrag.swift     drag-to-move/resize commit, rollback, keyboard nudge
  Views/                    TimeGridView, MonthView, Sidebar, editor, detail, palette, shortcuts, settings, FindTimeView, tasks
Tests/EZCalTests/           layout, parsing, mapping, OAuth loopback, .ics parser/fetch, slot-finder tests
scripts/                    build_app.sh, make_icon.swift
```

Handy places to tweak: overlay/event styling in `EventBlock` (`TimeGridView.swift`), the collision layout in `EventLayout`, the palette in `Palette` (`Util.swift`), what gets written into the event when Zoom is attached in `ZoomNotes` (`Services/ZoomAPI.swift`), and meeting options in `ZoomMeetingOptions` (same file).

## Known limitations / ideas

- "This and following events" (edit or delete) on Google splits the series by truncating the old RRULE and inserting a new one; this doesn't handle all-day recurring events' `UNTIL` correctly yet.
- Creating a recurring event only offers a few fixed patterns (daily, weekly, monthly, every weekday) — no custom RRULE builder.
- Deleting less than the whole series never detaches its Zoom meeting (only "All events" does).
- Moving an event to another calendar isn't supported in the editor.
- "Remove Zoom link" recognizes the block EZCal itself appends; on a Google event whose description is HTML (rare — only happens if it already contained a `<` before Zoom was added) it may remove more than just the Zoom lines. Plain-text notes (the common case, and always the case for Apple Calendar events) aren't affected.
- .ics subscriptions don't support per-occurrence overrides (RECURRENCE-ID) or `BYMONTHDAY`/`BYSETPOS` rules; uncommon in the sports/team/holiday feeds this targets.
- No dedicated task editor: quick-add and the checkbox cover creating and completing a task; edit notes, priority or its list in Reminders.app.
- A timed task marker doesn't participate in the event overlap layout (`EventLayout`), so a very busy hour can show it overlapping an event block.
- Multi-window shares accounts/calendars/Reminders lists (via UserDefaults/Keychain/EventKit) but not a live in-memory event cache — each window fetches its own copy of events (see "Multi-window" above).

## License

MIT
