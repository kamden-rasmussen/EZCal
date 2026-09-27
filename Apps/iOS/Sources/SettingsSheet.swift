import SwiftUI

struct SettingsSheet: View {
    @Environment(CalendarStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultDuration") private var duration = 60

    var body: some View {
        NavigationStack {
            Form {
                Section("Accounts") {
                    LabeledContent("Device calendars (iCloud etc.)", value: store.eventKitEnabled ? "Connected" : "Not connected")
                        .accessibilityIdentifier("settingsDevice")
                    LabeledContent("Google Calendar", value: "Not set up on iOS yet")
                    LabeledContent("Zoom", value: "Not set up on iOS yet")
                }
                Section("New events") {
                    Picker("Default length", selection: $duration) {
                        ForEach([15, 30, 45, 60, 90, 120], id: \.self) { Text("\($0) min").tag($0) }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("settingsDoneButton") } }
        }
        .presentationDetents([.medium, .large])
    }
}
