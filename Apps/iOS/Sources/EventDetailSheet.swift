import SwiftUI

struct EventDetailSheet: View {
    let event: CalEvent
    @Environment(CalendarStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var askScope = false

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
                    if !event.location.isEmpty { LabeledContent("Location", value: event.location) }
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
            .confirmationDialog("Edit recurring event", isPresented: $askScope, titleVisibility: .visible) {
                ForEach(RecurrenceScope.allCases) { scope in
                    Button(scope.title) { store.chooseRecurrenceScope(scope, for: event, action: .edit) }
                }
            } message: { Text("“\(event.title)” repeats. Which events should the edit affect?") }
        }
    }

    private var whenText: String {
        let day = event.start.formatted(.dateTime.weekday().month().day())
        return event.isAllDay ? "\(day), all day" : "\(day), \(timeText(event))"
    }
}
