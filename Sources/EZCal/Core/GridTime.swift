import Foundation

/// Wall-clock <-> grid-position math for the day/week time grids.
///
/// The grid always draws 24 equal hour rows labeled 0-23, so a y position must come from the *wall clock*
/// (hour/minute in the calendar's time zone), never from elapsed seconds since midnight: on a 25-hour
/// fall-back day or a 23-hour spring-forward day, elapsed time is an hour off for everything after the change.
///
/// Conventions on a change day:
/// - Spring forward: wall 2:00-2:59 doesn't exist. Nothing lands there; the row stays empty and an event
///   spanning the gap is drawn from its start wall time to its end wall time (so it covers the empty row).
/// - Fall back: wall 1:00-1:59 happens twice. Both occurrences map onto the same 1 AM row; an event spanning
///   the repeat is drawn by wall time (so shorter than its real length, never negative).
enum GridTime {
    /// Wall-clock minutes of `date` relative to the start of `day` (in `cal`'s zone). 0..<1440 for dates on `day`;
    /// negative / >= 1440 for other days (a whole number of days is added per calendar day of difference).
    static func minutes(of date: Date, on day: Date, cal: Calendar) -> Double {
        let c = cal.dateComponents([.hour, .minute, .second], from: date)
        let wall = Double((c.hour ?? 0) * 60 + (c.minute ?? 0)) + Double(c.second ?? 0) / 60
        let dayDelta = cal.dateComponents([.day], from: cal.startOfDay(for: day), to: cal.startOfDay(for: date)).day ?? 0
        return Double(dayDelta * 1440) + wall
    }

    /// Height in minutes of a block from `start` to `end`, by wall clock; never negative.
    static func durationMinutes(from start: Date, to end: Date, cal: Calendar) -> Double {
        max(minutes(of: end, on: start, cal: cal) - minutes(of: start, on: start, cal: cal), 0)
    }

    /// y offset of `date` in a grid for `day` that is `hourHeight` points per hour row.
    static func y(of date: Date, on day: Date, hourHeight: Double, cal: Calendar) -> Double {
        minutes(of: date, on: day, cal: cal) / 60 * hourHeight
    }

    /// Height of the block from `start` to `end`.
    static func height(from start: Date, to end: Date, hourHeight: Double, cal: Calendar) -> Double {
        durationMinutes(from: start, to: end, cal: cal) / 60 * hourHeight
    }

    /// The instant whose wall-clock time is `minutes` after midnight of `day` (may be negative or >= 1440 to reach
    /// neighbouring days). A wall time inside the spring-forward gap resolves to the first instant after it;
    /// an ambiguous fall-back time resolves to its first occurrence.
    static func date(minutes: Int, on day: Date, cal: Calendar) -> Date {
        let dayOffset = Int((Double(minutes) / 1440).rounded(.down))
        let rem = minutes - dayOffset * 1440
        let base = cal.startOfDay(for: day)
        let target = dayOffset == 0 ? base : (cal.date(byAdding: .day, value: dayOffset, to: base) ?? base)
        return cal.date(bySettingHour: rem / 60, minute: rem % 60, second: 0, of: target,
                        matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward) ?? target
    }

    /// Instant at grid offset `y` (rounded to the nearest minute) in the column for `day`.
    static func date(atY y: Double, on day: Date, hourHeight: Double, cal: Calendar) -> Date {
        date(minutes: Int((y / hourHeight * 60).rounded()), on: day, cal: cal)
    }

    /// `date` moved by `delta` wall-clock minutes (what a drag of that many grid minutes means), keeping the
    /// seconds component. Differs from adding elapsed minutes only across a DST change.
    static func shifted(_ date: Date, byWallMinutes delta: Int, cal: Calendar) -> Date {
        let sod = cal.startOfDay(for: date)
        let c = cal.dateComponents([.hour, .minute, .second], from: date)
        let wall = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        let moved = self.date(minutes: wall + delta, on: sod, cal: cal)
        return moved.addingTimeInterval(Double(c.second ?? 0))
    }
}
