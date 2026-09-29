import WidgetKit
import SwiftUI

private func timeText(_ e: WidgetEvent) -> String {
    e.isAllDay ? "All day" : e.start.formatted(date: .omitted, time: .shortened)
}

struct EventRow: View {
    let e: WidgetEvent
    var showDay = false
    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(Color(widgetHex: e.colorHex)).frame(width: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(e.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text((showDay && !Calendar.current.isDateInToday(e.start) ? "Tomorrow " : "") + timeText(e)
                     + (e.location.isEmpty ? "" : " · \(e.location)"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.primary)
    }
}

struct UpNextView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AgendaEntry
    private var next: WidgetEvent? { entry.events.first { !$0.isAllDay } ?? entry.events.first }

    var body: some View {
        switch family {
        case .accessoryInline:
            if let n = next { Text("\(n.title) \(timeText(n))") } else { Text("No events") }
        case .accessoryRectangular:
            if let n = next {
                VStack(alignment: .leading, spacing: 1) {
                    Text(n.title).font(.headline).lineLimit(1)
                    Text(timeText(n)).font(.caption)
                    if !n.location.isEmpty { Text(n.location).font(.caption2).lineLimit(1) }
                }.frame(maxWidth: .infinity, alignment: .leading).widgetURL(WidgetShared.eventURL(n))
            } else { Text("No upcoming events").font(.caption).widgetURL(WidgetShared.todayURL) }
        case .systemMedium:
            medium
        default:
            small
        }
    }

    private var small: some View {
        Group {
            if let n = next {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Circle().fill(Color(widgetHex: n.colorHex)).frame(width: 8, height: 8)
                        Text(n.start <= entry.date ? "NOW" : "UP NEXT").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    }
                    Text(n.title).font(.headline).lineLimit(2)
                    Text(timeText(n)).font(.subheadline).foregroundStyle(.secondary)
                    if n.start > entry.date && !n.isAllDay {
                        Text(n.start, style: .relative).font(.caption.weight(.medium)).foregroundStyle(Color(widgetHex: n.colorHex))
                    }
                    Spacer(minLength: 0)
                    if !n.location.isEmpty {
                        Label(n.location, systemImage: "mappin").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .widgetURL(WidgetShared.eventURL(n))
            } else { empty }
        }
    }

    private var medium: some View {
        let today = Calendar.current.startOfDay(for: entry.date)
        let rows = Array(entry.events.prefix(3))
        let tomorrowSpill = rows.contains { !Calendar.current.isDate($0.start, inSameDayAs: today) }
        return Group {
            if rows.isEmpty { empty } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tomorrowSpill ? "UP NEXT" : "TODAY").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    ForEach(rows) { e in
                        Link(destination: WidgetShared.eventURL(e)) { EventRow(e: e, showDay: true) }.buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 4) {
            Image(systemName: "calendar.badge.checkmark").font(.title2)
            Text("Nothing coming up").font(.caption)
        }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity).widgetURL(WidgetShared.todayURL)
    }
}

struct TodayView: View {
    let entry: AgendaEntry
    var body: some View {
        let cal = Calendar.current
        let today = entry.events.filter { cal.isDate($0.start, inSameDayAs: entry.date) || $0.start < entry.date }
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.date.formatted(.dateTime.weekday(.wide).month().day())).font(.headline)
            if today.isEmpty {
                Spacer()
                Text("Nothing else today").foregroundStyle(.secondary).frame(maxWidth: .infinity)
            } else {
                ForEach(today.prefix(7)) { e in
                    Link(destination: WidgetShared.eventURL(e)) { EventRow(e: e) }.buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, alignment: .leading).widgetURL(WidgetShared.todayURL)
    }
}

#Preview("Small", as: .systemSmall) { UpNextWidget() } timeline: {
    AgendaEntry(date: Date(), events: WidgetShared.demoEvents(), isPlaceholder: false)
}
#Preview("Medium", as: .systemMedium) { UpNextWidget() } timeline: {
    AgendaEntry(date: Date(), events: WidgetShared.demoEvents(), isPlaceholder: false)
}
#Preview("Large", as: .systemLarge) { TodayWidget() } timeline: {
    AgendaEntry(date: Date(), events: WidgetShared.demoEvents(), isPlaceholder: false)
}
