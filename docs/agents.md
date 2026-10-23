# Agent access (MCP)

EZCal can expose your calendars to AI agents (Claude Code, Claude Desktop, …) through a local [MCP](https://modelcontextprotocol.io) server, so "add the dentist appointment to my calendar" works whether the target is a Google or an iCloud calendar: EZCal routes it through the same save path the app itself uses (including Zoom/Meet links, recurrence and guests).

**Off by default.** Turn it on in Settings → **Agents**. It listens on `http://127.0.0.1:47900/mcp` (this Mac only; the port is changeable there), and every request needs the access token shown in that tab (kept in the Keychain; **Regenerate** disconnects every agent). EZCal has to be running. A **Read-only** switch lets agents look but not change anything.

Claude Code (use the **Copy setup command** button, or):

```
claude mcp add --transport http ezcal http://127.0.0.1:47900/mcp --header "Authorization: Bearer <token>"
```

Claude Desktop (via the `mcp-remote` bridge) in `claude_desktop_config.json`:

```json
{ "mcpServers": { "ezcal": { "command": "npx", "args": ["-y", "mcp-remote", "http://127.0.0.1:47900/mcp",
  "--header", "Authorization: Bearer <token>"] } } }
```

| Tool | What it does |
|---|---|
| `list_calendars` | ids, account, kind (google / eventkit / ics), writable, which one is the default |
| `list_events` | events in a window (max 62 days) with optional `query`, `calendar_ids`, paging; busy-only and private events show as "Busy" |
| `get_event` | full detail: notes, attendees + RSVP, video link, recurrence, `can_edit` |
| `create_event` | title, start/end (or all-day), calendar, location, notes, guests, `video` (zoom/meet), `recurrence`, `visibility`; reports overlapping events in `conflicts` |
| `update_event` | partial update; needs `current_title` + `current_start`; `calendar_id` moves it to another calendar; `scope` (`this_event` / `this_and_following` / `all`) for recurring events |
| `delete_event` | needs `current_title` + `current_start`; same `scope`; reports what was deleted |
| `list_reminder_lists`, `list_reminders` | Apple Reminders lists, and reminders soonest-due first (`due_before`, `query`, `list_ids`, `include_completed`) |
| `create_reminder`, `update_reminder`, `delete_reminder` | title, due date or date-time, list, notes, priority, `repeat`; `update_reminder` also marks done/not done and needs `current_title`, as does delete |
| `find_free_time` | free slots in your working hours, optionally checking other people's Google availability |

Notes: event ids from any tool work in every other tool. Without `calendar_id`, `create_event` uses your default writable calendar (the same one ⌘N uses). Times are ISO 8601; without an offset they are in your local zone. Subscriptions (`.ics`) and coworker overlays are read-only and refuse changes. Apple calendars can't take guests or private visibility through EZCal, so those fields are ignored with a warning. The change shows up in the app straight away. `update_event` and `delete_event` require the event's current title and start (copied from `list_events` / `get_event`) and refuse if they don't match the event behind `event_id`, so an approval prompt names the event and a stale id can't hit the wrong one. Tools carry titles and read-only / destructive hints so clients can auto-approve reads, and the server asks agents to show you the event and wait for a yes before changing anything. Moving an event with `calendar_id` follows the editor's rules: not for recurring events or events you don't organize, and moves between Google and Apple calendars copy the event (guests and Meet links don't carry over). Reminder tools need Reminders switched on in Settings → Accounts, respect the same Read-only switch, and use the same confirm-before-change rules; reminders you've hidden in the sidebar are skipped unless you pass their `list_ids`. The server speaks plain-JSON Streamable HTTP; there is no stdio shim, so clients without HTTP support need `mcp-remote`.
