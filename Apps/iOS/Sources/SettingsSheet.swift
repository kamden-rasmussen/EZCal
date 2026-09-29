import SwiftUI

struct SettingsSheet: View {
    @Environment(CalendarStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultDuration") private var duration = 60
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @AppStorage("notificationLeadMinutes") private var notificationLeadMinutes = 5
    @AppStorage("notificationVideoOnly") private var notificationVideoOnly = false
    @State private var permissionDeniedAlert = false

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
                Section("Meeting reminders") {
                    Toggle("Notify me before meetings", isOn: $notificationsEnabled)
                        .accessibilityIdentifier("notificationsToggle")
                        .onChange(of: notificationsEnabled) { _, _ in Task { await store.rescheduleNotifications() } }
                    Picker("Remind me", selection: $notificationLeadMinutes) {
                        Text("1 minute before").tag(1)
                        Text("5 minutes before").tag(5)
                        Text("10 minutes before").tag(10)
                        Text("15 minutes before").tag(15)
                    }
                    .disabled(!notificationsEnabled)
                    .onChange(of: notificationLeadMinutes) { _, _ in Task { await store.rescheduleNotifications() } }
                    Toggle("Only for events with a video link", isOn: $notificationVideoOnly)
                        .disabled(!notificationsEnabled)
                        .onChange(of: notificationVideoOnly) { _, _ in Task { await store.rescheduleNotifications() } }
                    Button("Send test notification") {
                        Task {
                            let ok = await store.sendTestNotification()
                            if !ok { permissionDeniedAlert = true }
                        }
                    }
                    Text("A notification appears a few minutes before each upcoming meeting, with a Join button when it has a video link.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("settingsDoneButton") } }
            .alert("Notifications permission denied", isPresented: $permissionDeniedAlert) {
                Button("OK", role: .cancel) {}
            } message: { Text("Enable EZCal in Settings → Notifications.") }
        }
        .presentationDetents([.medium, .large])
    }
}
