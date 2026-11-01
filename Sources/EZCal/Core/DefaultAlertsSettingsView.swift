import SwiftUI

/// Settings rows for the default alerts applied to new events (issue #131). Shared by the macOS
/// SettingsView and the iOS SettingsSheet; drop it inside a `Form`/`Section`.
struct DefaultAlertsSettingsRows: View {
    @State private var first: Int
    @State private var second: Int

    init() {
        let c = DefaultAlertChoice.choices(from: AppSettings.defaultAlerts)
        _first = State(initialValue: c.first)
        _second = State(initialValue: c.second)
    }

    var body: some View {
        Picker("First alert", selection: $first) {
            Text("Calendar default").tag(DefaultAlertChoice.unset)
            Text("None").tag(DefaultAlertChoice.none)
            ForEach(EventAlert.presets, id: \.self) { Text(EventAlert.label($0)).tag($0) }
        }
        .accessibilityIdentifier("defaultAlertFirst")
        Picker("Second alert", selection: $second) {
            Text("None").tag(DefaultAlertChoice.none)
            ForEach(EventAlert.presets, id: \.self) { Text(EventAlert.label($0)).tag($0) }
        }
        .disabled(first < 0)
        .accessibilityIdentifier("defaultAlertSecond")
        .onChange(of: first) { _, _ in save() }
        .onChange(of: second) { _, _ in save() }
    }

    private func save() {
        AppSettings.defaultAlerts = DefaultAlertChoice.alerts(first: first, second: second)
    }
}
