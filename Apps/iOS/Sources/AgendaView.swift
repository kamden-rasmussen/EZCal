import SwiftUI

struct AgendaView: View {
    @Environment(CalendarStore.self) private var store

    /// Days from the anchor forward within the fetched window that have events.
    private var days: [(day: Date, events: [TimeGridItem])] {
        let start = store.cal.startOfDay(for: store.anchor)
        return (0..<14).compactMap { i -> (Date, [TimeGridItem])? in
            guard let d = store.cal.date(byAdding: .day, value: i, to: start) else { return nil }
            let r = store.events(on: d)
            // Same meeting on several calendars folds into one stacked item (shared with the grids).
            let all = EventGrouping.group(r.allDay + r.timed)
            return all.isEmpty ? nil : (d, all)
        }
    }

    @State private var query = ""
    @State private var stackSelection: StackSelection?
    @State private var pendingOpen: CalEvent?

    /// Tap behaviour matches the grid: a single opens its detail, a stack asks which calendar's copy.
    private func open(_ item: TimeGridItem) {
        switch item {
        case .single(let e): store.sheet = .detail(e)
        case .stack(let es): stackSelection = StackSelection(events: es)
        }
    }

    /// Loaded + upcoming events matching `query` in title, location, notes or guest names/emails.
    /// Searches what the store has loaded (the visible window plus the next 36h), not the whole calendar.
    private var results: [TimeGridItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        var seen = Set<String>()
        let hits = (store.displayEvents + store.upcoming)
            .filter { !$0.isOverlay && !$0.isBusyOnly && seen.insert($0.id).inserted }
            .filter { e in
                e.title.lowercased().contains(q) || e.location.lowercased().contains(q)
                    || e.notes.lowercased().contains(q)
                    || e.attendees.contains { $0.display.lowercased().contains(q) || $0.email.lowercased().contains(q) }
            }
            .sorted { $0.start < $1.start }
        return EventGrouping.group(hits)
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
        .sheet(item: $stackSelection, onDismiss: {
            // Open the picked copy only after the list has finished dismissing (one sheet at a time).
            if let e = pendingOpen { pendingOpen = nil; store.sheet = .detail(e) }
        }) { sel in
            StackCalendarSheet(selection: sel) { pendingOpen = $0 }
        }
    }

    private var searchResults: some View {
        List {
            ForEach(results) { item in
                HStack(spacing: 8) {
                    Button { open(item) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.start.formatted(.dateTime.weekday(.abbreviated).month().day().year()))
                                .font(.caption).foregroundStyle(.secondary)
                            AgendaRow(event: item.front, calendars: item.events)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("searchResult")
                }
            }
        }
        .listStyle(.insetGrouped)
        .groupedSurfaceBackground()
        .accessibilityIdentifier("searchResults")
        .overlay {
            if results.isEmpty { ContentUnavailableView.search(text: query) }
        }
    }

    private var agenda: some View {
        List {
            ForEach(days, id: \.day) { group in
                Section(group.day.formatted(.dateTime.weekday(.wide).month().day())) {
                    ForEach(group.events) { item in
                        HStack(spacing: 8) {
                            Button { open(item) } label: { AgendaRow(event: item.front, calendars: item.events) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("agendaRow")
                            JoinIconButton(event: item.events.first { $0.meetingURL != nil } ?? item.front)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .groupedSurfaceBackground()
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
    /// All copies when the meeting is stacked across calendars (2+); empty/one for an ordinary event.
    var calendars: [CalEvent] = []
    private var stacked: Bool { calendars.count > 1 }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if stacked {
                VStack(spacing: 3) {
                    ForEach(calendars.prefix(4)) { Circle().fill($0.color).frame(width: 10, height: 10) }
                }.padding(.top, 5)
            } else {
                Circle().fill(event.color).frame(width: 10, height: 10).padding(.top, 5)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(event.title.isEmpty ? "(No title)" : event.title).font(.body)
                    if event.isPrivate && !event.isBusyOnly {
                        Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
                            .accessibilityLabel("Private")
                    }
                }
                Text(timeText(event)).font(.subheadline).foregroundStyle(.secondary)
                if stacked {
                    Text("On \(calendars.count) calendars: " + calendars.map(\.sourceName).joined(separator: ", "))
                        .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                        .accessibilityIdentifier("agendaStackCalendars")
                }
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
