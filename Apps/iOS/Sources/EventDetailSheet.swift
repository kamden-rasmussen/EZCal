import SwiftUI

struct EventDetailSheet: View {
    let event: CalEvent
    @Environment(CalendarStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var askScope = false
    @State private var confirmDelete = false

    private var duplicateTargets: [Source] { store.calendars.filter(\.canWrite) }
    private var canDelete: Bool { event.canEdit && !event.isBusyOnly && !event.isICS && !event.isOverlay }
    private var canDuplicate: Bool { !event.isBusyOnly && !event.isOverlay && !duplicateTargets.isEmpty }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(event.title.isEmpty ? "(No title)" : event.title).font(.title3.bold())
                        .accessibilityIdentifier("detailTitle")
                    LabeledContent("When", value: whenText)
                    if event.isPrivate && !event.isBusyOnly {
                        Label("Private — others see this only as Busy", systemImage: "lock.fill")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Calendar")
                        Spacer()
                        Circle().fill(event.color).frame(width: 10, height: 10)
                        Text(event.sourceName).foregroundStyle(.secondary)
                    }
                    if !event.location.isEmpty {
                        Button {
                            if let url = Self.mapsURL(event.location) { Platform.open(url) }
                        } label: {
                            HStack {
                                Text("Location").foregroundStyle(.primary)
                                Spacer()
                                Text(event.location).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                                Image(systemName: "map").foregroundStyle(.tint)
                            }
                        }
                        .accessibilityIdentifier("locationButton")
                        .accessibilityHint("Opens in Maps")
                    }
                }
                if let url = event.meetingURL {
                    Section {
                        Button {
                            Platform.open(url)
                        } label: {
                            Label("Join \(event.meetingProvider?.name ?? "meeting")", systemImage: "video.fill")
                        }
                    }
                }
                if !event.notes.isEmpty {
                    Section("Notes") { Text(event.notes) }
                }
                if canDuplicate || canDelete {
                    Section {
                        if canDuplicate {
                            Menu {
                                ForEach(duplicateTargets) { s in
                                    Button { store.duplicateDraft(event, to: s) } label: {
                                        Text(s.name + (store.calendars.filter { $0.name == s.name }.count > 1 ? " (\(s.groupTitle))" : ""))
                                    }
                                }
                            } label: { Label("Duplicate to calendar", systemImage: "plus.square.on.square") }
                                .accessibilityIdentifier("duplicateButton")
                        }
                        if canDelete {
                            Button(role: .destructive) { confirmDelete = true } label: {
                                Label("Delete Event", systemImage: "trash")
                            }
                            .accessibilityIdentifier("detailDelete")
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("doneButton") }
                if event.canEdit && !event.isBusyOnly && !event.isICS {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Edit") { if event.isRecurring { askScope = true } else { store.editDraft(event) } }
                            .accessibilityIdentifier("editButton")
                    }
                }
            }
            .confirmationDialog(event.isRecurring ? "Delete recurring event" : "Delete this event?",
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                if event.isRecurring {
                    ForEach(RecurrenceScope.allCases) { scope in
                        Button("Delete \(scope.title.lowercased())", role: .destructive) { delete(scope) }
                    }
                } else {
                    Button("Delete", role: .destructive) { delete(.thisEvent) }
                }
            } message: {
                Text(event.isRecurring ? "“\(event.title)” repeats. Which events should be deleted?" : "This can’t be undone.")
            }
            .confirmationDialog("Edit recurring event", isPresented: $askScope, titleVisibility: .visible) {
                ForEach(RecurrenceScope.allCases) { scope in
                    Button(scope.title) { store.chooseRecurrenceScope(scope, for: event, action: .edit) }
                }
            } message: { Text("“\(event.title)” repeats. Which events should the edit affect?") }
        }
    }

    /// Apple Maps search for the location text (also resolves street addresses). A location that is
    /// itself a web link (e.g. a meeting URL) opens as-is.
    static func mapsURL(_ location: String) -> URL? {
        let t = location.trimmingCharacters(in: .whitespacesAndNewlines)
        if let u = URL(string: t), let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https" { return u }
        var c = URLComponents(string: "https://maps.apple.com/")
        c?.queryItems = [URLQueryItem(name: "q", value: t)]
        return c?.url
    }

    /// The store closes the sheet itself on success.
    private func delete(_ scope: RecurrenceScope) {
        Task { await store.delete(event, scope: scope) }
    }

    private var whenText: String {
        let day = event.start.formatted(.dateTime.weekday().month().day())
        return event.isAllDay ? "\(day), all day" : "\(day), \(timeText(event))"
    }
}
