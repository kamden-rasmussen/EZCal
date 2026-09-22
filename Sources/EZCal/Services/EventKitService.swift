import Foundation
import EventKit
import AppKit

/// Reads/writes calendars that macOS already syncs (iCloud, Exchange, Fastmail, CalDAV, "On My Mac"…).
/// Accounts are managed in System Settings → Internet Accounts; EZCal just gets permission to see them.
final class EventKitService: @unchecked Sendable {
    static let shared = EventKitService()
    let store = EKEventStore()

    var isAuthorized: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    // MARK: Calendars

    func sources() -> [Source] {
        store.calendars(for: .event).map { c in
            Source(id: "ek|\(c.calendarIdentifier)",
                   accountId: "ek:\(c.source?.title ?? "On My Mac")",
                   calendarId: c.calendarIdentifier,
                   name: c.title,
                   colorHex: Self.hex(c.cgColor),
                   kind: .calendar,
                   accessRole: c.allowsContentModifications ? "owner" : "reader")
        }
    }

    func isBirthdayCalendar(_ id: String) -> Bool {
        store.calendar(withIdentifier: id)?.type == .birthday
    }

    private static func hex(_ cg: CGColor?) -> String {
        guard let cg, let c = NSColor(cgColor: cg)?.usingColorSpace(.sRGB) else { return "#4285F4" }
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }

    // MARK: Events

    func events(for s: Source, range: Range<Date>) -> [CalEvent] {
        guard let cal = store.calendar(withIdentifier: s.calendarId) else { return [] }
        let pred = store.predicateForEvents(withStart: range.lowerBound, end: range.upperBound, calendars: [cal])
        return store.events(matching: pred).compactMap { Self.map($0, source: s) }
    }

    static func map(_ e: EKEvent, source: Source) -> CalEvent? {
        guard e.status != .canceled, let start = e.startDate, let rawEnd = e.endDate else { return nil }
        let c = Calendar.current
        // EventKit's all-day end is the last day; the rest of the app uses an exclusive end.
        let end = e.isAllDay ? c.date(byAdding: .day, value: 1, to: c.startOfDay(for: rawEnd))! : rawEnd

        let attendees = (e.attendees ?? []).map { p -> Attendee in
            let email = p.url.absoluteString.replacingOccurrences(of: "mailto:", with: "")
            let response: String
            switch p.participantStatus {
            case .accepted: response = "accepted"
            case .declined: response = "declined"
            case .tentative: response = "tentative"
            default: response = "needsAction"
            }
            return Attendee(email: email, name: p.name, response: response, isSelf: p.isCurrentUser,
                            isOrganizer: p.participantRole == .chair, isResource: p.participantType == .resource,
                            isOptional: p.participantRole == .optional)
        }
        let me = attendees.first { $0.isSelf }
        let location = e.location ?? ""
        let notes = e.notes ?? ""
        let eventId = e.eventIdentifier ?? UUID().uuidString

        return CalEvent(
            id: "\(source.id)|\(eventId)|\(start.timeIntervalSince1970)", eventId: eventId,
            sourceId: source.id, calendarId: source.calendarId, accountId: source.accountId,
            uid: e.calendarItemExternalIdentifier ?? eventId,
            title: (e.title?.isEmpty == false ? e.title! : "(No title)"),
            start: start, end: end, isAllDay: e.isAllDay,
            location: location, notes: notes, attendees: attendees,
            htmlLink: nil,
            meetingURL: MeetingLink.find(in: [location, notes, e.url?.absoluteString ?? ""]),
            colorHex: source.colorHex, sourceName: source.name,
            ownerName: nil, isOverlay: false, canEdit: source.canWrite,
            isBusyOnly: false, isRecurring: e.hasRecurrenceRules,
            zoomMeetingID: nil,
            isTentative: e.availability == .tentative || me?.response == "tentative",
            isDeclined: me?.response == "declined"
        )
    }

    /// Recurring occurrences share an identifier, so match on start time too.
    private func find(_ event: CalEvent) -> EKEvent? {
        guard let cal = store.calendar(withIdentifier: event.calendarId) else { return nil }
        let pred = store.predicateForEvents(withStart: event.start.addingTimeInterval(-60),
                                            end: event.end.addingTimeInterval(60), calendars: [cal])
        return store.events(matching: pred).first {
            $0.eventIdentifier == event.eventId && abs($0.startDate.timeIntervalSince(event.start)) < 1
        }
    }

    // MARK: Writes

    /// `notes == nil` leaves the existing notes untouched. For all-day events `end` is the inclusive last day.
    func save(existing: CalEvent?, calendarId: String, title: String, start: Date, end: Date,
              allDay: Bool, location: String, notes: String?) throws {
        let ev: EKEvent
        if let existing {
            guard let found = find(existing) else { throw APIError.invalid("That event no longer exists in Calendar.") }
            ev = found
        } else {
            guard let cal = store.calendar(withIdentifier: calendarId) else { throw APIError.invalid("Calendar not found.") }
            ev = EKEvent(eventStore: store)
            ev.calendar = cal
        }
        ev.title = title.isEmpty ? "New Event" : title
        ev.isAllDay = allDay
        ev.startDate = start
        ev.endDate = end
        ev.location = location.isEmpty ? nil : location
        if let notes { ev.notes = notes.isEmpty ? nil : notes }
        try store.save(ev, span: .thisEvent, commit: true)
    }

    func delete(_ event: CalEvent) throws {
        guard let ev = find(event) else { return }
        try store.remove(ev, span: .thisEvent, commit: true)
    }
}
