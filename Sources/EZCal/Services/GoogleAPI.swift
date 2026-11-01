import Foundation

// MARK: - Wire types (all optional so decoding is lenient)

struct GCalListResponse: Decodable {
    var items: [GCalListItem]?
    var nextPageToken: String?
}
struct GCalListItem: Decodable {
    var id: String
    var summary: String?
    var summaryOverride: String?
    var backgroundColor: String?
    var accessRole: String?
    var primary: Bool?
    var selected: Bool?
    var deleted: Bool?
}

struct GEventList: Decodable {
    var items: [GEvent]?
    var nextPageToken: String?
}
struct GEvent: Decodable {
    var id: String?
    var status: String?
    var summary: String?
    var description: String?
    var location: String?
    var htmlLink: String?
    var hangoutLink: String?
    var iCalUID: String?
    var recurringEventId: String?
    var visibility: String?     // default, public, private (or confidential)
    var recurrence: [String]?   // RRULE/EXDATE lines; only present on a master (unexpanded) event
    var start: GTime?
    var end: GTime?
    var attendees: [GAttendee]?
    var organizer: GOrganizer?
    var guestsCanModify: Bool?
    var guestsCanInviteOthers: Bool?
    var conferenceData: GConference?
    var extendedProperties: GExtProps?
    var reminders: GReminders?
}
struct GReminders: Decodable {
    struct Override: Decodable { var method: String?; var minutes: Int? }
    var useDefault: Bool?
    var overrides: [Override]?
}
struct GTime: Decodable {
    var date: String?
    var dateTime: String?
}
struct GOrganizer: Decodable {
    var isSelf: Bool?
    enum CodingKeys: String, CodingKey { case isSelf = "self" }
}
struct GAttendee: Decodable {
    var email: String?
    var displayName: String?
    var responseStatus: String?
    var isSelf: Bool?
    var organizer: Bool?
    var resource: Bool?
    var optional: Bool?
    enum CodingKeys: String, CodingKey {
        case email, displayName, responseStatus, organizer, resource, optional
        case isSelf = "self"
    }
}
struct GConference: Decodable {
    var entryPoints: [GEntryPoint]?
}
struct GEntryPoint: Decodable {
    var entryPointType: String?
    var uri: String?
}
struct GExtProps: Decodable {
    var `private`: [String: String]?
}

struct GFreeBusy: Decodable {
    struct Cal: Decodable {
        struct Slot: Decodable { var start: String; var end: String }
        struct Err: Decodable { var reason: String? }
        var busy: [Slot]?
        var errors: [Err]?
    }
    var calendars: [String: Cal]?
}

struct GPeopleResponse: Decodable {
    struct P: Decodable {
        struct Name: Decodable { var displayName: String? }
        struct Email: Decodable { var value: String? }
        struct Photo: Decodable { var url: String? }
        var names: [Name]?
        var emailAddresses: [Email]?
        var photos: [Photo]?
    }
    var people: [P]?
}

// MARK: - Client

struct GoogleAPI: Sendable {
    let accountId: String
    static let calendarBase = "https://www.googleapis.com/calendar/v3"

