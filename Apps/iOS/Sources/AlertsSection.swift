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
