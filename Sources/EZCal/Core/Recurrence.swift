import Foundation
import EventKit

/// Pure recurrence logic (issue #3): which occurrences an edit/delete applies to, and how that
/// maps onto EventKit's `EKSpan` and Google's instance/master event ids + RRULE. Kept dependency-free
/// (no network, no EKEventStore calls) so it's fully unit-testable — see Tests/EZCalTests/RecurrenceTests.swift.

/// The three choices offered whenever the user edits or deletes an occurrence of a recurring event.
enum RecurrenceScope: String, CaseIterable, Identifiable, Sendable, Hashable {
    case thisEvent, thisAndFollowing, all
    var id: String { rawValue }

    var title: String {
        switch self {
        case .thisEvent: return "This event"
        case .thisAndFollowing: return "This and following events"
        case .all: return "All events"
        }
    }

    var detail: String {
        switch self {
        case .thisEvent: return "Only this occurrence changes."
        case .thisAndFollowing: return "This and every later occurrence changes."
        case .all: return "Every occurrence in the series changes."
        }
    }

    /// EventKit only distinguishes two spans; "this and following" and "all" both mean "from here on"
    /// unless applied to the first occurrence, in which case `.futureEvents` already covers the whole series.
    var ekSpan: EKSpan { self == .thisEvent ? .thisEvent : .futureEvents }

    // MARK: Google mapping

    /// What a Google Calendar delete should target for a given scope.
    /// `recurringEventId` is the parent series id Google puts on every expanded instance; the instance
    /// itself is its own id, and a bare (unexpanded) master's own id doubles as the series id.
    enum GoogleDeleteTarget: Equatable {
        case instance(eventId: String)
        case series(eventId: String)
        case truncateSeries(masterEventId: String)
    }

    static func googleDeleteTarget(scope: RecurrenceScope, eventId: String, recurringEventId: String?) -> GoogleDeleteTarget {
        let masterId = recurringEventId ?? eventId
        switch scope {
        case .thisEvent: return .instance(eventId: eventId)
        case .all: return .series(eventId: masterId)
        case .thisAndFollowing: return .truncateSeries(masterEventId: masterId)
        }
    }

    /// What a Google Calendar patch (edit) should target for a given scope.
    enum GooglePatchTarget: Equatable {
        case instance(eventId: String)
        case series(eventId: String)
        /// Truncate the master's RRULE to end before this occurrence, then insert a new series
        /// starting here with the edited fields (a "split").
        case splitSeries(masterEventId: String)
    }

    static func googlePatchTarget(scope: RecurrenceScope, eventId: String, recurringEventId: String?) -> GooglePatchTarget {
        let masterId = recurringEventId ?? eventId
        switch scope {
        case .thisEvent: return .instance(eventId: eventId)
        case .all: return .series(eventId: masterId)
        case .thisAndFollowing: return .splitSeries(masterEventId: masterId)
        }
    }
}

/// Which action a `RecurrenceScope` choice is for — drives the sheet's title and button label.
enum RecurrenceAction: String, Sendable, Equatable {
    case edit, delete
    var noun: String { self == .edit ? "Edit" : "Delete" }
}

/// RFC 5545 RRULE editing, used to truncate a series when a "this and following" edit/delete splits it.
enum RecurrenceRule {
    /// Sets (or replaces) `UNTIL` on every `RRULE` line so the series ends just before `cutoff`,
    /// dropping any existing `UNTIL`/`COUNT` (a rule can't have both `UNTIL` and `COUNT`).
    /// Non-`RRULE` lines (e.g. `EXDATE`) pass through unchanged.
    static func truncated(_ rrules: [String], before cutoff: Date) -> [String] {
        let untilString = untilFormatter.string(from: cutoff.addingTimeInterval(-1))
        return rrules.map { rule in
            guard rule.uppercased().hasPrefix("RRULE") else { return rule }
            var parts = rule.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
            parts.removeAll { $0.uppercased().hasPrefix("UNTIL=") || $0.uppercased().hasPrefix("COUNT=") }
            parts.append("UNTIL=\(untilString)")
            return parts.joined(separator: ";")
        }
    }

    /// UTC date-time form (`20260921T090000Z`), valid per RFC 5545 for timed events regardless of the
    /// event's own timezone. All-day (`VALUE=DATE`) series aren't split correctly by this — a known limitation.
    private static let untilFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

/// "Nice to have" recurrence picker shown when creating a new event.
enum RecurrenceOption: String, CaseIterable, Identifiable, Sendable, Hashable {
    case none, daily, weekly, monthly, weekdays
    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "Doesn't repeat"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .weekdays: return "Every weekday"
        }
    }

    /// Google Calendar `recurrence` RRULE line, or nil for a one-off event.
    var rrule: String? {
        switch self {
        case .none: return nil
        case .daily: return "RRULE:FREQ=DAILY"
        case .weekly: return "RRULE:FREQ=WEEKLY"
        case .monthly: return "RRULE:FREQ=MONTHLY"
        case .weekdays: return "RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"
        }
    }

    /// EventKit equivalent, for events created on an iCloud/Apple calendar.
    var ekRule: EKRecurrenceRule? {
        switch self {
        case .none: return nil
        case .daily: return EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
        case .weekly: return EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
        case .monthly: return EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, end: nil)
        case .weekdays:
            let weekdays: [EKWeekday] = [.monday, .tuesday, .wednesday, .thursday, .friday]
            let days = weekdays.map { EKRecurrenceDayOfWeek(dayOfTheWeek: $0, weekNumber: 0) }
            return EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, daysOfTheWeek: days,
                                    daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil,
                                    daysOfTheYear: nil, setPositions: nil, end: nil)
        }
    }
}
