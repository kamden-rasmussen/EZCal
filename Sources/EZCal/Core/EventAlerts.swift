import Foundation
import EventKit

/// Per-event alerts (issue #131). An alert is "N minutes before the event starts" (0 = at the start);
/// that is what both EventKit relative alarms and Google `reminders.overrides` express.
enum EventAlert {
    /// The choices offered in the editor, in minutes before the start.
    static let presets: [Int] = [0, 5, 10, 15, 30, 60, 120, 1440, 2880, 10080]
    /// Google allows at most five reminder overrides per event.
    static let maxCount = 5

    static func label(_ minutes: Int) -> String {
        if minutes <= 0 { return "At time of event" }
        if minutes % 10080 == 0 { return plural(minutes / 10080, "week") + " before" }
        if minutes % 1440 == 0 { return plural(minutes / 1440, "day") + " before" }
        if minutes % 60 == 0 { return plural(minutes / 60, "hour") + " before" }
        return plural(minutes, "minute") + " before"
    }

    private static func plural(_ n: Int, _ unit: String) -> String { "\(n) \(unit)\(n == 1 ? "" : "s")" }

    /// Sorted, de-duplicated and clamped to what the calendars accept.
    static func normalized(_ minutes: [Int]) -> [Int] {
        Array(Set(minutes.map { max(0, $0) })).sorted().prefix(maxCount).map { $0 }
    }

    // MARK: EventKit

    static func ekAlarms(_ minutes: [Int]) -> [EKAlarm] {
        normalized(minutes).map { EKAlarm(relativeOffset: -TimeInterval($0) * 60) }
    }

    /// Relative alarms only; absolute-date and location alarms have no "minutes before" form.
    static func minutes(from alarms: [EKAlarm]?) -> [Int] {
        normalized((alarms ?? []).filter { $0.absoluteDate == nil && $0.structuredLocation == nil && $0.relativeOffset <= 0 }
            .map { Int((-$0.relativeOffset / 60).rounded()) })
    }

    // MARK: Google

    static func googleReminders(_ minutes: [Int]) -> [String: Any] {
        ["useDefault": false,
         "overrides": normalized(minutes).map { ["method": "popup", "minutes": $0] as [String: Any] }]
    }

    /// nil when the event uses the calendar's default reminders (their contents aren't on the event).
    static func minutes(fromGoogle useDefault: Bool?, overrides: [(method: String?, minutes: Int?)]?) -> [Int]? {
        if useDefault == true { return nil }
        return normalized((overrides ?? []).filter { $0.method != "email" }.compactMap(\.minutes))
    }

    /// The alert list to write on save, or nil to leave the event's alerts untouched.
    static func changes(draft: [Int]?, existing: [Int]?, isNew: Bool) -> [Int]? {
        guard let draft else { return nil }
        if isNew { return normalized(draft) }
        return normalized(draft) == existing.map(normalized) ? nil : normalized(draft)
    }
}

extension AppSettings {
    /// Alerts added to every new event. nil = never configured (Google falls back to the calendar's own default,
    /// EventKit events get none); an empty array = explicitly no alerts.
    static var defaultAlerts: [Int]? {
        get {
            guard let s = defaults.string(forKey: "defaultAlerts") else { return nil }
            return EventAlert.normalized(s.split(separator: ",").compactMap { Int($0) })
        }
        set {
            if let newValue { defaults.set(EventAlert.normalized(newValue).map(String.init).joined(separator: ","), forKey: "defaultAlerts") }
            else { defaults.removeObject(forKey: "defaultAlerts") }
        }
    }
}
