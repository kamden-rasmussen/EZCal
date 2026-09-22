import Foundation

/// Working hours considered when searching for a shared slot.
///
/// Issue #5 (working-hours settings) will supply a user-configured value through this same type;
/// until it lands every caller here uses `.default` (9:00–18:00). Keeping it as a plain injectable
/// parameter (rather than reading `AppSettings` directly) means `SlotFinder` never has to change
/// once that setting exists.
struct WorkingHours: Sendable, Equatable {
    var startHour: Int
    var endHour: Int

    static let `default` = WorkingHours(startHour: 9, endHour: 18)

    init(startHour: Int = 9, endHour: Int = 18) {
        self.startHour = startHour
        self.endHour = endHour
    }
}

/// One attendee's availability at a candidate slot.
struct SlotAttendeeStatus: Sendable, Equatable {
    let email: String
    let busy: Bool
    /// True when this person's calendar isn't visible to us at all. Unknown attendees are shown
    /// to the user but never keep a slot out of the results.
    let unknown: Bool
}

/// A candidate meeting time, with each requested attendee's availability at that time.
struct TimeSlot: Identifiable, Sendable, Equatable {
    let start: Date
    let end: Date
    let attendees: [SlotAttendeeStatus]

    var id: Date { start }
    var unknownCount: Int { attendees.filter(\.unknown).count }
}

/// Pure scheduling logic for "find a time for coworkers". No I/O, no SwiftUI — takes busy ranges
/// that the caller already fetched (via `GoogleAPI.freeBusy` / `CalendarStore.busyRanges`) and
/// returns candidate slots where nobody with *known* availability is busy.
enum SlotFinder {
    /// Finds candidate meeting slots across `days`.
    ///
    /// - Parameters:
    ///   - emails: attendees to check, in display order. The organizer isn't included here — pass
    ///     their own events via `myBusy` since those are always known and should always block a slot.
    ///   - busy: per-email busy ranges, as returned by `GoogleAPI.freeBusy`. A missing key or a
    ///     `nil` value both mean "not visible to us" (unknown), never "free all day".
    ///   - myBusy: the organizer's own busy ranges. Always known, so it does block candidate slots.
    ///   - duration: meeting length in seconds. Non-positive durations produce no results.
    ///   - days: the calendar days to search; only the day component of each date is used.
    ///   - workingHours: the window of each day to search within.
    ///   - granularity: spacing between candidate start times.
    ///   - limit: maximum number of slots returned.
    ///   - calendar: used to compute each day's working-hours window.
    /// - Returns: slots where every known attendee (and the organizer) is free, sorted with the
    ///   fewest unknown attendees first, then earliest first. Attendees whose availability is
    ///   unknown are reported on the slot (`unknown: true`) but never exclude it.
    static func findSlots(
        emails: [String],
        busy: [String: [Range<Date>]?],
        myBusy: [Range<Date>],
        duration: TimeInterval,
        days: [Date],
        workingHours: WorkingHours = .default,
        granularity: TimeInterval = 15 * 60,
        limit: Int = 40,
        calendar: Calendar = .current
    ) -> [TimeSlot] {
        guard duration > 0, granularity > 0 else { return [] }

        var out: [TimeSlot] = []
        for day in days {
            guard let dayStart = calendar.date(bySettingHour: workingHours.startHour, minute: 0, second: 0, of: day),
                  let dayEnd = calendar.date(bySettingHour: workingHours.endHour, minute: 0, second: 0, of: day),
                  dayStart < dayEnd else { continue }

            var t = dayStart
            while t.addingTimeInterval(duration) <= dayEnd {
                let slot = t..<t.addingTimeInterval(duration)
                defer { t = t.addingTimeInterval(granularity) }

                if myBusy.contains(where: { $0.overlaps(slot) }) { continue }

                var statuses: [SlotAttendeeStatus] = []
                var blocked = false
                for email in emails {
                    guard let ranges = busy[email] ?? nil else {
                        statuses.append(SlotAttendeeStatus(email: email, busy: false, unknown: true))
                        continue
                    }
                    let isBusy = ranges.contains { $0.overlaps(slot) }
                    if isBusy { blocked = true }
                    statuses.append(SlotAttendeeStatus(email: email, busy: isBusy, unknown: false))
                }
                guard !blocked else { continue }
                out.append(TimeSlot(start: slot.lowerBound, end: slot.upperBound, attendees: statuses))
            }
        }

        out.sort { a, b in
            if a.unknownCount != b.unknownCount { return a.unknownCount < b.unknownCount }
            return a.start < b.start
        }
        return Array(out.prefix(limit))
    }
}
