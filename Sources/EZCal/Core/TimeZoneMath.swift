import Foundation

/// Pure helpers for showing times in a second time zone. Every function takes the zones and the instant
/// explicitly so DST is handled correctly and the results are unit-testable.
enum ZoneMath {
    /// Minutes the `to` zone is ahead of the `from` zone at `date` (negative when behind).
    static func offsetMinutes(from: TimeZone, to: TimeZone, at date: Date) -> Int {
        (to.secondsFromGMT(for: date) - from.secondsFromGMT(for: date)) / 60
    }

    /// "+6h", "-3h", "+5:30h" or "same time".
    static func offsetLabel(minutes: Int) -> String {
        if minutes == 0 { return "same time" }
        let sign = minutes < 0 ? "-" : "+", m = abs(minutes)
        return m % 60 == 0 ? "\(sign)\(m / 60)h" : "\(sign)\(m / 60):\(String(format: "%02d", m % 60))h"
    }

    /// "GMT+1", "GMT-7", "GMT+5:30".
    static func gmtLabel(_ zone: TimeZone, at date: Date) -> String {
        let s = zone.secondsFromGMT(for: date) / 60
        if s == 0 { return "GMT" }
        let sign = s < 0 ? "-" : "+", m = abs(s)
        return m % 60 == 0 ? "GMT\(sign)\(m / 60)" : "GMT\(sign)\(m / 60):\(String(format: "%02d", m % 60))"
    }

    private static let northAmerica: [String: String] = [
        "America/Los_Angeles": "PT", "America/Vancouver": "PT", "America/Tijuana": "PT",
        "America/Denver": "MT", "America/Edmonton": "MT", "America/Phoenix": "MT",
        "America/Chicago": "CT", "America/Winnipeg": "CT", "America/Mexico_City": "CT",
        "America/New_York": "ET", "America/Toronto": "ET", "America/Detroit": "ET",
        "America/Halifax": "AT", "America/Anchorage": "AKT", "Pacific/Honolulu": "HST",
    ]
    /// (standard, daylight) abbreviations for common zones ICU doesn't name for us.
    private static let named: [String: (String, String)] = [
        "Europe/Berlin": ("CET", "CEST"), "Europe/Paris": ("CET", "CEST"), "Europe/Madrid": ("CET", "CEST"),
        "Europe/Rome": ("CET", "CEST"), "Europe/Amsterdam": ("CET", "CEST"), "Europe/Brussels": ("CET", "CEST"),
        "Europe/Vienna": ("CET", "CEST"), "Europe/Zurich": ("CET", "CEST"), "Europe/Stockholm": ("CET", "CEST"),
        "Europe/Oslo": ("CET", "CEST"), "Europe/Copenhagen": ("CET", "CEST"), "Europe/Prague": ("CET", "CEST"),
        "Europe/Warsaw": ("CET", "CEST"), "Europe/Budapest": ("CET", "CEST"),
        "Europe/London": ("GMT", "BST"), "Europe/Dublin": ("GMT", "IST"), "Europe/Lisbon": ("WET", "WEST"),
        "Europe/Athens": ("EET", "EEST"), "Europe/Helsinki": ("EET", "EEST"), "Europe/Kyiv": ("EET", "EEST"),
        "Europe/Istanbul": ("TRT", "TRT"), "Europe/Moscow": ("MSK", "MSK"),
        "Asia/Tokyo": ("JST", "JST"), "Asia/Seoul": ("KST", "KST"), "Asia/Kolkata": ("IST", "IST"),
        "Asia/Shanghai": ("CST", "CST"), "Asia/Singapore": ("SGT", "SGT"), "Asia/Hong_Kong": ("HKT", "HKT"),
        "Australia/Sydney": ("AEST", "AEDT"), "Australia/Melbourne": ("AEST", "AEDT"), "Australia/Perth": ("AWST", "AWST"),
        "Pacific/Auckland": ("NZST", "NZDT"), "UTC": ("UTC", "UTC"),
    ]

    /// Short zone name for a gutter header: "PT", "CET", "JST". Falls back to ICU's abbreviation, then GMT offset.
    static func shortName(_ zone: TimeZone, at date: Date = Date()) -> String {
        if let na = northAmerica[zone.identifier] { return na }
        if let n = named[zone.identifier] { return zone.isDaylightSavingTime(for: date) ? n.1 : n.0 }
        if let a = zone.abbreviation(for: date), !a.hasPrefix("GMT") { return a }
        return gmtLabel(zone, at: date)
    }

    /// Wall-clock hour and minute of `date` in `zone`.
    static func wallClock(_ date: Date, in zone: TimeZone) -> (hour: Int, minute: Int) {
        var c = Calendar(identifier: .gregorian); c.timeZone = zone
        let p = c.dateComponents([.hour, .minute], from: date)
        return (p.hour ?? 0, p.minute ?? 0)
    }

    /// Whether `date` falls on the previous (-1), same (0) or next (+1) calendar day in `zone` compared with `local`.
    static func dayShift(of date: Date, local: TimeZone, zone: TimeZone) -> Int {
        func ymd(_ tz: TimeZone) -> Int {
            var c = Calendar(identifier: .gregorian); c.timeZone = tz
            let p = c.dateComponents([.year, .month, .day], from: date)
            return (p.year ?? 0) * 10_000 + (p.month ?? 0) * 100 + (p.day ?? 0)
        }
        let a = ymd(local), b = ymd(zone)
        return b == a ? 0 : (b > a ? 1 : -1)
    }

    /// Gutter label for a time in `zone`: "9 AM", or "9:30 AM" when the offset isn't a whole hour.
    static func hourLabel(_ date: Date, in zone: TimeZone) -> String {
        let style = Date.FormatStyle(timeZone: zone)
        return wallClock(date, in: zone).minute == 0 ? date.formatted(style.hour()) : date.formatted(style.hour().minute())
    }

    /// Tooltip text: "Tue 8:00 AM – 9:00 AM CET". The weekday is added when the start is on a different day there.
    static func rangeLabel(start: Date, end: Date, in zone: TimeZone, local: TimeZone = .current) -> String {
        let style = Date.FormatStyle(timeZone: zone)
        let s = start.formatted(style.hour().minute()), e = end.formatted(style.hour().minute())
        let day = dayShift(of: start, local: local, zone: zone) == 0 ? "" : start.formatted(style.weekday(.abbreviated)) + " "
        return "\(day)\(s) – \(e) \(shortName(zone, at: start))"
    }
}

extension AppSettings {
    /// The zone to show as a second gutter and in tooltips, or nil when off or not chosen.
    /// `EZCAL_SECONDARY_TZ=Europe/Berlin` forces one for screenshots.
    static var secondaryTimeZone: TimeZone? {
        if let forced = ProcessInfo.processInfo.environment["EZCAL_SECONDARY_TZ"], let z = TimeZone(identifier: forced) { return z }
        return effectiveZone(id: defaults.string(forKey: "secondaryZoneID") ?? "",
                             show: defaults.object(forKey: "showSecondaryZone") as? Bool ?? true)
    }

    static func effectiveZone(id: String, show: Bool) -> TimeZone? {
        if let forced = ProcessInfo.processInfo.environment["EZCAL_SECONDARY_TZ"], let z = TimeZone(identifier: forced) { return z }
        return show && !id.isEmpty ? TimeZone(identifier: id) : nil
    }
}
