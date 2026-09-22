import Foundation
import SwiftUI

struct Account: Codable, Identifiable, Hashable, Sendable {
    var id: String { email }
    var email: String
    var name: String?
}

/// Anything that produces events: one of your own Google calendars, or a coworker's calendar.
struct Source: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case calendar, person }

    var id: String
    var accountId: String
    var calendarId: String
    var name: String
    var colorHex: String
    var kind: Kind
    var accessRole: String = "reader"

    var canWrite: Bool { accessRole == "owner" || accessRole == "writer" }
    var color: Color { Color(hex: colorHex) }
    /// Calendars that come from macOS (iCloud etc.) via EventKit rather than the Google API.
    var isEventKit: Bool { id.hasPrefix("ek|") }
    /// Read-only .ics URL subscriptions (see `ICSSubscription`).
    var isICS: Bool { id.hasPrefix("ics|") }
    var groupTitle: String { accountId.hasPrefix("ek:") ? String(accountId.dropFirst(3)) : accountId }

    var initials: String {
        let parts = name.split(separator: " ").prefix(2).compactMap { $0.first }
        let s = String(parts).uppercased()
        return s.isEmpty ? String(name.prefix(1)).uppercased() : s
    }

    static func calendarID(account: String, calendar: String) -> String { "cal|\(account)|\(calendar)" }
    static func personID(account: String, email: String) -> String { "person|\(account)|\(email.lowercased())" }
}

enum PersonAccess: Sendable {
    case unknown
    case full       // we can read event details
    case busyOnly   // only free/busy is visible
    case none       // nothing visible
}

struct Attendee: Hashable, Sendable {
    var email: String
    var name: String?
    var response: String = "needsAction"   // needsAction, accepted, declined, tentative
    var isSelf = false
    var isOrganizer = false
    var isResource = false
    var isOptional = false

    var display: String { (name?.isEmpty == false ? name! : email) }
}

struct CalEvent: Identifiable, Hashable, Sendable {
    var id: String
    var eventId: String
    var sourceId: String
    var calendarId: String
    var accountId: String
    var uid: String
    var title: String
    var start: Date
    var end: Date            // exclusive for all-day events
    var isAllDay: Bool
    var location: String
    var notes: String
    var attendees: [Attendee]
    var htmlLink: URL?
    var meetingURL: URL?
    var colorHex: String
    var sourceName: String
    var ownerName: String?   // set for coworker overlay events
    var isOverlay: Bool
    var canEdit: Bool
    var isBusyOnly: Bool
    var isRecurring: Bool
    /// Google's id for the recurring event's master/series (nil for a non-recurring event, or an
    /// EventKit one — EventKit doesn't distinguish instance vs. series ids the way Google does).
    var recurringEventId: String? = nil
    var zoomMeetingID: String?
    var isTentative: Bool
    var isDeclined: Bool

    var color: Color { Color(hex: colorHex) }
    var isEventKit: Bool { sourceId.hasPrefix("ek|") }
    var isICS: Bool { sourceId.hasPrefix("ics|") }
    var meetingProvider: MeetingProvider? { meetingURL.map(MeetingProvider.init(url:)) }
    var selfAttendee: Attendee? { attendees.first { $0.isSelf } }
}

enum MeetingProvider: Sendable {
    case zoom, meet, teams, other

    init(url: URL) {
        let h = (url.host ?? "").lowercased()
        if h.contains("zoom.us") || h.contains("zoom.com") { self = .zoom }
        else if h.contains("meet.google.com") { self = .meet }
        else if h.contains("teams.microsoft.com") || h.contains("teams.live.com") { self = .teams }
        else { self = .other }
    }

    var name: String {
        switch self {
        case .zoom: return "Zoom"
        case .meet: return "Google Meet"
        case .teams: return "Teams"
        case .other: return "meeting"
        }
    }
}

enum MeetingLink {
    private static let patterns = [
        #"https?://[\w.-]*zoom\.(?:us|com)/[^\s<>"')]+"#,
        #"https?://meet\.google\.com/[a-z0-9\-]+[^\s<>"')]*"#,
        #"https?://teams\.(?:microsoft|live)\.com/[^\s<>"')]+"#,
        #"https?://[\w.-]*webex\.com/[^\s<>"')]+"#,
    ]

    static func find(in texts: [String]) -> URL? {
        let joined = texts.joined(separator: "\n").replacingOccurrences(of: "&amp;", with: "&")
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]),
                  let m = re.firstMatch(in: joined, range: NSRange(joined.startIndex..., in: joined)),
                  let r = Range(m.range, in: joined) else { continue }
            var s = String(joined[r])
            while let last = s.last, ".,;".contains(last) { s.removeLast() }
            if let url = URL(string: s) { return url }
        }
        return nil
    }
}

// MARK: - Draft used by the event editor

struct EventDraft: Identifiable {
    enum Video: String, CaseIterable, Identifiable {
        case none = "None", zoom = "Zoom", meet = "Google Meet"
        var id: String { rawValue }
    }

    let id = UUID()
    var existing: CalEvent?
    var title = ""
    var start: Date
    var end: Date            // for all-day drafts this is the *inclusive* last day
    var isAllDay = false
    var sourceId: String
    var location = ""
    var notes = ""
    var attendees: [Attendee] = []
    var video: Video = .none
    /// Only used when creating a new Zoom meeting; starts from Settings → Zoom's defaults.
    var zoomOptions: ZoomMeetingOptions = .defaults
    /// Which occurrences an edit to an existing recurring event applies to (chosen via RecurrenceScopeView).
    var recurrenceScope: RecurrenceScope = .thisEvent
    /// Recurrence to create a new event with; ignored when editing an existing event.
    var recurrence: RecurrenceOption = .none
}

enum ViewMode: String, CaseIterable, Identifiable {
    case day, workWeek, week, month
    var id: String { rawValue }
    var title: String {
        switch self {
        case .day: return "Day"
        case .workWeek: return "Work week"
        case .week: return "Week"
        case .month: return "Month"
        }
    }
}

enum ActiveSheet: Identifiable {
    case detail(CalEvent)
    case editor(EventDraft)
    case palette
    case shortcuts
    /// Standalone "Find a time" (opened from the ⌘K palette, not tied to an open editor).
    case findTime
    case addSubscription
    /// Shown before editing or deleting an occurrence of a recurring event.
    case recurrenceScope(CalEvent, RecurrenceAction)

    var id: String {
        switch self {
        case .palette: return "palette"
        case .shortcuts: return "shortcuts"
        case .findTime: return "findTime"
        case .addSubscription: return "addSubscription"
        case .detail(let e): return "detail-" + e.id
        case .editor(let d): return "editor-" + d.id.uuidString
        case .recurrenceScope(let e, let a): return "scope-\(a.rawValue)-" + e.id
        }
    }
}

struct DirectoryPerson: Identifiable, Hashable, Sendable {
    var id: String { email }
    var name: String
    var email: String
    var photoURL: URL?
}