    static func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~@"))) ?? s
    }

    func data(_ method: String, _ url: URL, json: Any? = nil) async throws -> Data {
        for attempt in 0..<2 {
            let token = try await TokenManager.shared.accessToken(for: .google(accountId), force: attempt > 0)
            var req = URLRequest(url: url)
            req.httpMethod = method
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let json {
                req.httpBody = try JSONSerialization.data(withJSONObject: json)
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            let (d, r) = try await URLSession.shared.data(for: req)
            let status = (r as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 && attempt == 0 { continue }
            guard (200..<300).contains(status) else { throw APIError.http(status, Self.message(d)) }
            return d
        }
        throw APIError.notSignedIn
    }

    static func message(_ d: Data) -> String {
        if let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
           let e = j["error"] as? [String: Any], let m = e["message"] as? String { return m }
        return String(data: d, encoding: .utf8)?.prefix(200).description ?? "Unknown error"
    }

    // MARK: Calendar list

    func calendarList() async throws -> [GCalListItem] {
        var all: [GCalListItem] = []
        var token: String?
        repeat {
            var c = URLComponents(string: "\(Self.calendarBase)/users/me/calendarList")!
            c.queryItems = [.init(name: "maxResults", value: "250")] + (token.map { [.init(name: "pageToken", value: $0)] } ?? [])
            let list = try JSONDecoder().decode(GCalListResponse.self, from: try await data("GET", c.url!))
            all += (list.items ?? []).filter { $0.deleted != true }
            token = list.nextPageToken
        } while token != nil
        return all
    }

    // MARK: Events

    func events(calendarId: String, range: Range<Date>) async throws -> [GEvent] {
        var all: [GEvent] = []
        var token: String?
        repeat {
            var c = URLComponents(string: "\(Self.calendarBase)/calendars/\(Self.enc(calendarId))/events")!
            var items: [URLQueryItem] = [
                .init(name: "singleEvents", value: "true"),
                .init(name: "orderBy", value: "startTime"),
                .init(name: "maxResults", value: "2500"),
                .init(name: "timeMin", value: RFC3339.string(range.lowerBound)),
                .init(name: "timeMax", value: RFC3339.string(range.upperBound)),
            ]
            if let token { items.append(.init(name: "pageToken", value: token)) }
            c.queryItems = items
            let list = try JSONDecoder().decode(GEventList.self, from: try await data("GET", c.url!))
            all += list.items ?? []
            token = list.nextPageToken
        } while token != nil
        return all
    }

    func insertEvent(calendarId: String, body: [String: Any], withMeet: Bool) async throws {
        var c = URLComponents(string: "\(Self.calendarBase)/calendars/\(Self.enc(calendarId))/events")!
        c.queryItems = [.init(name: "sendUpdates", value: "all")]
            + (withMeet ? [.init(name: "conferenceDataVersion", value: "1")] : [])
        _ = try await data("POST", c.url!, json: body)
    }

    func patchEvent(calendarId: String, eventId: String, body: [String: Any], withMeet: Bool = false) async throws {
        var c = URLComponents(string: "\(Self.calendarBase)/calendars/\(Self.enc(calendarId))/events/\(Self.enc(eventId))")!
        c.queryItems = [.init(name: "sendUpdates", value: "all")]
            + (withMeet ? [.init(name: "conferenceDataVersion", value: "1")] : [])
        _ = try await data("PATCH", c.url!, json: body)
    }

    /// Moves an event to another calendar of the same account (`events.move`); the event keeps its id.
    func moveEvent(calendarId: String, eventId: String, destination: String) async throws {
        var c = URLComponents(string: "\(Self.calendarBase)/calendars/\(Self.enc(calendarId))/events/\(Self.enc(eventId))/move")!
        c.queryItems = [.init(name: "destination", value: destination), .init(name: "sendUpdates", value: "all")]
        _ = try await data("POST", c.url!)
    }

    /// Fetches a single event by id, including its `recurrence` (RRULE) lines when it's a series master —
    /// used to split a series for a "this and following" edit/delete (see RecurrenceScope).
    func getEvent(calendarId: String, eventId: String) async throws -> GEvent {
        let url = URL(string: "\(Self.calendarBase)/calendars/\(Self.enc(calendarId))/events/\(Self.enc(eventId))")!
        return try JSONDecoder().decode(GEvent.self, from: try await data("GET", url))
    }

    func deleteEvent(calendarId: String, eventId: String) async throws {
        var c = URLComponents(string: "\(Self.calendarBase)/calendars/\(Self.enc(calendarId))/events/\(Self.enc(eventId))")!
        c.queryItems = [.init(name: "sendUpdates", value: "all")]
        _ = try await data("DELETE", c.url!)
    }

    // MARK: Free / busy

    /// Returns busy intervals per calendar id; a nil value means the calendar isn't visible to us.
    func freeBusy(ids: [String], range: Range<Date>) async throws -> [String: [Range<Date>]?] {
        let body: [String: Any] = [
            "timeMin": RFC3339.string(range.lowerBound),
            "timeMax": RFC3339.string(range.upperBound),
            "items": ids.map { ["id": $0] },
        ]
        let d = try await data("POST", URL(string: "\(Self.calendarBase)/freeBusy")!, json: body)
        let fb = try JSONDecoder().decode(GFreeBusy.self, from: d)
        var out: [String: [Range<Date>]?] = [:]
        for id in ids {
            guard let cal = fb.calendars?[id], (cal.errors ?? []).isEmpty else { out[id] = .some(nil); continue }
            out[id] = (cal.busy ?? []).compactMap { slot in
                guard let s = RFC3339.parse(slot.start), let e = RFC3339.parse(slot.end), s < e else { return nil }
                return s..<e
            }
        }
        return out
    }

    // MARK: Directory

    func searchDirectory(_ query: String) async throws -> [DirectoryPerson] {
        var c = URLComponents(string: "https://people.googleapis.com/v1/people:searchDirectoryPeople")!
        c.queryItems = [
            .init(name: "query", value: query),
            .init(name: "readMask", value: "names,emailAddresses,photos"),
            .init(name: "sources", value: "DIRECTORY_SOURCE_TYPE_DOMAIN_PROFILE"),
            .init(name: "sources", value: "DIRECTORY_SOURCE_TYPE_DOMAIN_CONTACT"),
            .init(name: "pageSize", value: "12"),
        ]
        let r = try JSONDecoder().decode(GPeopleResponse.self, from: try await data("GET", c.url!))
        return (r.people ?? []).compactMap { p in
            guard let email = p.emailAddresses?.first?.value else { return nil }
            return DirectoryPerson(name: p.names?.first?.displayName ?? email,
                                   email: email,
                                   photoURL: p.photos?.first?.url.flatMap(URL.init(string:)))
        }
    }

    // MARK: Profile

    static func userInfo(accessToken: String) async throws -> Account {
        var req = URLRequest(url: URL(string: "https://openidconnect.googleapis.com/v1/userinfo")!)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (d, _) = try await URLSession.shared.data(for: req)
        guard let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any], let email = j["email"] as? String else {
            throw APIError.oauth("Couldn't read your Google profile")
        }
        return Account(email: email.lowercased(), name: j["name"] as? String)
    }
}

