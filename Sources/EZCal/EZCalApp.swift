import SwiftUI

/// `EZCal --mcp-stdio` serves MCP over stdin/stdout for Claude Desktop (issue #86) and must exit before SwiftUI
/// starts, so it never shows a Dock icon or window; anything else launches the app.
@main
enum EZCalMain {
    static func main() {
        if MCPStdioBridge.isRequested() { MCPStdioBridge.run() }
        EZCalApp.main()
    }
}

struct EZCalApp: App {
    @State private var store: CalendarStore
    @State private var updates = UpdateChecker()

    init() {
        let s = CalendarStore()
        _store = State(initialValue: s)
        DebugSnapshot.scheduleIfRequested(store: s)
        #if os(macOS)
        MCPServer.shared.attach(s)   // local agent (MCP) server, if enabled in Settings → Agents
        #endif
    }

    var body: some Scene {
        Window("EZCal", id: "main") {
            ContentView()
                .environment(store)
                .environment(updates)
                .frame(minWidth: 980, minHeight: 640)
                .task { updates.start() }   // launch check, then every ~6h; start() is idempotent
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Event") { store.newDraft() }.keyboardShortcut("n")
                NewWindowButton()
            }

            CommandMenu("Calendar") {
                Button("Command Palette…") { store.openPalette() }.keyboardShortcut("k")
                Divider()
                Button("Today") { store.goToday() }.keyboardShortcut("t")
                Button("Previous") { store.step(-1) }.keyboardShortcut("[")
                Button("Next") { store.step(1) }.keyboardShortcut("]")
                Button("Go to Date…") { store.openPalette("go to ") }.keyboardShortcut("g")
                Divider()
                Button("Day") { store.setMode(.day) }.keyboardShortcut("1")
                Button("Work Week (Mon–Fri)") { store.setMode(.workWeek) }.keyboardShortcut("2")
                Button("Week") { store.setMode(.week) }.keyboardShortcut("3")
                Button("Month") { store.setMode(.month) }.keyboardShortcut("4")
                Button("Show / Hide Weekends") { store.toggleWeekends() }.keyboardShortcut("w", modifiers: [.command, .shift])
                Button("Show / Hide Sidebar") { store.toggleSidebar() }.keyboardShortcut("\\")
                Divider()
                Button("Add Coworker…") { store.requestAddPerson() }.keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Add Calendar by URL…") { store.openAddSubscription() }
                Button("Refresh") { Task { await store.refreshAll() } }.keyboardShortcut("r")
            }

            CommandMenu("Event") {
                Button("Join Video Call") { store.joinMeeting() }.keyboardShortcut("j")
                Button("Open") { store.openFocused() }.keyboardShortcut("o")
                Button("Edit…") { store.editFocused() }.keyboardShortcut("e")
                Button("Delete…") { store.deleteFocused() }.keyboardShortcut(.delete)
                Divider()
                Button("Next Event") { store.moveFocus(1) }.keyboardShortcut(.downArrow, modifiers: [.command, .option])
                Button("Previous Event") { store.moveFocus(-1) }.keyboardShortcut(.upArrow, modifiers: [.command, .option])
            }

            CommandGroup(replacing: .appInfo) {
                Button("About EZCal") { AboutPanel.show() }
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton()
            }

            CommandGroup(replacing: .help) {
                Button("Keyboard Shortcuts") { store.openShortcuts() }.keyboardShortcut("/")
            }
        }

        // ⌘⇧N: a second, independent window (e.g. to compare two weeks side by side). It gets its own
        // `CalendarStore`, so navigation state (anchor/mode/focus/sheet) is isolated per window; accounts,
        // calendars and Reminders lists are shared because they're read from the same UserDefaults/Keychain/
        // EventKit store, but each window fetches and caches its own copy of events rather than sharing one
        // in-memory cache. See docs/architecture.md "Multi-window" for the tradeoffs of this approach.
        WindowGroup("EZCal", id: "secondary") {
            ContentView()
                .environment(CalendarStore())
                .environment(updates)
                .frame(minWidth: 980, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)

        // Opened by "Check for Updates…" and the toolbar's "Update available" pill.
        Window("Check for Updates", id: "update") {
            UpdateView().environment(updates)
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarView().environment(store)
        } label: {
            MenuBarLabel().environment(store)
        }

        Settings {
            SettingsView().environment(store)
        }
    }
}

private struct CheckForUpdatesButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Check for Updates…") { openWindow(id: "update") }
    }
}

/// Small wrapper so `.commands { }` (which builds a plain `View`) can reach `openWindow`.
private struct NewWindowButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("New Window") { openWindow(id: "secondary") }
            .keyboardShortcut("n", modifiers: [.command, .shift])
    }
}
