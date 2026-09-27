import SwiftUI

struct EventDetailSheet: View {
    let event: CalEvent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(event.title.isEmpty ? "(No title)" : event.title).font(.title3.bold())
                    LabeledContent("When", value: whenText)
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
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var whenText: String {
        let day = event.start.formatted(.dateTime.weekday().month().day())
        return event.isAllDay ? "\(day), all day" : "\(day), \(timeText(event))"
    }
}
