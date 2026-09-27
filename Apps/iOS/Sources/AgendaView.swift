import SwiftUI

struct AgendaView: View {
    @Environment(CalendarStore.self) private var store

    /// Days from the anchor forward within the fetched window that have events.
    private var days: [(day: Date, events: [CalEvent])] {
        let start = store.cal.startOfDay(for: store.anchor)
        return (0..<14).compactMap { i -> (Date, [CalEvent])? in
            guard let d = store.cal.date(byAdding: .day, value: i, to: start) else { return nil }
            let r = store.events(on: d)
            let all = r.allDay + r.timed
            return all.isEmpty ? nil : (d, all)
        }
    }

    var body: some View {
        List {
            ForEach(days, id: \.day) { group in
                Section(group.day.formatted(.dateTime.weekday(.wide).month().day())) {
                    ForEach(group.events) { ev in
                        Button { store.sheet = .detail(ev) } label: { AgendaRow(event: ev) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("agendaRow")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("agendaList")
        .refreshable { await store.refreshAll() }
        .overlay {
            if days.isEmpty {
                ContentUnavailableView(store.isLoading ? "Loading..." : "No events",
                                       systemImage: "calendar",
                                       description: Text(store.errorMessage ?? "Nothing scheduled."))
            }
        }
    }
}

struct AgendaRow: View {
    let event: CalEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(event.color).frame(width: 10, height: 10).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title.isEmpty ? "(No title)" : event.title).font(.body)
                Text(timeText(event)).font(.subheadline).foregroundStyle(.secondary)
                if !event.location.isEmpty {
                    Text(event.location).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

func timeText(_ e: CalEvent) -> String {
    if e.isAllDay { return "All day" }
    return "\(e.start.formatted(date: .omitted, time: .shortened)) – \(e.end.formatted(date: .omitted, time: .shortened))"
}
