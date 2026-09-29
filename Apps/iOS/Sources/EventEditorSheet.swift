import SwiftUI

/// Touch-first editor for creating and editing events. All persistence goes through the shared
/// `CalendarStore.save(_:)` / `delete(_:scope:)`, so Google, EventKit and recurrence-scope logic is
/// the same as on macOS.
struct EventEditorSheet: View {
    @Environment(CalendarStore.self) private var store
    @State var draft: EventDraft
    @State private var saving = false
    @State private var error: String?
    @State private var confirmDelete = false
    @FocusState private var titleFocused: Bool

    init(draft: EventDraft) { _draft = State(initialValue: draft) }

    private var isNew: Bool { draft.existing == nil }
    private var writable: [Source] { store.calendars.filter(\.canWrite) }
    private var source: Source? { store.calendars.first { $0.id == draft.sourceId } }
    private var isEK: Bool { draft.existing?.isEventKit ?? (source?.isEventKit ?? false) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $draft.title)
                        .font(.title3.weight(.semibold))
                        .focused($titleFocused)
                        .accessibilityIdentifier("editorTitle")
                    if isNew {
                        Picker("Calendar", selection: $draft.sourceId) {
                            ForEach(writable) { s in
                                Label { Text(s.isEventKit ? "\(s.name) · \(s.groupTitle)" : s.name) }
                                    icon: { Image(systemName: "circle.fill").foregroundStyle(s.color) }
                                    .tag(s.id)
                            }
                        }
                        .accessibilityIdentifier("editorCalendar")
                    } else {
                        LabeledContent("Calendar") {
                            HStack { Circle().fill(source?.color ?? .secondary).frame(width: 10, height: 10)
                                Text(source?.name ?? draft.existing?.sourceName ?? "") }
                        }
                    }
                }

                Section {
                    Toggle("All-day", isOn: $draft.isAllDay).accessibilityIdentifier("editorAllDay")
                    DatePicker("Starts", selection: $draft.start,
                               displayedComponents: draft.isAllDay ? .date : [.date, .hourAndMinute])
                        .accessibilityIdentifier("editorStart")
                    DatePicker("Ends", selection: $draft.end, in: draft.start...,
                               displayedComponents: draft.isAllDay ? .date : [.date, .hourAndMinute])
                        .accessibilityIdentifier("editorEnd")
                    if isNew {
                        Picker("Repeat", selection: $draft.recurrence) {
                            ForEach(RecurrenceOption.allCases) { Text($0.label).tag($0) }
                        }
                        .accessibilityIdentifier("editorRepeat")
                    } else if draft.existing?.isRecurring == true {
                        LabeledContent("Applies to", value: draft.recurrenceScope.title)
                    }
                }

                Section {
                    TextField("Location", text: $draft.location).accessibilityIdentifier("editorLocation")
                    if isNew {
                        Picker("Video call", selection: $draft.video) {
                            Text("None").tag(EventDraft.Video.none)
                            if !isEK { Text("Google Meet").tag(EventDraft.Video.meet) }
                            if store.zoomConnected { Text("Zoom").tag(EventDraft.Video.zoom) }
                        }
                        .accessibilityIdentifier("editorVideo")
                    }
                    TextField("Notes", text: $draft.notes, axis: .vertical).lineLimit(3...8)
                        .accessibilityIdentifier("editorNotes")
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("editorError") }
                }

                if let e = draft.existing {
                    Section {
                        Button("Delete Event", role: .destructive) { confirmDelete = true }
                            .accessibilityIdentifier("editorDelete")
                            .confirmationDialog(e.isRecurring ? "Delete recurring event" : "Delete this event?",
                                                isPresented: $confirmDelete, titleVisibility: .visible) {
                                if e.isRecurring {
                                    ForEach(RecurrenceScope.allCases) { scope in
                                        Button("Delete \(scope.title.lowercased())", role: .destructive) { delete(e, scope) }
                                    }
                                } else {
                                    Button("Delete", role: .destructive) { delete(e, .thisEvent) }
                                }
                            } message: {
                                Text(e.isRecurring ? "“\(e.title)” repeats. Which events should be deleted?" : "This can’t be undone.")
                            }
                    }
                }
            }
            .navigationTitle(isNew ? "New Event" : "Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { store.sheet = nil }.accessibilityIdentifier("editorCancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() }
                    else { Button(isNew ? "Add" : "Save") { submit() }.fontWeight(.semibold).accessibilityIdentifier("editorSave") }
                }
            }
            .disabled(saving)
        }
        .onAppear { if isNew { titleFocused = true } }
        .onChange(of: draft.sourceId) { _, _ in
            if isEK && draft.video == .meet { draft.video = .none }
        }
        // Keep the duration when the start moves (same behaviour as the macOS editor).
        .onChange(of: draft.start) { old, new in
            draft.end = draft.end.addingTimeInterval(new.timeIntervalSince(old))
        }
        .presentationDetents([.large])
    }

    private func submit() {
        guard !saving else { return }
        saving = true; error = nil
        Task {
            do { try await store.save(draft) }   // closes the sheet on success
            catch {
                self.error = error.localizedDescription
                if case APIError.zoomReconnectNeeded = error { store.zoomConnected = false; store.zoomNeedsReconnect = true }
            }
            saving = false
        }
    }

    private func delete(_ e: CalEvent, _ scope: RecurrenceScope) {
        saving = true; error = nil
        Task {
            await store.delete(e, scope: scope)
            if store.sheet != nil, let m = store.errorMessage { error = m }
            saving = false
        }
    }
}
