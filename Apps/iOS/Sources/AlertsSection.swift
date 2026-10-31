import SwiftUI

/// Alerts rows for the event editor (issue #131): one menu per alert, a minus to remove, and "Add Alert".
struct AlertsSection: View {
    @Binding var alerts: [Int]?
    /// Google events whose alerts are "calendar default" show that until the user edits them.
    var usesDefaultLabel: Bool { alerts == nil }

    private var list: [Int] { alerts ?? [] }

    var body: some View {
        Section("Alerts") {
            if alerts == nil {
                Text("Calendar default").foregroundStyle(.secondary).accessibilityIdentifier("editorAlertsDefault")
            }
            ForEach(Array(list.enumerated()), id: \.offset) { idx, minutes in
                HStack {
                    Button {
                        var l = list; l.remove(at: idx); alerts = l
                    } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.red) }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove alert").accessibilityIdentifier("editorAlertRemove-\(idx)")
                    Menu {
                        ForEach(options(including: minutes), id: \.self) { m in
                            Button(EventAlert.label(m)) { var l = list; l[idx] = m; alerts = EventAlert.normalized(l) }
                        }
                    } label: {
                        HStack { Text(EventAlert.label(minutes)); Spacer(); Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary) }
                    }
                    .accessibilityIdentifier("editorAlert-\(idx)")
                }
            }
            if list.count < EventAlert.maxCount {
                Button {
                    let next = ([10, 0, 5, 15, 30, 60, 1440] + EventAlert.presets).first { !list.contains($0) } ?? 10
                    alerts = EventAlert.normalized(list + [next])
                } label: { Label("Add Alert", systemImage: "plus.circle.fill") }
                .accessibilityIdentifier("editorAddAlert")
            }
        }
    }

    private func options(including current: Int) -> [Int] {
        EventAlert.presets.contains(current) ? EventAlert.presets : (EventAlert.presets + [current]).sorted()
    }
}

/// Settings rows for the default alerts applied to new events.
struct DefaultAlertsSettingsRows: View {
    private static let unset = -1, none = -2
    @State private var first: Int
    @State private var second: Int

    init() {
        let d = AppSettings.defaultAlerts
        _first = State(initialValue: d == nil ? Self.unset : (d!.first ?? Self.none))
        _second = State(initialValue: d.flatMap { $0.count > 1 ? $0[1] : nil } ?? Self.none)
    }

    var body: some View {
        Picker("First alert", selection: $first) {
            Text("Calendar default").tag(Self.unset)
            Text("None").tag(Self.none)
            ForEach(EventAlert.presets, id: \.self) { Text(EventAlert.label($0)).tag($0) }
        }
        .accessibilityIdentifier("defaultAlertFirst")
        Picker("Second alert", selection: $second) {
            Text("None").tag(Self.none)
            ForEach(EventAlert.presets, id: \.self) { Text(EventAlert.label($0)).tag($0) }
        }
        .disabled(first < 0)
        .accessibilityIdentifier("defaultAlertSecond")
        .onChange(of: first) { _, _ in save() }
        .onChange(of: second) { _, _ in save() }
    }

    private func save() {
        if first == Self.unset { AppSettings.defaultAlerts = nil; return }
        AppSettings.defaultAlerts = first == Self.none ? [] : ([first] + (second >= 0 ? [second] : []))
    }
}
