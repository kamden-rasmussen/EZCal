import WidgetKit
import AppIntents
import SwiftUI
import EventKit

struct AgendaEntry: TimelineEntry {
    let date: Date
    let events: [WidgetEvent]   // events not yet ended at `date`, soonest first
    let isPlaceholder: Bool
}

struct AgendaProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> AgendaEntry {
        AgendaEntry(date: Date(), events: WidgetShared.demoEvents(), isPlaceholder: true)
    }

    func snapshot(for configuration: SelectCalendarsIntent, in context: Context) async -> AgendaEntry {
        let now = Date()
        let live = Self.load(now: now, only: configuration.selectedIDs)
        return AgendaEntry(date: now, events: context.isPreview && live.isEmpty ? WidgetShared.demoEvents(now: now) : live,
                           isPlaceholder: false)
    }

    func timeline(for configuration: SelectCalendarsIntent, in context: Context) async -> Timeline<AgendaEntry> {
        let now = Date()
        let all = Self.load(now: now, only: configuration.selectedIDs)
        // One entry now plus one at every upcoming start/end so "next event" and countdowns roll over on their own.
        var dates: Set<Date> = [now]
        for e in all where !e.isAllDay {
            if e.start > now { dates.insert(e.start) }
            if e.end > now { dates.insert(e.end) }
        }
        let sorted = Array(dates.sorted().prefix(24))
        let entries = sorted.map { d in
            AgendaEntry(date: d, events: all.filter { $0.end > d }, isPlaceholder: false)
        }
        let hourly = now.addingTimeInterval(3600)
        return Timeline(entries: entries, policy: .after(hourly))
    }

    /// EventKit first (if the widget process has calendar access), else the app-group cache.
    /// `only` limits the result to those `Source.id`s; empty means every calendar.
    static func load(now: Date, only: Set<String> = []) -> [WidgetEvent] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        let end = cal.date(byAdding: .day, value: 3, to: start)!
        func allowed(_ e: WidgetEvent) -> Bool { only.isEmpty || (e.calendarId.map(only.contains) ?? false) }
        let cached = (WidgetShared.read()?.events ?? []).filter { $0.end > start && $0.start < end }
        var result: [WidgetEvent] = []
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess {
            let store = EKEventStore()
            var calendars: [EKCalendar]? = nil
            if !only.isEmpty {
                calendars = store.calendars(for: .event).filter { only.contains("ek|" + $0.calendarIdentifier) }
            }
            let pred = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
            result = (calendars?.isEmpty == true) ? [] : store.events(matching: pred).compactMap { e in
                guard e.status != .canceled, let s = e.startDate, let en = e.endDate else { return nil }
                return WidgetEvent(id: e.eventIdentifier ?? UUID().uuidString,
                                   title: (e.title?.isEmpty == false ? e.title! : "(No title)"),
                                   start: s, end: en, isAllDay: e.isAllDay, location: e.location ?? "",
                                   colorHex: Self.hex(e.calendar?.cgColor))
            }
        }
        if result.isEmpty {
            result = cached.filter(allowed)
        } else {
            // Google and subscription calendars only reach the widget through the cache.
            result += cached.filter { !($0.calendarId?.hasPrefix("ek|") ?? true) && allowed($0) }
        }
        return result.filter { $0.end > now }
            .sorted { ($0.isAllDay ? 1 : 0, $0.start) < ($1.isAllDay ? 1 : 0, $1.start) }
    }

    private static func hex(_ cg: CGColor?) -> String {
        guard let cg, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let c = cg.converted(to: space, intent: .defaultIntent, options: nil)?.components,
              c.count >= 3 else { return "#4285F4" }
        return String(format: "#%02X%02X%02X", Int(c[0] * 255), Int(c[1] * 255), Int(c[2] * 255))
    }
}

struct UpNextWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "UpNextWidget", intent: SelectCalendarsIntent.self, provider: AgendaProvider()) { entry in
            UpNextView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Up Next")
        .description("Your next events at a glance. Edit the widget to choose calendars.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "TodayWidget", intent: SelectCalendarsIntent.self, provider: AgendaProvider()) { entry in
            TodayView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Today's agenda. Edit the widget to choose calendars.")
        .supportedFamilies([.systemLarge])
    }
}

@main
struct EZCalWidgets: WidgetBundle {
    var body: some Widget {
        UpNextWidget()
        TodayWidget()
    }
}
