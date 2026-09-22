import SwiftUI

/// Icon plus the next meeting's countdown. Deliberately a plain view: see CalendarStore.menuBarText.
struct MenuBarLabel: View {
    @Environment(CalendarStore.self) private var store

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "calendar")
            if !store.menuBarText.isEmpty { Text(store.menuBarText) }
        }
    }
}

struct MenuBarView: View {
    @Environment(CalendarStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let now = Date()
        let items = Array(store.upcoming.filter { $0.end > now }.prefix(5))

        if items.isEmpty {
            Text("Nothing coming up")
        }
        ForEach(items) { e in
            if let url = e.meetingURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Text("\(e.start.formatted(date: .omitted, time: .shortened))  \(e.title)  —  Join")
                }
            } else {
                Text("\(e.start.formatted(date: .omitted, time: .shortened))  \(e.title)")
            }
        }
        Divider()
        Button("Open EZCal") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Refresh") { Task { await store.refreshAll() } }
        Divider()
        Button("Quit EZCal") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
