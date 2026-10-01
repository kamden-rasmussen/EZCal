import Foundation

extension CalendarStore {
    /// `proposed` minus anyone already on the event (case-insensitive by email), without duplicates.
    nonisolated static func newGuests(_ proposed: [Attendee], existing: [Attendee]) -> [Attendee] {
        var seen = Set(existing.map { $0.email.lowercased() })
        return proposed.filter { seen.insert($0.email.lowercased()).inserted }
    }

    /// Detail-panel quick add: PATCHes only the guest list (this occurrence, for a recurring event), so
    /// no trip through the editor. Invitations go out immediately, the same as saving the editor does.
    func addGuests(_ people: [Attendee], to e: CalEvent) async throws {
        let fresh = Self.newGuests(people, existing: e.attendees)
        guard !fresh.isEmpty else { return }
        if isDemo {
            eventsBySource[e.sourceId] = (eventsBySource[e.sourceId] ?? []).map { ev in
                guard ev.id == e.id else { return ev }
                var n = ev; n.attendees += fresh; return n
            }
            rebuildDisplay()
        } else {
            let body: [String: Any] = ["attendees": Self.attendeeBody(e.attendees + fresh, existing: true)]
            try await GoogleAPI(accountId: e.accountId).patchEvent(calendarId: e.calendarId, eventId: e.eventId, body: body)
            await reload()
            await refreshUpcoming()
        }
        // The open panel holds a copy of the event; swap in the refreshed one so the new guests show.
        if case .detail(let cur) = sheet, let updated = displayEvents.first(where: { $0.id == cur.id }) {
            sheet = .detail(updated)
        }
    }
}