// MARK: - Mapping

enum EventMapper {
    static func map(_ g: GEvent, source: Source, ownerName: String? = nil, ownerEmail: String? = nil) -> CalEvent? {
        guard let id = g.id, g.status != "cancelled" else { return nil }

        let allDay = g.start?.date != nil
        let start: Date?, end: Date?
        if allDay {
            start = g.start?.date.flatMap(RFC3339.parseDay)
            end = g.end?.date.flatMap(RFC3339.parseDay)
        } else {
            start = g.start?.dateTime.flatMap(RFC3339.parse)
            end = g.end?.dateTime.flatMap(RFC3339.parse)
        }
        guard let s = start, let e = end else { return nil }

        let attendees = (g.attendees ?? []).compactMap { a -> Attendee? in
            guard let email = a.email else { return nil }
            return Attendee(email: email, name: a.displayName, response: a.responseStatus ?? "needsAction",
                            isSelf: a.isSelf ?? false, isOrganizer: a.organizer ?? false,
                            isResource: a.resource ?? false, isOptional: a.optional ?? false)
        }

        // A coworker who declined shouldn't show up on their overlay.
        if let ownerEmail, attendees.contains(where: { $0.email.lowercased() == ownerEmail.lowercased() && $0.response == "declined" }) {
            return nil
        }

        let location = g.location ?? ""
        let notes = g.description ?? ""
        let entry = g.conferenceData?.entryPoints?.first { $0.entryPointType == "video" }?.uri
        let meeting = (entry.flatMap(URL.init(string:)))
            ?? g.hangoutLink.flatMap(URL.init(string:))
            ?? MeetingLink.find(in: [location, notes])

        let visibility = EventVisibility(apiValue: g.visibility)
        // A coworker's private event: show only that they're busy, never any details we may have received.
        if source.kind == .person, visibility == .private {
            var busy = busyEvent(s..<e, source: source, ownerName: ownerName ?? "")
            busy.id = "\(source.id)|\(id)"
            busy.eventId = id
            busy.uid = g.iCalUID ?? id
            busy.isAllDay = allDay
            busy.visibility = .private
            return busy
        }

        let me = attendees.first { $0.isSelf }
        return CalEvent(
            id: "\(source.id)|\(id)", eventId: id, sourceId: source.id,
            calendarId: source.calendarId, accountId: source.accountId,
            uid: g.iCalUID ?? id,
            title: (g.summary?.isEmpty == false ? g.summary! : (source.kind == .person ? "Busy" : "(No title)")),
            start: s, end: e, isAllDay: allDay,
            location: location, notes: notes, attendees: attendees,
            htmlLink: g.htmlLink.flatMap(URL.init(string:)),
            meetingURL: meeting,
            colorHex: source.colorHex, sourceName: source.name,
            ownerName: ownerName, isOverlay: source.kind == .person,
            canEdit: source.kind == .calendar && source.canWrite,
            isBusyOnly: false, isRecurring: g.recurringEventId != nil,
            recurringEventId: g.recurringEventId,
            visibility: visibility,
            // No organizer block (e.g. imported events) means it's effectively ours.
            isOrganizer: g.organizer?.isSelf ?? (g.organizer == nil),
            guestsCanModify: g.guestsCanModify ?? false,
            guestsCanInviteOthers: g.guestsCanInviteOthers ?? true,
            zoomMeetingID: g.extendedProperties?.private?["zoomMeetingId"],
            isTentative: me?.response == "tentative",
            isDeclined: me?.response == "declined",
            alertMinutes: EventAlert.minutes(fromGoogle: g.reminders?.useDefault ?? (g.reminders == nil ? true : nil),
                                             overrides: g.reminders?.overrides?.map { ($0.method, $0.minutes) })
        )
    }

    static func busyEvent(_ slot: Range<Date>, source: Source, ownerName: String) -> CalEvent {
        CalEvent(
            id: "\(source.id)|busy|\(slot.lowerBound.timeIntervalSince1970)", eventId: "busy",
            sourceId: source.id, calendarId: source.calendarId, accountId: source.accountId,
            uid: "busy|\(source.id)|\(slot.lowerBound.timeIntervalSince1970)",
            title: "Busy", start: slot.lowerBound, end: slot.upperBound, isAllDay: false,
            location: "", notes: "", attendees: [], htmlLink: nil, meetingURL: nil,
            colorHex: source.colorHex, sourceName: source.name, ownerName: ownerName,
            isOverlay: true, canEdit: false, isBusyOnly: true, isRecurring: false,
            zoomMeetingID: nil, isTentative: false, isDeclined: false
        )
    }
}
