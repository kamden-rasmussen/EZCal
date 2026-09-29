import Foundation

/// Pure math behind the continuously scrolling Week / Work Week grid (`Views/WeekScrollView.swift`).
/// Foundation-only so it is unit-testable (`WeekScrollMathTests`) and compiles for iOS too.
///
/// The grid is a horizontal strip of "column days". Which calendar days get a column is decided by a
/// `ColumnRule`; weekend days that the rule hides are simply absent from the strip (the scroll runs through
/// work days only), so a work week is always 5 adjacent columns.
enum WeekScrollMath {
    enum ColumnRule: Equatable {
        case all            // every day (Week view with weekends shown)
        case localeWeekdays // hide the locale's weekend days (Week view with "show weekends" off)
        case monFri         // Monday through Friday only (Work Week)

        func includes(_ day: Date, cal: Calendar) -> Bool {
            switch self {
            case .all: return true
            case .localeWeekdays: return !cal.isDateInWeekend(day)
            case .monFri: return (2...6).contains(cal.component(.weekday, from: day))
            }
        }
    }

    /// `start` (as a start-of-day) if it gets a column, else the next day that does.
    static func firstColumnDay(onOrAfter start: Date, rule: ColumnRule, cal: Calendar) -> Date {
        var d = cal.startOfDay(for: start)
        var attempts = 0
        while !rule.includes(d, cal: cal), attempts < 8 {
            d = cal.date(byAdding: .day, value: 1, to: d)!
            attempts += 1
        }
        return d
    }

    /// The column day `n` columns after (n > 0) or before (n < 0) `day`, skipping hidden days.
    static func shift(_ day: Date, byColumns n: Int, rule: ColumnRule, cal: Calendar) -> Date {
        var d = cal.startOfDay(for: day)
        guard n != 0 else { return d }
        let step = n > 0 ? 1 : -1
        var remaining = abs(n)
        while remaining > 0 {
            d = cal.date(byAdding: .day, value: step, to: d)!
            if rule.includes(d, cal: cal) { remaining -= 1 }
        }
        return d
    }

    /// `count` consecutive column days beginning at the first column day on or after `start`.
    static func columnDays(from start: Date, count: Int, rule: ColumnRule, cal: Calendar) -> [Date] {
        guard count > 0 else { return [] }
        var out = [firstColumnDay(onOrAfter: start, rule: rule, cal: cal)]
        while out.count < count { out.append(shift(out[out.count - 1], byColumns: 1, rule: rule, cal: cal)) }
        return out
    }

    /// A lazy window of column days: `before` columns before `center`, `center` itself, `after` columns after.
    static func window(around center: Date, before: Int, after: Int, rule: ColumnRule, cal: Calendar) -> [Date] {
        let c = firstColumnDay(onOrAfter: center, rule: rule, cal: cal)
        let b = max(before, 0), a = max(after, 0)
        var out = [shift(c, byColumns: -b, rule: rule, cal: cal)]
        for _ in 0..<(b + a) {
            out.append(shift(out[out.count - 1], byColumns: 1, rule: rule, cal: cal))
        }
        return out
    }

    /// Grows `days` when the leading column gets within `thresholdColumns` of either end, so scrolling never
    /// dead-ends. Returns nil when no growth is needed. `prepended` is how many columns were added in front
    /// (the caller must re-anchor the scroll position when that is nonzero).
    static func extended(_ days: [Date], leadingIndex: Int, visibleCount: Int, thresholdColumns: Int,
                         chunk: Int, rule: ColumnRule, cal: Calendar) -> (days: [Date], prepended: Int)? {
        guard let first = days.first, let last = days.last, chunk > 0 else { return nil }
        var result = days
        var prepended = 0
        if leadingIndex < thresholdColumns {
            var front: [Date] = []
            var d = first
            for _ in 0..<chunk { d = shift(d, byColumns: -1, rule: rule, cal: cal); front.append(d) }
            result = front.reversed() + result
            prepended = chunk
        }
        if leadingIndex + visibleCount + thresholdColumns > days.count {
            var d = last
            for _ in 0..<chunk { d = shift(d, byColumns: 1, rule: rule, cal: cal); result.append(d) }
        }
        return result.count == days.count ? nil : (result, prepended)
    }

    /// Column index nearest the viewport's leading edge for a horizontal scroll `offset` (rounded, so the
    /// anchor flips at the halfway point between two snap positions).
    static func leadingIndex(offset: CGFloat, colWidth: CGFloat, count: Int) -> Int {
        guard colWidth > 0, count > 0 else { return 0 }
        return min(max(Int((offset / colWidth).rounded()), 0), count - 1)
    }

    /// Column indices that intersect a viewport of `viewport` points at `offset`, plus `overscan` each side.
    static func visibleIndices(offset: CGFloat, colWidth: CGFloat, viewport: CGFloat, count: Int, overscan: Int) -> ClosedRange<Int>? {
        guard colWidth > 0, count > 0 else { return nil }
        let lo = max(Int((offset / colWidth).rounded(.down)) - overscan, 0)
        let hi = min(Int(((offset + viewport) / colWidth).rounded(.up)) - 1 + overscan, count - 1)
        return lo <= hi ? lo...hi : nil
    }

    /// Events are fetched for the visible days plus `bufferDays` of calendar days on each side.
    static func fetchRange(visible days: [Date], bufferDays: Int, cal: Calendar) -> Range<Date> {
        guard let f = days.first, let l = days.last else { let n = Date(); return n..<n }
        let lo = cal.date(byAdding: .day, value: -bufferDays, to: cal.startOfDay(for: f))!
        let hi = cal.date(byAdding: .day, value: bufferDays, to: cal.endOfDay(l))!
        return lo..<hi
    }

    /// Whether scrolling has approached the edge of what was fetched and events should be reloaded.
    static func needsReload(visible: Range<Date>, loaded: Range<Date>?, margin: TimeInterval) -> Bool {
        guard let loaded else { return true }
        return visible.lowerBound < loaded.lowerBound.addingTimeInterval(margin)
            || visible.upperBound > loaded.upperBound.addingTimeInterval(-margin)
    }

    /// Short hops animate; long jumps (Today from months away) would whip through the lazy strip, so they cut.
    static func shouldAnimate(columns: Int) -> Bool { abs(columns) <= 21 }

    /// Screen x (relative to the grid's leading edge) of column `index` at scroll `offset`. The header strip and
    /// the day grid both use this geometry, so a header date sits exactly above its column at rest and mid-pan.
    static func columnX(index: Int, colWidth: CGFloat, offset: CGFloat) -> CGFloat {
        CGFloat(index) * colWidth - offset
    }
}
