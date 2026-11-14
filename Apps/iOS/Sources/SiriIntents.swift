import AppIntents
import EventKit
import UIKit

/// Siri / Spotlight / Shortcuts support (issue #200). The intents run without the UI: they read EventKit
/// directly (the same `EventKitService` the app uses) and add the app-group cache for non-Apple calendars
/// such as Google, which only the app can fetch.
enum IntentCalendarData {
    /// Events overlapping `range`, soonest first, with declined ones dropped.
    static func events(in range: Range<Date>) -> [CalEvent] {
        var out: [CalEvent] = []
        let ek = EventKitService.shared
        let usedEventKit = ek.isAuthorized
        if usedEventKit {
            for s in ek.sources() where !ek.isBirthdayCalendar(s.calendarId) {
                out += ek.events(for: s, range: range).filter { !$0.isDeclined }
            }
        }
        // The cache carries Google/ICS events too; Apple ones came straight from EventKit above.
        for e in WidgetShared.read()?.events ?? [] {
            if usedEventKit, e.calendarId?.hasPrefix("ek|") ?? true { continue }
            out.append(cached(e))
        }
        return out.filter { $0.end > range.lowerBound && $0.start < range.upperBound }
            .sorted { ($0.start, $0.title) < ($1.start, $1.title) }
    }

    /// Timed events that haven't ended, over the next week.
    static func upcoming(now: Date = Date()) -> [CalEvent] {
        events(in: now..<now.addingTimeInterval(7 * 86400)).filter { !$0.isAllDay }
    }

    static func cached(_ e: WidgetEvent) -> CalEvent {
        CalEvent(id: e.id, eventId: e.id, sourceId: e.calendarId ?? "", calendarId: e.calendarId ?? "", accountId: "",
                 uid: e.id, title: e.title, start: e.start, end: e.end, isAllDay: e.isAllDay, location: e.location,
                 notes: "", attendees: [], htmlLink: nil, meetingURL: e.meetingURL.flatMap(URL.init(string:)),
                 colorHex: e.colorHex, sourceName: "", ownerName: nil, isOverlay: false, canEdit: false,
                 isBusyOnly: false, isRecurring: false, zoomMeetingID: nil, isTentative: false, isDeclined: false)
    }

    static func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }
}

enum IntentDay: String, AppEnum {
    case today, tomorrow
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Day"
    static var caseDisplayRepresentations: [IntentDay: DisplayRepresentation] = [
        .today: "Today", .tomorrow: "Tomorrow",
    ]
}

struct NextEventIntent: AppIntent {
    static var title: LocalizedStringResource = "What's Next on My Calendar"
    static var description = IntentDescription("Tells you your next event.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let now = Date()
        // Same rule as the app's "next meeting": a video call about to start takes over from one already under way.
        guard let next = CalEvent.nextMeeting(in: IntentCalendarData.upcoming(now: now), now: now) else {
            let msg = "You have nothing coming up on your calendar."
            return .result(value: msg, dialog: IntentDialog(stringLiteral: msg))
        }
        let msg: String
        if next.start <= now {
            msg = "\(next.title) is happening now, until \(IntentCalendarData.time(next.end))."
        } else {
            let rel = next.start.formatted(.relative(presentation: .named))
            msg = "Your next event is \(next.title) at \(IntentCalendarData.time(next.start)), \(rel)."
        }
        return .result(value: msg, dialog: IntentDialog(stringLiteral: msg))
    }
}

struct DayScheduleIntent: AppIntent {
    static var title: LocalizedStringResource = "What's on My Calendar"
    static var description = IntentDescription("Lists your events for today or tomorrow.")
    static var openAppWhenRun = false

    @Parameter(title: "Day", default: .today)
    var day: IntentDay

    static var parameterSummary: some ParameterSummary { Summary("What's on my calendar \(\.$day)") }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let cal = Calendar.current
        let start = cal.startOfDay(for: cal.date(byAdding: .day, value: day == .tomorrow ? 1 : 0, to: Date())!)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        var events = IntentCalendarData.events(in: start..<end)
        if day == .today { events = events.filter { $0.end > Date() || $0.isAllDay } }
        let label = day == .today ? "today" : "tomorrow"
        let msg: String
        if events.isEmpty {
            msg = day == .today ? "You have nothing else on your calendar today." : "You have nothing on your calendar tomorrow."
        } else {
            let items = events.prefix(8).map { $0.isAllDay ? "\($0.title), all day" : "\($0.title) at \(IntentCalendarData.time($0.start))" }
            let more = events.count > 8 ? ", and \(events.count - 8) more" : ""
            msg = "You have \(events.count) event\(events.count == 1 ? "" : "s") \(label): " + items.joined(separator: "; ") + more + "."
        }
        return .result(value: msg, dialog: IntentDialog(stringLiteral: msg))
    }
}

struct JoinNextMeetingIntent: AppIntent {
    static var title: LocalizedStringResource = "Join My Next Meeting"
    static var description = IntentDescription("Opens the video link of your next meeting.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let now = Date()
        let withLinks = IntentCalendarData.upcoming(now: now).filter { $0.meetingURL != nil }
        guard let next = CalEvent.nextMeeting(in: withLinks, now: now), let url = next.meetingURL else {
            return .result(dialog: "You have no upcoming meeting with a video link.")
        }
        await UIApplication.shared.open(url)
        return .result(dialog: IntentDialog(stringLiteral: "Joining \(next.title)."))
    }
}

struct AddEventIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Calendar Event"
    static var description = IntentDescription("Adds an event to your default calendar.")
    static var openAppWhenRun = false

    @Parameter(title: "Title", requestValueDialog: "What should the event be called?")
    var eventTitle: String

    @Parameter(title: "Start", requestValueDialog: "When does it start?")
    var start: Date

    @Parameter(title: "Duration (minutes)", default: 60)
    var minutes: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$eventTitle) at \(\.$start) for \(\.$minutes) minutes")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ek = EventKitService.shared
        if !ek.isAuthorized { _ = try? await ek.requestAccess() }
        guard ek.isAuthorized, let cal = ek.store.defaultCalendarForNewEvents else {
            return .result(dialog: "EZCal doesn't have access to your calendars. Open EZCal to grant it.")
        }
        let end = start.addingTimeInterval(TimeInterval(max(minutes, 1)) * 60)
        try ek.save(existing: nil, calendarId: cal.calendarIdentifier, title: eventTitle, start: start, end: end,
                    allDay: false, location: "", notes: nil)
        return .result(dialog: IntentDialog(stringLiteral: "Added \(eventTitle) at \(IntentCalendarData.time(start))."))
    }
}

struct EZCalShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: NextEventIntent(),
                    phrases: ["What's next in \(.applicationName)", "What's my next event in \(.applicationName)"],
                    shortTitle: "What's Next", systemImageName: "calendar.badge.clock")
        AppShortcut(intent: DayScheduleIntent(),
                    phrases: ["What's on my \(.applicationName) calendar \(\.$day)", "What's \(\.$day) in \(.applicationName)"],
                    shortTitle: "Day Schedule", systemImageName: "calendar")
        AppShortcut(intent: JoinNextMeetingIntent(),
                    phrases: ["Join my next meeting in \(.applicationName)", "Join my next \(.applicationName) meeting"],
                    shortTitle: "Join Next Meeting", systemImageName: "video.fill")
        AppShortcut(intent: AddEventIntent(),
                    phrases: ["Add an event in \(.applicationName)", "Add an event to \(.applicationName)"],
                    shortTitle: "Add Event", systemImageName: "calendar.badge.plus")
    }
}
