import SwiftUI

/// Form rows for Settings → "Default calendar" (mode, fixed pick, schedule rules). Shared by the macOS
/// SettingsView and the iOS SettingsSheet; drop it inside a `Form`/`Section`.
struct DefaultCalendarSettingsRows: View {
    @Environment(CalendarStore.self) private var store
    @AppStorage(DefaultCalendarSettings.defaultsKey) private var raw = ""

    private var writable: [Source] { store.calendars.filter(\.canWrite) }

    private var settings: Binding<DefaultCalendarSettings> {
        Binding(get: { DefaultCalendarSettings(rawValue: raw) }, set: { raw = $0.rawValue })
    }

    var body: some View {
        let s = settings
        Picker("Default calendar", selection: s.mode) {
            ForEach(DefaultCalendarMode.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        switch s.wrappedValue.mode {
        case .followSidebar:
            Text("New events start on the calendar you most recently turned on in the sidebar.")
                .font(.caption).foregroundStyle(.secondary)
        case .fixed:
            calendarPicker("Calendar", selection: s.fixedSourceId)
        case .schedule:
            ForEach(s.rules) { $rule in ruleRow($rule) }
                .onDelete { s.wrappedValue.rules.remove(atOffsets: $0) }
            Button {
                s.wrappedValue.rules.append(DefaultCalendarRule(
                    days: [2, 3, 4, 5, 6], startMinute: 9 * 60, endMinute: 17 * 60,
                    sourceId: writable.first?.id ?? ""))
            } label: { Label("Add rule", systemImage: "plus") }
            calendarPicker("Otherwise", selection: s.fallbackSourceId)
            Text("The first matching rule wins. A start time later than the end time runs overnight into the next day.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func calendarPicker(_ title: String, selection: Binding<String?>) -> some View {
        Picker(title, selection: selection) {
            Text("Automatic").tag(String?.none)
            ForEach(writable) { src in
                Text(src.isEventKit ? "\(src.name) · \(src.groupTitle)" : src.name).tag(Optional(src.id))
            }
        }
    }

    private func ruleRow(_ rule: Binding<DefaultCalendarRule>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(1...7, id: \.self) { weekday in
                    let on = rule.wrappedValue.days.contains(weekday)
                    Button {
                        if on { rule.wrappedValue.days.remove(weekday) } else { rule.wrappedValue.days.insert(weekday) }
                    } label: {
                        Text(Calendar.current.veryShortWeekdaySymbols[weekday - 1])
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 26, height: 26)
                            .foregroundStyle(on ? Theme.accentText : Theme.text2)
                            .background(Circle().fill(on ? Theme.accent : Theme.hover))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Calendar.current.weekdaySymbols[weekday - 1])
                    .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                }
            }
            HStack {
                timePicker(rule.startMinute)
                Text("to").foregroundStyle(.secondary)
                timePicker(rule.endMinute)
            }
            Picker("Calendar", selection: rule.sourceId) {
                ForEach(writable) { src in
                    Text(src.isEventKit ? "\(src.name) · \(src.groupTitle)" : src.name).tag(src.id)
                }
                if !writable.contains(where: { $0.id == rule.wrappedValue.sourceId }) {
                    Text("Unavailable").tag(rule.wrappedValue.sourceId)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func timePicker(_ minute: Binding<Int>) -> some View {
        DatePicker("", selection: Binding(
            get: { Calendar.current.date(bySettingHour: minute.wrappedValue / 60, minute: minute.wrappedValue % 60, second: 0, of: Date()) ?? Date() },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                minute.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }), displayedComponents: .hourAndMinute)
            .labelsHidden()
    }
}
