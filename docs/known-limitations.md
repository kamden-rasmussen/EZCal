# Known limitations

- "This and following events" (edit or delete) on Google splits the series by truncating the old RRULE and inserting a new one; this doesn't handle all-day recurring events' `UNTIL` correctly yet.
- Creating a recurring event only offers a few fixed patterns (daily, weekly, monthly, every weekday) — no custom RRULE builder.
- Deleting less than the whole series never detaches its Zoom meeting (only "All events" does).
- Moving an event to another calendar isn't supported in the editor.
- Private events need EZCal's own Google sign-in. A Google calendar that only reaches EZCal through macOS Internet Accounts (as an Apple/EventKit calendar) has no Visibility control, because EventKit exposes no privacy field and EZCal can't reliably tell such calendars from iCloud ones. To mark those events private, also connect the same Google account in Settings → Accounts: the Google copy of each event is the one shown and edited. Tracked in #52.
- "Remove Zoom link" recognizes the block EZCal itself appends; on a Google event whose description is HTML (rare — only happens if it already contained a `<` before Zoom was added) it may remove more than just the Zoom lines. Plain-text notes (the common case, and always the case for Apple Calendar events) aren't affected.
- .ics subscriptions don't support per-occurrence overrides (RECURRENCE-ID) or `BYMONTHDAY`/`BYSETPOS` rules; uncommon in the sports/team/holiday feeds this targets.
- No dedicated task editor: quick-add and the checkbox cover creating and completing a task; edit notes, priority or its list in Reminders.app.
- A timed task marker doesn't participate in the event overlap layout (`EventLayout`), so a very busy hour can show it overlapping an event block.
- Multi-window shares accounts/calendars/Reminders lists (via UserDefaults/Keychain/EventKit) but not a live in-memory event cache — each window fetches its own copy of events (see [architecture notes](architecture.md)).
