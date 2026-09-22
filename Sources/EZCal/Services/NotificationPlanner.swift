import Foundation

/// One meeting reminder EZCal wants pending. Pure data — no UNUserNotificationCenter here, so "which
/// events get which triggers" can be unit tested without touching notification permissions or the
/// system notification center. See NotificationService.swift for the UNUserNotificationCenter side.
struct PlannedNotification: Equatable, Sendable {
    /// Stable across replans for the same event start + lead time, so rescheduling after a refresh
    /// replaces a still-pending request instead of duplicating it, and so a request whose id no longer
    /// appears in a fresh plan (event deleted, declined, or moved) can be identified and dropped.
    let id: String
    let eventID: String
    let title: String
    let body: String
    let fireDate: Date
    let hasJoinLink: Bool
    let joinURLString: String?
}

enum NotificationPlanner {
    /// Builds the set of reminders that should be pending right now for `events`, given the user's
    /// notification settings. `now` is injected so this is deterministic in tests.
    static func plan(events: [CalEvent], now: Date, leadMinutes: Int, videoOnly: Bool) -> [PlannedNotification] {
        events
            .filter { !$0.isAllDay && !$0.isDeclined }
            .filter { !videoOnly || $0.meetingURL != nil }
            .compactMap { event -> PlannedNotification? in
                // Already started (or over): nothing useful to remind about.
                guard now < event.start else { return nil }
                // Clamp to "now + a beat" so an event closer than the lead time (app just launched,
                // or was offline) still gets an immediate reminder instead of none at all.
                let fireDate = max(event.start.addingTimeInterval(-Double(leadMinutes) * 60),
                                   now.addingTimeInterval(1))
                let leadText = leadMinutes == 1 ? "1 minute" : "\(leadMinutes) minutes"
                var body = "Starts in \(leadText)"
                if !event.location.isEmpty { body += " · \(event.location)" }
                return PlannedNotification(
                    id: identifier(for: event, leadMinutes: leadMinutes),
                    eventID: event.id,
                    title: event.title.isEmpty ? "Untitled event" : event.title,
                    body: body,
                    fireDate: fireDate,
                    hasJoinLink: event.meetingURL != nil,
                    joinURLString: event.meetingURL?.absoluteString)
            }
    }

    /// Deterministic id for one (event start, lead time) pair. Prefixed so NotificationService can tell
    /// our own pending requests apart from anything else that might use the shared notification center.
    static func identifier(for event: CalEvent, leadMinutes: Int) -> String {
        "meeting|\(event.uid)|\(Int(event.start.timeIntervalSince1970))|\(leadMinutes)"
    }
}
