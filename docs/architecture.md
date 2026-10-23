# Architecture notes

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
  Core/MCPProtocol.swift    MCP JSON-RPC dispatcher + tiny HTTP framing (pure, unit tested)
  Services/MCPServer.swift  loopback listener, token auth, Settings → Agents switch
  Store/MCPTools.swift      the calendar tools agents call (list/get/create/update/delete/find time)
  Store/MCPReminderTools.swift  the Apple Reminders tools (list/create/update/delete)
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

## How EZCal remembers an Apple Calendar event's Zoom meeting

EventKit (iCloud/Apple Calendar) has no field for arbitrary app metadata, so there's nowhere obvious to store "this event's Zoom meeting is #123". EZCal keeps the id in a single hidden line appended to the event's notes — two zero-width spaces bracketing `EZCAL-ZOOM:<id>` — which `EventKitService` strips out before showing notes anywhere in the app or re-adds when saving. This was chosen over a local id-to-event map (keyed by EventKit's `eventIdentifier`) because the marker travels with the event itself: it survives EZCal being reinstalled, another device editing the same iCloud event, and EventKit occasionally reassigning identifiers, all of which would silently orphan a local map. The formatting/parsing lives in `ZoomNotes` (`Services/ZoomAPI.swift`) and is unit-tested in `Tests/EZCalTests/ZoomTests.swift`.

## Multi-window

**⌘⇧N** (or File → New Window) opens another EZCal window. Each window gets its own `CalendarStore`, so the anchor date, view mode (day/week/month), keyboard focus and any open sheet are independent per window — handy for comparing two weeks side by side. Accounts, Google/Zoom credentials, calendar and Reminders-list selections are shared, because they're all persisted to the same `UserDefaults`/Keychain/EventKit store and each window reads them on launch; what *isn't* shared live is the in-memory event cache — each window fetches its own copy of events, so an edit made in one window shows up in the other after its next periodic refresh (or **⌘R**) rather than instantly. Sidebar show/hide state is technically per-window state too (each store has its own `hidden` set), but since it's persisted, a freshly opened window starts from whatever was last saved.

This trades a little memory/network duplication for a much smaller, more reviewable change than splitting `CalendarStore` into a shared-data object plus a separate per-window navigation object — that split is the natural next step if the duplicate fetches become a real problem.

Colors, spacing and type live in `Sources/EZCal/Core/Theme.swift`; the design source is the "EZCal Design" canvas. Light and dark mode follow the system.

## Coworker overlay

Add people with the **+** next to *Coworkers* in the sidebar. For each person EZCal tries, in order:

1. **Full events**: works if they've shared their calendar with you (or your org shares calendars org-wide).
2. **Free/busy blocks**: if only availability is shared, you'll see dashed "Alice · Busy" blocks and an eye-slash icon in the sidebar.
3. Otherwise the person gets a warning icon: they haven't shared anything.

If a coworker marks an event private, Google hides its details from you and EZCal draws it as a plain "Busy" block (no title, location, guests or link, and it isn't clickable for details), the same as the free/busy fallback.

Each person gets their own color. The same meeting on several calendars is shown once. Coworker events are drawn lighter with an outline and prefixed with their name.
