import SwiftUI

/// "?" cheat sheet. Keep in sync with ContentView.handle, the menu bar and the editor.
struct ShortcutsView: View {
    @Environment(CalendarStore.self) private var store

    private struct Row: Identifiable { let id = UUID(); let label: String; let keys: [String] }
    private struct Section: Identifiable { let id = UUID(); let title: String; let rows: [Row] }

    private let sections: [Section] = [
        Section(title: "Move around", rows: [
            Row(label: "Today", keys: ["T"]),
            Row(label: "Previous / next period", keys: ["[", "]"]),
            Row(label: "Go to date…", keys: ["G"]),
            Row(label: "Switch view", keys: ["D", "5", "W", "M"]),
            Row(label: "Search anything", keys: ["/"]),
        ]),
        Section(title: "Events", rows: [
            Row(label: "New event", keys: ["N"]),
            Row(label: "Next / previous event", keys: ["↓", "↑"]),
            Row(label: "Same time, next / prev day", keys: ["→", "←"]),
            Row(label: "Open event", keys: ["↩"]),
            Row(label: "Join video call", keys: ["J"]),
        ]),
        Section(title: "On an open event", rows: [
            Row(label: "Edit", keys: ["E"]),
            Row(label: "Add Zoom meeting", keys: ["Z"]),
            Row(label: "RSVP yes / maybe / no", keys: ["Y", "M", "N"]),
            Row(label: "Delete", keys: ["⌫"]),
            Row(label: "Close", keys: ["esc"]),
        ]),
        Section(title: "In the editor", rows: [
            Row(label: "Save", keys: ["⌘", "↩"]),
            Row(label: "Cancel", keys: ["esc"]),
            Row(label: "Next field", keys: ["tab"]),
            Row(label: "Zoom / Meet / none", keys: ["⌃1", "⌃2", "⌃3"]),
            Row(label: "All-day", keys: ["⌃A"]),
        ]),
        Section(title: "Coworkers & calendars", rows: [
            Row(label: "Add coworker", keys: ["P"]),
            Row(label: "Add calendar by URL", keys: ["⌘K"]),
            Row(label: "Show or hide a coworker", keys: ["⌘K"]),
            Row(label: "Toggle sidebar", keys: ["⌘", "\\"]),
            Row(label: "Hide weekends", keys: ["⌘", "⇧", "W"]),
            Row(label: "Refresh", keys: ["⌘", "R"]),
        ]),
        Section(title: "App", rows: [
            Row(label: "Command palette", keys: ["⌘", "K"]),
            Row(label: "This cheat sheet", keys: ["?"]),
            Row(label: "Settings", keys: ["⌘", ","]),
            Row(label: "New event (anywhere)", keys: ["⌘", "N"]),
            Row(label: "Join next meeting", keys: ["J"]),
        ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Keyboard shortcuts").font(.system(size: 20, weight: .semibold))
                Text("Everything works without a mouse. Press ⌘K to search all commands.").foregroundStyle(Theme.text2)
                Spacer()
                Button("Done") { store.sheet = nil }.buttonStyle(SecondaryButtonStyle()).keyboardShortcut(.cancelAction)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 32, alignment: .top), count: 3), alignment: .leading, spacing: 22) {
                ForEach(sections) { s in
                    VStack(alignment: .leading, spacing: 2) {
                        SectionLabel(s.title).padding(.bottom, 6)
                        ForEach(s.rows) { r in
                            HStack(spacing: 8) {
                                Text(r.label)
                                Spacer(minLength: 4)
                                HStack(spacing: 4) { ForEach(r.keys, id: \.self) { KeyCap($0) } }
                            }
                            .frame(height: 28)
                            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line2).frame(height: 1) }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 30).padding(.vertical, 26)
        .frame(width: 920)
        .background(Theme.surface)
    }
}
