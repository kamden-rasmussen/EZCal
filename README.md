# EZCal

A free, open-source, native calendar for macOS, built for speed and the keyboard. It shows Google Calendar, iCloud / Apple Calendar and subscribed `.ics` feeds side by side, and it's inspired by Notion Calendar.

Pure SwiftUI with no third-party dependencies. There is no EZCal server: your sign-in tokens live in your Mac's Keychain and requests go straight from your Mac to Google and Zoom. See the [privacy policy](PRIVACY.md).

## Install

```bash
brew install --cask kamden-rasmussen/tap/ezcal
```

Update with `brew update && brew upgrade --cask ezcal`. EZCal also checks for new releases on launch and shows an **Update available** pill.

Requires macOS 14 or later.

## Features

- **Google Calendar**: multiple accounts, day / work week / week / month views, create, edit, delete and RSVP.
- **iCloud & Apple Calendar**: every calendar macOS already syncs (iCloud, Exchange, Fastmail, CalDAV) appears alongside Google with no passwords or API keys. Events on both are de-duplicated.
- **Calendar subscriptions**: paste a `webcal://` or `https://` link (a sports schedule, a shared team calendar, a holiday list) and it shows up read-only in the sidebar.
- **Zoom in one click**: add a real Zoom meeting to any event, with your own defaults (waiting room, mute on entry, passcode and more). It's updated when you move the event and deleted when you delete the event or remove the link. Google Meet works too.
- **Coworker overlay**: search your Google Workspace directory and see a colleague's calendar in your grid (full details if shared, free/busy blocks if not).
- **Find a time**: lists the best slots where every attendee you can see is free.
- **Join buttons and reminders**: one-click join for Zoom, Meet and Teams links, a menu bar item showing your next meeting, and optional notifications before each meeting.
- **Private events**: Default / Public / Private visibility on Google events. Private events show only as "Busy" to anyone viewing your calendar.
- **Tasks**: due-dated Apple Reminders appear in the grid, with a checkbox and quick-add (`task: call dentist tomorrow 3pm`). Enable under Settings → Accounts → Reminders.
- **Working hours and a second time zone**: shade time outside your working hours and show a second hour gutter.
- **Keyboard first**: press **⌘K** for a command palette, or **?** for the shortcut cheat sheet. See [all shortcuts](docs/keyboard-shortcuts.md).
- **Agent access (MCP)**: optionally let AI agents such as Claude Code or Claude Desktop read and manage your calendars through a local server. It's off by default. See [agent access](docs/agents.md).
- **Multi-window**: ⌘⇧N opens another window with its own date and view.

## Build from source

Requires macOS 14+ and Xcode / Swift 5.9+.

```bash
scripts/build_app.sh --run        # builds build/EZCal.app and opens it
scripts/build_app.sh --install    # also copies it to /Applications
swift test                        # unit tests
open Package.swift                # or edit and debug in Xcode
```

If you have an Apple Development certificate, the script signs with it automatically, which stops Keychain from re-asking for permission after every rebuild. Otherwise it signs ad-hoc, and you'll see a Keychain prompt per rebuild (click **Always Allow**).

Apple Calendar, Reminders and `.ics` subscriptions work out of the box. Google and Zoom sign-in need OAuth clients that are compiled into the app. To use them in your own build, create your own and copy `Sources/EZCal/Core/Secrets.swift.example` to `Sources/EZCal/Core/Secrets.swift` (gitignored). The steps are in [docs/oauth-setup.md](docs/oauth-setup.md).

An iOS companion app lives in [`Apps/iOS`](Apps/iOS/README.md).

## Documentation

- [Keyboard shortcuts](docs/keyboard-shortcuts.md)
- [Agent access (MCP)](docs/agents.md)
- [Setting up your own OAuth clients](docs/oauth-setup.md)
- [Architecture notes](docs/architecture.md)
- [Known limitations](docs/known-limitations.md)
- [Releasing](docs/releasing.md)

## Contributing

Issues and pull requests are welcome. Run `swift test` before opening a PR. If you're planning something larger, open an issue first so we can talk it through.

## Privacy

EZCal collects no data and has no analytics. Read the full [privacy policy](PRIVACY.md) and [terms of use](TERMS.md).

## License

[MIT](LICENSE)
