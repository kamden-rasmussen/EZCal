import SwiftUI

struct MonthView: View {
    @Environment(CalendarStore.self) private var store

    var body: some View {
        let days = store.visibleDays
        let c = store.cal
        let month = c.component(.month, from: store.anchor)

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(days.prefix(7), id: \.self) { d in
                    Text(d.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                        .font(.system(size: 11, weight: .medium)).tracking(0.5)
                        .foregroundStyle(Theme.text2)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
            }
            Divider().overlay(Theme.line)
            GeometryReader { geo in
                let rowH = geo.size.height / 6
                VStack(spacing: 0) {
                    ForEach(0..<6, id: \.self) { r in
                        HStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { col in
                                let d = days[r * 7 + col]
                                MonthCell(day: d, inMonth: c.component(.month, from: d) == month, maxItems: max(1, Int((rowH - 30) / 18)))
                                    .frame(height: rowH)
                                    .overlay(alignment: .leading) { Rectangle().fill(Theme.line2).frame(width: 1) }
                            }
                        }
                        .overlay(alignment: .top) { Rectangle().fill(Theme.line2).frame(height: 1) }
                    }
                }
            }
        }
        .background(Theme.bg)
    }
}

private struct MonthCell: View {
    @Environment(CalendarStore.self) private var store
    let day: Date
    let inMonth: Bool
    let maxItems: Int

    var body: some View {
        let isToday = Calendar.current.isDateInToday(day)
        let evs = store.events(on: day)
        let all = evs.allDay + evs.timed
        let shown = all.prefix(all.count > maxItems ? maxItems - 1 : maxItems)

        VStack(alignment: .leading, spacing: 2) {
            Text(day.formatted(.dateTime.day()))
                .font(.system(size: 12, weight: isToday ? .bold : .regular).monospacedDigit())
                .foregroundStyle(isToday ? Theme.accentText : (inMonth ? Theme.text : Theme.text3.opacity(0.7)))
                .frame(width: 22, height: 22)
                .background(Circle().fill(isToday ? Theme.accent : .clear))
            ForEach(Array(shown)) { e in
                let focused = store.focusedEventID == e.id
                HStack(spacing: 5) {
                    Circle().fill(e.color).frame(width: 6, height: 6)
                    Text(label(e)).font(.system(size: 11)).foregroundStyle(e.isOverlay ? Theme.text2 : Theme.text).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4).frame(height: 17)
                .background(RoundedRectangle(cornerRadius: 4).stroke(focused ? Theme.accent : .clear, lineWidth: 2))
                .contentShape(Rectangle())
                .onTapGesture { store.focusedEventID = e.id; store.sheet = .detail(e) }
                .accessibilityLabel(e.title)
                .accessibilityAddTraits(.isButton)
            }
            if all.count > shown.count {
                Text("\(all.count - shown.count) more").font(.system(size: 10)).foregroundStyle(Theme.text3).padding(.horizontal, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(3)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(isToday ? Theme.todayBg : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            let start = store.cal.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
            store.newDraft(start: start)
        }
        .onTapGesture { store.anchor = day; store.setMode(.day) }
    }

    private func label(_ e: CalEvent) -> String {
        let t = e.isAllDay ? "" : e.start.formatted(.dateTime.hour().minute()) + " "
        let who = e.ownerName.map { "\($0) · " } ?? ""
        return t + who + e.title
    }
}
