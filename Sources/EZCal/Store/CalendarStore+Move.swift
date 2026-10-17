import Foundation

/// How saving an edited event onto a different calendar is carried out (issue #78).
enum EventMove: Equatable {
    /// Same calendar; an ordinary edit.
    case none
    /// Both calendars are in Calendar/EventKit: reassign `EKEvent.calendar`.
    case eventKit
    /// Same Google account: Google's `events.move` keeps the event id, guests and Meet link.
    case googleMove
    /// Different account or provider (Google <-> Apple, or two Google accounts): create the event in the
    /// destination, then delete the original. Guests, Meet links and Google-only fields don't carry over.
    case recreate
    /// Not offered (recurring series, events you don't own, read-only destination).
    case unsupported

    static func plan(from e: CalEvent, to dest: Source) -> EventMove {
        if dest.id == e.sourceId { return .none }
        guard dest.canWrite, dest.kind == .calendar, !dest.isICS else { return .unsupported }
        // Moving a series (or one occurrence of it) across calendars isn't supported.
        guard !e.isRecurring, e.canEdit, !e.isOverlay, !e.isBusyOnly else { return .unsupported }
        if e.isEventKit && dest.isEventKit { return .eventKit }
        // Someone else's Google event can't be moved or re-created as ours.
        if !e.isEventKit && !e.isOrganizer { return .unsupported }
        if !e.isEventKit && !dest.isEventKit && e.accountId == dest.accountId { return .googleMove }
        return .recreate
    }

    /// Calendars the editor should offer for an existing event (includes its current one).
    static func destinations(for e: CalEvent, in sources: [Source]) -> [Source] {
        sources.filter { $0.canWrite && plan(from: e, to: $0) != .unsupported }
    }
}
