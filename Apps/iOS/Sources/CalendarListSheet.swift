import SwiftUI

/// Touch equivalent of the macOS sidebar: per-calendar visibility, grouped by account.
/// Uses the store's own `hidden` state, so it persists and filters Agenda/Day.
struct CalendarListSheet: View {
    @Environment(CalendarStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var groups: [(title: String, items: [Source])] {
        var order: [String] = []
        var by: [String: [Source]] = [:]
        for s in store.ordered(store.calendars) {
            let t = s.isICS ? "Subscriptions" : s.groupTitle
            if by[t] == nil { order.append(t) }
            by[t, default: []].append(s)
        }
        return order.map { ($0, by[$0]!) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups, id: \.title) { g in
                    Section(g.title) {
                        ForEach(g.items) { s in
                            Toggle(isOn: Binding(get: { store.isVisible(s) }, set: { _ in store.toggle(s) })) {
                                HStack(spacing: 10) {
                                    Circle().fill(s.color).frame(width: 12, height: 12)
                                    Text(s.name)
                                }
                            }
                            .accessibilityIdentifier("calendarToggle-\(s.name)")
                        }
                    }
                }
            }
            .overlay { if store.calendars.isEmpty { ContentUnavailableView("No calendars", systemImage: "calendar") } }
            .navigationTitle("Calendars")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("calendarsDoneButton") } }
        }
        .presentationDetents([.medium, .large])
    }
}
