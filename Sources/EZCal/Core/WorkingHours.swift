import Foundation

/// The user's working days and hours. Pure value type so the grid shading, the initial scroll position and
/// (later) "find a time" can all share one definition. Minutes are wall-clock minutes since local midnight.
struct WorkingHours: Equatable {
    /// `Calendar` weekday numbers: 1 = Sunday … 7 = Saturday.
    var days: Set<Int>
    var startMinute: Int
    var endMinute: Int

    static let minuteStep = 30
    static let standard = WorkingHours(days: [2, 3, 4, 5, 6], startMinute: 9 * 60, endMinute: 17 * 60)

    /// UserDefaults keys (also used with @AppStorage).
    enum Keys {
        static let days = "workDays"
        static let start = "workStartMinute"
        static let end = "workEndMinute"
    }
    static let defaultDaysRaw = "2,3,4,5,6"

    /// Clamps to a sane range: start in 0..<24h, end at least one step after start and at most 24h.
    init(days: Set<Int>, startMinute: Int, endMinute: Int) {
        let s = min(max(startMinute, 0), 24 * 60 - Self.minuteStep)
        self.days = days.filter { (1...7).contains($0) }
        self.startMinute = s
        self.endMinute = min(max(endMinute, s + Self.minuteStep), 24 * 60)
    }

    init(daysRaw: String, startMinute: Int, endMinute: Int) {
        self.init(days: Self.decodeDays(daysRaw), startMinute: startMinute, endMinute: endMinute)
    }

    // MARK: Queries

    func isWorkingDay(_ day: Date, cal: Calendar = .current) -> Bool {
        days.contains(cal.component(.weekday, from: day))
    }

    /// Working minutes for that day, or nil on a non-working day.
    func workingRange(on day: Date, cal: Calendar = .current) -> Range<Int>? {
        isWorkingDay(day, cal: cal) ? startMinute..<endMinute : nil
    }

    /// The parts of the day (minutes since midnight) to shade: everything on a non-working day,
    /// otherwise before the start and after the end.
    func nonWorkingRanges(on day: Date, cal: Calendar = .current) -> [Range<Int>] {
        guard let w = workingRange(on: day, cal: cal) else { return [0..<24 * 60] }
        var out: [Range<Int>] = []
        if w.lowerBound > 0 { out.append(0..<w.lowerBound) }
        if w.upperBound < 24 * 60 { out.append(w.upperBound..<24 * 60) }
        return out
    }

    /// Is this instant inside working hours?
    func contains(_ date: Date, cal: Calendar = .current) -> Bool {
        guard let r = workingRange(on: date, cal: cal) else { return false }
        return r.contains(Self.minuteOfDay(date, cal: cal))
    }

    /// Hour to scroll to when the grid opens: the start of the working day.
    var startHour: Int { startMinute / 60 }
    /// End hour rounded up, so a partial last hour (e.g. ending 17:30) still shows in an hour-by-hour axis.
    var endHour: Int { (endMinute + 59) / 60 }

    enum Edge { case start, end }

    /// Keeps start < end after the user edits one side: the other side is pushed a step away.
    static func reconciled(start: Int, end: Int, editing: Edge) -> (start: Int, end: Int) {
        switch editing {
        case .start: return (start, end <= start ? min(start + minuteStep, 24 * 60) : end)
        case .end: return (start >= end ? max(end - minuteStep, 0) : start, end)
        }
    }

    /// Hour a phone-style grid should open scrolled to. Today: a couple of hours before now, but never
    /// above the start of the working day. Other days: an hour before the first event, or the start of
    /// the working day when that is earlier (or the day is empty).
    func initialScrollHour(nowHour: Int?, firstEventHour: Int?) -> Int {
        if let nowHour { return min(max(nowHour - 2, startHour), 23) }
        if let e = firstEventHour { return max(min(e - 1, startHour), 0) }
        return startHour
    }

    static func minuteOfDay(_ date: Date, cal: Calendar = .current) -> Int {
        let c = cal.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    // MARK: Storage helpers ("2,3,4,5,6")

    static func decodeDays(_ raw: String) -> Set<Int> {
        Set(raw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.filter { (1...7).contains($0) })
    }

    static func encodeDays(_ days: Set<Int>) -> String {
        days.sorted().map(String.init).joined(separator: ",")
    }

    /// "9:00 AM" style label for a minute-of-day value (24:00 renders as midnight).
    static func label(minute: Int) -> String {
        var c = DateComponents(); c.hour = (minute / 60) % 24; c.minute = minute % 60
        let d = Calendar.current.date(from: c) ?? Date()
        return d.formatted(date: .omitted, time: .shortened)
    }
}

extension AppSettings {
    /// Working days and hours (default Mon–Fri 9:00–17:00). Read by the grid and available to other features.
    static var workingHours: WorkingHours {
        WorkingHours(daysRaw: defaults.string(forKey: WorkingHours.Keys.days) ?? WorkingHours.defaultDaysRaw,
                     startMinute: defaults.object(forKey: WorkingHours.Keys.start) as? Int ?? WorkingHours.standard.startMinute,
                     endMinute: defaults.object(forKey: WorkingHours.Keys.end) as? Int ?? WorkingHours.standard.endMinute)
    }
}
