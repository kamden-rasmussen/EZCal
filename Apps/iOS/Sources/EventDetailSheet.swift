import SwiftUI

struct EventDetailSheet: View {
    let event: CalEvent
    @Environment(CalendarStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var askScope = false
    @State private var confirmDelete = false
    // Glass at half height, fading to an opaque sheet at the tall detent. A full-height (.large) sheet makes iOS
    // swap to opaque in one frame, so the tall detent stays just short of full and the fade is ours.
    private static let tall = PresentationDetent.fraction(0.94)
    @State private var detent: PresentationDetent = .medium
    private var opaque: Double { detent == Self.tall ? 1 : 0 }

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
                if !guests.isEmpty { attendeesSection }
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
            .scrollContentBackground(.hidden)
            .listRowBackground(Color(.secondarySystemGroupedBackground).opacity(0.35 + 0.65 * opaque))
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
        .background { Color(.systemGroupedBackground).opacity(opaque).ignoresSafeArea() }
        .animation(.easeInOut(duration: 0.35), value: detent)
        .presentationDetents([.medium, Self.tall], selection: $detent)
    }

    private var guests: [Attendee] { event.attendees.filter { !$0.isResource } }

    /// EventKit participants are read-only, so for those this only displays. Google RSVP goes through the
    /// shared `store.rsvp`, but that needs a signed-in Google account, and iOS has no Google sign-in UI
    /// yet (#37), so the buttons only appear for a non-EventKit event once an account exists.
    private var canRSVP: Bool {
        event.selfAttendee != nil && !event.isOverlay && !event.isEventKit && !event.isICS && !store.accounts.isEmpty
    }

    private var attendeesSection: some View {
        Section("\(guests.count) \(guests.count == 1 ? "guest" : "guests")") {
            ForEach(guests, id: \.email) { a in
                HStack(spacing: 8) {
                    Image(systemName: Self.icon(a.response)).foregroundStyle(Self.tint(a.response))
                    Text(a.display + (a.isSelf ? " (you)" : ""))
                    if a.isOrganizer { Text("organizer").font(.caption).foregroundStyle(.secondary) }
                    if a.isOptional { Text("optional").font(.caption).foregroundStyle(.secondary) }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(a.display), \(Self.statusText(a.response))")
                .accessibilityIdentifier("attendeeRow")
            }
            if canRSVP {
                HStack {
                    Text("Going?")
                    Spacer()
                    ForEach([("Yes", "accepted"), ("Maybe", "tentative"), ("No", "declined")], id: \.1) { label, value in
                        Button(label) { Task { await store.rsvp(event, value) } }
                            .buttonStyle(.bordered)
                            .tint(event.selfAttendee?.response == value ? .accentColor : .gray)
                    }
                }
                .accessibilityIdentifier("rsvpRow")
            }
        }
    }

    static func icon(_ r: String) -> String {
        switch r {
        case "accepted": return "checkmark.circle.fill"
        case "declined": return "xmark.circle.fill"
        case "tentative": return "questionmark.circle.fill"
        default: return "circle.dashed"
        }
    }
    static func tint(_ r: String) -> Color {
        switch r {
        case "accepted": return .green
        case "declined": return .red
        case "tentative": return .orange
        default: return .secondary
        }
    }
    static func statusText(_ r: String) -> String {
        switch r {
        case "accepted": return "accepted"
        case "declined": return "declined"
        case "tentative": return "maybe"
        default: return "no response"
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
