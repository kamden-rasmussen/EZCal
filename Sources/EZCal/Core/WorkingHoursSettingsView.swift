import SwiftUI

/// "Working hours" settings rows (days + start/end), shared by the macOS SettingsView and the iOS
/// SettingsSheet; drop it inside a `Form`/`Section` (issue #117). Persists via the `WorkingHours.Keys`.
struct WorkingHoursSettingsRows: View {
    @AppStorage(WorkingHours.Keys.days) private var daysRaw = WorkingHours.defaultDaysRaw
    @AppStorage(WorkingHours.Keys.start) private var start = WorkingHours.standard.startMinute
    @AppStorage(WorkingHours.Keys.end) private var end = WorkingHours.standard.endMinute

    var body: some View {
        WorkDaysPicker(daysRaw: $daysRaw)
        LabeledContent("Starts") {
            MinutePicker(minute: $start)
                .accessibilityIdentifier("workStartPicker")
                .onChange(of: start) { _, new in
                    let r = WorkingHours.reconciled(start: new, end: end, editing: .start)
                    if r.end != end { end = r.end }
                }
        }
        LabeledContent("Ends") {
            MinutePicker(minute: $end)
                .accessibilityIdentifier("workEndPicker")
                .onChange(of: end) { _, new in
                    let r = WorkingHours.reconciled(start: start, end: new, editing: .end)
                    if r.start != start { start = r.start }
                }
        }
        Text("Hours outside this range are shaded in the grid, and the day opens scrolled to the beginning of your working day.")
            .font(.caption).foregroundStyle(.secondary)
    }
}

/// Seven day-of-week toggle chips (Sun…Sat order follows the user's locale start-of-week for familiarity,
/// but the underlying storage always uses Calendar weekday numbers 1...7 so it's locale-independent).
struct WorkDaysPicker: View {
    @Binding var daysRaw: String
    private let symbols = Calendar.current.veryShortWeekdaySymbols   // index 0 = Sunday, matching weekday 1

    var body: some View {
        let days = WorkingHours.decodeDays(daysRaw)
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { weekday in
                let on = days.contains(weekday)
                Button {
                    var d = days
                    if on { d.remove(weekday) } else { d.insert(weekday) }
                    daysRaw = WorkingHours.encodeDays(d)
                } label: {
                    Text(symbols[weekday - 1])
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 28, height: 28)
                        .foregroundStyle(on ? Theme.accentText : Theme.text2)
                        .background(Circle().fill(on ? Theme.accent : Theme.hover))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Calendar.current.weekdaySymbols[weekday - 1])
                .accessibilityIdentifier("workDay-\(weekday)")
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

/// Half-hour time-of-day picker bound to minutes-since-midnight, so it stores cleanly in UserDefaults/AppSettings.
struct MinutePicker: View {
    @Binding var minute: Int

    private var asDate: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date() },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                minute = (c.hour ?? 0) * 60 + (((c.minute ?? 0) / WorkingHours.minuteStep) * WorkingHours.minuteStep)
            })
    }

    var body: some View {
        DatePicker("", selection: asDate, displayedComponents: .hourAndMinute)
            .labelsHidden()
            #if os(macOS)
            .datePickerStyle(.stepperField)
            .frame(width: 100)
            #endif
    }
}
