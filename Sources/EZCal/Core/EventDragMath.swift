import Foundation

/// Pure snap/time math for dragging (or keyboard-nudging) events on the time grid. Kept free of SwiftUI so
/// it's easy to unit test; the gestures themselves live in `EventBlock` (`Views/TimeGridView.swift`), and the
/// save/rollback side lives in `Store/EventDrag.swift`.
enum EventDragMath {
    /// Rounds a raw minute offset to the nearest `step` minutes (15 by default).
    static func snap(minutes: Double, step: Int = 15) -> Int {
        guard step > 0 else { return Int(minutes.rounded()) }
        return Int((minutes / Double(step)).rounded()) * step
    }

    /// New (start, end) after moving the whole block by `minutesDelta` minutes and `dayDelta` days, keeping
    /// the original duration.
    static func moved(start: Date, end: Date, minutesDelta: Int, dayDelta: Int, cal: Calendar) -> (start: Date, end: Date) {
        let duration = end.timeIntervalSince(start)
        var newStart = cal.date(byAdding: .minute, value: minutesDelta, to: start) ?? start
        if dayDelta != 0 { newStart = cal.date(byAdding: .day, value: dayDelta, to: newStart) ?? newStart }
        return (newStart, newStart.addingTimeInterval(duration))
    }

    /// New (start, end) after dragging the bottom edge by `minutesDelta` minutes. `start` never moves;
    /// `end` is clamped so the event is always at least `minimumMinutes` long.
    static func resized(start: Date, end: Date, minutesDelta: Int, minimumMinutes: Int = 15, cal: Calendar) -> (start: Date, end: Date) {
        let candidate = cal.date(byAdding: .minute, value: minutesDelta, to: end) ?? end
        let minEnd = cal.date(byAdding: .minute, value: minimumMinutes, to: start) ?? end
        return (start, max(candidate, minEnd))
    }
}
