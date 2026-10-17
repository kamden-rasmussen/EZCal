import Foundation

/// Which calendar a NEW event starts on. Pure value types + a pure resolver so the rules are unit-testable;
/// `CalendarStore.defaultSource` supplies the inputs (writable source ids, last sidebar pick, "now").
enum DefaultCalendarMode: String, Codable, CaseIterable, Sendable {
    case followSidebar, fixed, schedule

    var title: String {
        switch self {
        case .followSidebar: return "Last selected in sidebar"
        case .fixed: return "Fixed calendar"
        case .schedule: return "By schedule"
        }
    }
}

/// "On these weekdays, between these times, use this calendar." Minutes are wall-clock minutes since local
/// midnight. `startMinute > endMinute` is an overnight range (e.g. 22:00-06:00): the part after midnight
/// belongs to the day the rule STARTED on (Fri 22:00-06:00 covers Saturday's early morning too).
/// `startMinute == endMinute` means the whole day.
struct DefaultCalendarRule: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    /// `Calendar` weekday numbers: 1 = Sunday … 7 = Saturday.
    var days: Set<Int>
    var startMinute: Int
    var endMinute: Int
    var sourceId: String

    func matches(_ date: Date, cal: Calendar = .current) -> Bool {
        let weekday = cal.component(.weekday, from: date)
        let minute = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
        if startMinute == endMinute { return days.contains(weekday) }
        if startMinute < endMinute {
            return days.contains(weekday) && minute >= startMinute && minute < endMinute
        }
        // Overnight: evening part on a listed day, early-morning part on the day after a listed day.
        if minute >= startMinute { return days.contains(weekday) }
        if minute < endMinute { return days.contains(weekday == 1 ? 7 : weekday - 1) }
        return false
    }
}

struct DefaultCalendarSettings: Codable, Equatable, Sendable {
    var mode: DefaultCalendarMode = .followSidebar
    var fixedSourceId: String?
    var rules: [DefaultCalendarRule] = []
    var fallbackSourceId: String?

    static let defaultsKey = "defaultCalendarSettings"
    static let lastSelectedKey = "lastSelectedCalendarId"

    // JSON-in-a-string so it works with @AppStorage and UserDefaults alike.
    var rawValue: String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
    init() {}
    init(rawValue: String) {
        self = rawValue.data(using: .utf8).flatMap { try? JSONDecoder().decode(Self.self, from: $0) } ?? Self()
    }

    static func load(_ defaults: UserDefaults = .standard) -> Self {
        Self(rawValue: defaults.string(forKey: defaultsKey) ?? "")
    }
    func save(_ defaults: UserDefaults = .standard) { defaults.set(rawValue, forKey: Self.defaultsKey) }
}

enum DefaultCalendarResolver {
    /// The source id new events should start on, or nil when nothing configured is usable (the caller then
    /// applies its own built-in default). A configured id that isn't in `writable` (deleted, read-only,
    /// account removed) is skipped rather than returned, so the result is always safe to use.
    /// - Parameters:
    ///   - writable: ids of calendars the user can create events on.
    ///   - lastSelected: the calendar most recently chosen in the sidebar.
    static func resolve(_ s: DefaultCalendarSettings, writable: Set<String>, lastSelected: String?,
                        now: Date = Date(), cal: Calendar = .current) -> String? {
        func ok(_ id: String?) -> String? { id.flatMap { writable.contains($0) ? $0 : nil } }
        switch s.mode {
        case .followSidebar: return ok(lastSelected)
        case .fixed: return ok(s.fixedSourceId)
        case .schedule:
            // First matching rule whose calendar is still usable wins; otherwise the fallback.
            for r in s.rules where r.matches(now, cal: cal) {
                if let id = ok(r.sourceId) { return id }
            }
            return ok(s.fallbackSourceId)
        }
    }
}
