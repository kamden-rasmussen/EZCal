import SwiftUI

/// Phone Month mode: a compact month grid (day number + up to two event chips + "+N") with the selected
/// day's events listed underneath. The selected day is `store.anchor`, so Day / Agenda / Week stay
/// consistent when switching modes. Month navigation (prev/next) goes through `store.step`, which in
/// `.month` mode moves the anchor by a calendar month. Reuses the shared `MonthGrid` math.
struct MonthView: View {
    @Environment(CalendarStore.self) private var store
    @Binding var gridMode: ViewMode

    private var grid: MonthGrid { MonthGrid(cal: store.cal) }
    private var cal: Calendar { store.cal }

    /// Week indices covering the anchor's month.
    private var weeks: Range<Int> {
        let g = grid
        let key = g.monthKey(of: store.anchor)
        let first = g.weekIndex(of: g.monthStart(key))
        let lastDay = cal.date(byAdding: .day, value: -1, to: g.monthStart(key + 1))!
        return first..<(g.weekIndex(of: lastDay) + 1)
    }

    private var weekdayHeaders: [String] {
        let s = cal.veryShortStandaloneWeekdaySymbols
        return (0..<7).map { s[(cal.firstWeekday - 1 + $0) % 7] }
    }

    var body: some View {
        let g = grid
        let monthKey = g.monthKey(of: store.anchor)
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(Array(weekdayHeaders.enumerated()), id: \.offset) { _, s in
                        Text(s).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityHidden(true)
                ForEach(Array(weeks), id: \.self) { w in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { c in
                            cell(g.day(week: w, column: c), inMonth: g.monthKey(of: g.day(week: w, column: c)) == monthKey)
                        }
                    }
                    Divider()
                }
            }
            .frame(height: 300)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("monthGrid")
            Divider()
            dayList
        }
    }

    // MARK: - Grid cell

    private func cell(_ day: Date, inMonth: Bool) -> some View {
        let r = store.events(on: day)
        let evs = r.allDay + r.timed
        let isToday = cal.isDateInToday(day)
        let selected = cal.isDate(day, inSameDayAs: store.anchor)
        return Button { store.goTo(day) } label: {
            VStack(spacing: 1) {
                Text("\(cal.component(.day, from: day))")
                    .font(.footnote.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? Color.white : (inMonth ? Color.primary : Color.secondary.opacity(0.6)))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(isToday ? Color.accentColor : .clear))
                ForEach(evs.prefix(2)) { ev in
                    Text(ev.title.isEmpty ? "(No title)" : ev.title)
                        .font(.system(size: 8)).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 2)
                        .background(ev.color.opacity(ev.isAllDay ? 0.45 : 0.22), in: RoundedRectangle(cornerRadius: 2))
                }
                if evs.count > 2 {
                    Text("+\(evs.count - 2)").font(.system(size: 8)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 1).padding(.top, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(selected ? Color.accentColor.opacity(0.15) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month(.wide).day())
                            + (evs.isEmpty ? "" : ", \(evs.count) event\(evs.count == 1 ? "" : "s")")
                            + (isToday ? ", today" : ""))
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier("monthCell-" + Self.idFormatter.string(from: day))
    }

    static let idFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Selected day list

    private var dayList: some View {
        let r = store.events(on: store.anchor)
        let evs = r.allDay + r.timed
        return List {
            Section {
                ForEach(evs) { ev in
                    Button { store.sheet = .detail(ev) } label: { MonthRow(event: ev, day: store.anchor, cal: cal) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("monthRow")
                }
                if evs.isEmpty {
                    Text("No events").foregroundStyle(.secondary).accessibilityIdentifier("monthEmpty")
                }
            } header: {
                HStack {
                    Text(store.anchor.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .accessibilityIdentifier("monthSelectedHeader")
                    Spacer()
                    Button("Open day") { gridMode = .day }
                        .font(.footnote).textCase(nil)
                        .accessibilityIdentifier("openDayButton")
                }
            }
        }
        .listStyle(.plain)
        .accessibilityIdentifier("monthDayList")
    }
}

private struct MonthRow: View {
    let event: CalEvent
    let day: Date
    let cal: Calendar

    private var subtitle: String {
        let multi = !cal.isDate(event.start, inSameDayAs: max(event.start, event.end.addingTimeInterval(-1)))
        if event.isAllDay {
            if multi {
                let last = cal.date(byAdding: .second, value: -1, to: event.end) ?? event.end
                return "All day · " + event.start.formatted(.dateTime.month(.abbreviated).day())
                    + " – " + last.formatted(.dateTime.month(.abbreviated).day())
            }
            return "All day"
        }
        if multi {
            return event.start.formatted(.dateTime.month(.abbreviated).day().hour().minute())
                + " – " + event.end.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        }
        return timeText(event)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(event.color).frame(width: 10, height: 10).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title.isEmpty ? "(No title)" : event.title).font(.body)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                if !event.location.isEmpty {
                    Text(event.location).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}
