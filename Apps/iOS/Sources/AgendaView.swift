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

    @State private var query = ""

    /// Loaded + upcoming events matching `query` in title, location, notes or guest names/emails.
    /// Searches what the store has loaded (the visible window plus the next 36h), not the whole calendar.
    private var results: [CalEvent] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        var seen = Set<String>()
        return (store.displayEvents + store.upcoming)
            .filter { !$0.isOverlay && !$0.isBusyOnly && seen.insert($0.id).inserted }
            .filter { e in
                e.title.lowercased().contains(q) || e.location.lowercased().contains(q)
                    || e.notes.lowercased().contains(q)
                    || e.attendees.contains { $0.display.lowercased().contains(q) || $0.email.lowercased().contains(q) }
            }
            .sorted { $0.start < $1.start }
    }

    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search events", text: $query)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.search)
                    .accessibilityIdentifier("agendaSearch")
                if searching {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .accessibilityLabel("Clear search").accessibilityIdentifier("agendaSearchClear")
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16).padding(.vertical, 6)
            if searching { searchResults } else { agenda }
        }
    }

    private var searchResults: some View {
        List {
            ForEach(results) { ev in
                HStack(spacing: 8) {
                    Button { store.sheet = .detail(ev) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ev.start.formatted(.dateTime.weekday(.abbreviated).month().day().year()))
                                .font(.caption).foregroundStyle(.secondary)
                            AgendaRow(event: ev)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("searchResult")
                }
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("searchResults")
        .overlay {
            if results.isEmpty { ContentUnavailableView.search(text: query) }
        }
    }

    private var agenda: some View {
        List {
            ForEach(days, id: \.day) { group in
                Section(group.day.formatted(.dateTime.weekday(.wide).month().day())) {
                    ForEach(group.events) { ev in
                        HStack(spacing: 8) {
                            Button { store.sheet = .detail(ev) } label: { AgendaRow(event: ev) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("agendaRow")
                            JoinIconButton(event: ev)
                        }
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
                HStack(spacing: 4) {
                    Text(event.title.isEmpty ? "(No title)" : event.title).font(.body)
                    if event.isPrivate && !event.isBusyOnly {
                        Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
                            .accessibilityLabel("Private")
                    }
                }
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
