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
| `update_event` | partial update; `scope` (`this_event` / `this_and_following` / `all`) for recurring events |
| `delete_event` | delete with the same `scope`; reports what was deleted |
| `find_free_time` | free slots in your working hours, optionally checking other people's Google availability |

Notes: event ids from any tool work in every other tool. Without `calendar_id`, `create_event` uses your default writable calendar (the same one ⌘N uses). Times are ISO 8601; without an offset they are in your local zone. Subscriptions (`.ics`) and coworker overlays are read-only and refuse changes. Apple calendars can't take guests or private visibility through EZCal, so those fields are ignored with a warning. The change shows up in the app straight away. Reminders/tasks and moving an event between calendars aren't exposed yet. The server speaks plain-JSON Streamable HTTP; there is no stdio shim, so clients without HTTP support need `mcp-remote`.
