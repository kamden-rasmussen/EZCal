import Foundation

/// Pure week/month math behind the continuously scrolling Month view. Weeks are addressed by an
/// integer index (weeks since a fixed reference week), so a week's identity never changes while the
/// visible window slides — that keeps SwiftUI row ids stable.
struct MonthGrid: Equatable {
    let cal: Calendar
    /// Start of the week containing the reference date (respects `cal.firstWeekday`).
    let refStart: Date

    init(cal: Calendar) {
        self.cal = cal
        let ref = Date(timeIntervalSinceReferenceDate: 0)
        self.refStart = cal.dateInterval(of: .weekOfYear, for: ref)?.start ?? cal.startOfDay(for: ref)
    }

    func weekStart(_ index: Int) -> Date {
        cal.date(byAdding: .day, value: index * 7, to: refStart)!
    }

    func day(week: Int, column: Int) -> Date {
        cal.date(byAdding: .day, value: week * 7 + column, to: refStart)!
    }

    func weekIndex(of date: Date) -> Int {
        let days = cal.dateComponents([.day], from: refStart, to: cal.startOfDay(for: date)).day ?? 0
        return Int((Double(days) / 7.0).rounded(.down))
    }

    /// year*12 + (month-1): a single comparable value per calendar month.
    func monthKey(of date: Date) -> Int {
        let c = cal.dateComponents([.year, .month], from: date)
        return (c.year ?? 0) * 12 + ((c.month ?? 1) - 1)
    }

    /// The month a week "belongs" to: the month of its fourth day, so a week straddling two months
    /// counts toward whichever has the majority of it.
    func monthKey(forWeek index: Int) -> Int {
        monthKey(of: day(week: index, column: 3))
    }

    func monthStart(_ key: Int) -> Date {
        cal.date(from: DateComponents(year: key / 12, month: key % 12 + 1, day: 1))!
    }

    /// The week to scroll to so that month `key` is what the user sees at the top; it is always a week
    /// for which `monthKey(forWeek:) == key`, so scrolling there can't flip the label to another month.
    func firstWeek(ofMonth key: Int) -> Int {
        let idx = weekIndex(of: monthStart(key))
        return monthKey(forWeek: idx) == key ? idx : idx + 1
    }

    /// `anchor` moved into month `key`, keeping its day-of-month (clamped to the month's length).
    func anchor(_ anchor: Date, movedToMonth key: Int) -> Date {
        let first = monthStart(key)
        let dim = cal.range(of: .day, in: .month, for: first)?.count ?? 28
        let d = min(cal.component(.day, from: anchor), dim)
        return cal.date(byAdding: .day, value: d - 1, to: first)!
    }

    /// Range we ask the server for while `key` is the current month: that month plus one either side,
    /// padded out to whole weeks, so a bit of scrolling never shows empty rows.
    func fetchRange(aroundMonth key: Int) -> Range<Date> {
        let lo = weekStart(weekIndex(of: monthStart(key - 1)))
        let hiMonth = monthStart(key + 2)
        return lo..<cal.endOfDay(cal.date(byAdding: .day, value: -1, to: hiMonth)!)
    }
}

/// Sliding window of week indices rendered by the lazy stack.
struct WeekWindow: Equatable {
    static let radius = 260   // ~5 years each side; rows are lazy so this is cheap
    static let margin = 40    // recenter when the top week gets this close to an edge

    var center: Int
    var range: Range<Int> { (center - Self.radius)..<(center + Self.radius) }

    /// Returns a recentered window if `top` has wandered near an edge, else nil.
    func recentered(forTop top: Int) -> WeekWindow? {
        let r = range
        guard top < r.lowerBound + Self.margin || top > r.upperBound - Self.margin else { return nil }
        return WeekWindow(center: top)
    }
}

/// Events bucketed by day once per change, so month cells are a dictionary lookup instead of a
/// filter + sort over every event per cell per render.
struct DayEventIndex {
    typealias Day = (allDay: [CalEvent], timed: [CalEvent])
    private var buckets: [Date: Day] = [:]
    private let cal: Calendar
    private static let maxSpanDays = 400

    init(events: [CalEvent], cal: Calendar) {
        self.cal = cal
        var all: [Date: [CalEvent]] = [:], timed: [Date: [CalEvent]] = [:]
        for e in events {
            // Same overlap rule the per-day filter used: a zero-length event still occupies its day.
            let effEnd = max(e.end, e.start.addingTimeInterval(1))
            var d = cal.startOfDay(for: e.start)
            var n = 0
            while d < effEnd, n < Self.maxSpanDays {
                if e.isAllDay { all[d, default: []].append(e) } else { timed[d, default: []].append(e) }
                d = cal.date(byAdding: .day, value: 1, to: d)!
                n += 1
            }
        }
        for k in Set(all.keys).union(timed.keys) {
            buckets[k] = (all[k, default: []].sorted { $0.start < $1.start },
                          timed[k, default: []].sorted { $0.start < $1.start })
        }
    }

    func events(on day: Date) -> Day {
        buckets[cal.startOfDay(for: day)] ?? ([], [])
    }
}
