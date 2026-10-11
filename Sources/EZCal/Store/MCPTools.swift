#if os(macOS)
import Foundation

/// The calendar tools exposed over MCP (issue #69). Everything goes through `CalendarStore`, so Google and Apple
/// Calendar (EventKit) sources share one code path, and an id from any tool is accepted by every other tool.
@MainActor
enum MCPTools {
    static func all(store: CalendarStore) -> [MCPTool] {
        let h = MCPToolHelper(store: store)
        return [
            MCPTool(name: "list_calendars",
                    description: "List the user's calendars (Google, Apple/iCloud, subscriptions) with ids, whether each is writable, and which one create_event uses by default.",
                    schema: obj([:]), writes: false) { _ in h.listCalendars() },

            MCPTool(name: "list_events",
                    description: "List events between start and end (max 62 days) across all visible calendars, sorted by start. Busy-only and private events appear as \"Busy\" without details; use get_event for full detail.",
                    schema: obj([
                        "start": str("Window start: ISO 8601 date or date-time."),
                        "end": str("Window end (exclusive): ISO 8601 date or date-time."),
                        "calendar_ids": ["type": "array", "items": ["type": "string"], "description": "Only these calendars (ids from list_calendars). Default: all visible."],
                        "query": str("Case-insensitive text match on title, location and notes."),
                        "limit": ["type": "integer", "description": "Max events to return (default 50, max 200)."],
                        "cursor": str("`next_cursor` from a previous call."),
                    ], required: ["start", "end"]), writes: false) { try await h.listEvents($0) },

            MCPTool(name: "get_event",
                    description: "Full detail for one event: times, location, notes, attendees with RSVP status, video link, recurrence, calendar, and whether it can be edited.",
                    schema: obj(["event_id": str("Event id from any tool.")], required: ["event_id"]),
                    writes: false) { try await h.getEvent($0) },

            MCPTool(name: "create_event",
                    description: "Create an event. Uses the user's default writable calendar unless calendar_id is given. Works for Google and Apple/iCloud calendars. Overlapping events are reported in `conflicts` (the event is still created).",
                    schema: obj([
                        "title": str("Event title."),
                        "start": str("Start: ISO 8601 date-time, or a date (YYYY-MM-DD) for an all-day event."),
                        "end": str("End: ISO 8601 date-time (default: start + the user's default length). For all-day events, the last day, inclusive (default: the start day)."),
                        "all_day": ["type": "boolean", "description": "All-day event. Implied when start is a bare date."],
                        "calendar_id": str("Target calendar id from list_calendars."),
                        "location": str("Location."),
                        "notes": str("Description / notes."),
                        "attendees": ["type": "array", "items": ["type": "string"], "description": "Guest email addresses (Google calendars only)."],
                        "video": ["type": "string", "enum": ["none", "zoom", "meet"], "description": "Attach a Zoom or Google Meet link (meet: Google calendars only)."],
                        "recurrence": ["type": "string", "enum": ["none", "daily", "weekly", "monthly", "weekdays"], "description": "Repeat rule."],
                        "visibility": ["type": "string", "enum": ["default", "public", "private"], "description": "Google only; private shows others just \"Busy\"."],
                    ], required: ["title", "start"]), writes: true) { try await h.createEvent($0) },

            MCPTool(name: "update_event",
                    description: "Change an event. Only the fields you pass are changed. For a recurring event, `scope` picks which occurrences change (default this_event).",
                    schema: obj([
                        "event_id": str("Event id."),
                        "title": str("New title."),
                        "start": str("New start (ISO 8601 date-time, or date for all-day)."),
                        "end": str("New end (all-day: last day, inclusive)."),
                        "all_day": ["type": "boolean", "description": "Make it (or stop it being) an all-day event."],
                        "location": str("New location (empty string clears it)."),
                        "notes": str("New notes (empty string clears them)."),
                        "attendees": ["type": "array", "items": ["type": "string"], "description": "Replaces the guest list (Google calendars only)."],
                        "video": ["type": "string", "enum": ["zoom", "meet"], "description": "Add a video link if the event has none."],
                        "visibility": ["type": "string", "enum": ["default", "public", "private"]],
                        "scope": ["type": "string", "enum": ["this_event", "this_and_following", "all"], "description": "Recurring events only."],
                    ], required: ["event_id"]), writes: true) { try await h.updateEvent($0) },

            MCPTool(name: "delete_event",
                    description: "Delete an event and report what was deleted. For a recurring event, `scope` picks which occurrences go (default this_event).",
                    schema: obj([
                        "event_id": str("Event id."),
                        "scope": ["type": "string", "enum": ["this_event", "this_and_following", "all"], "description": "Recurring events only."],
                    ], required: ["event_id"]), writes: true) { try await h.deleteEvent($0) },

            MCPTool(name: "find_free_time",
                    description: "Find slots within the user's working hours where the user (and optionally other people) are free. Other people's availability is Google-only; people whose calendars aren't visible are reported as unknown.",
                    schema: obj([
                        "duration_minutes": ["type": "integer", "description": "Meeting length in minutes."],
                        "start": str("First day to search (ISO 8601 date)."),
                        "end": str("Day after the last day to search (max 30 days)."),
                        "attendee_emails": ["type": "array", "items": ["type": "string"]],
                        "limit": ["type": "integer", "description": "Max slots (default 10)."],
                    ], required: ["duration_minutes", "start", "end"]), writes: false) { try await h.findFreeTime($0) },
        ]
    }

    private static func obj(_ props: [String: Any], required: [String] = []) -> [String: Any] {
        var s: [String: Any] = ["type": "object", "properties": props]
        if !required.isEmpty { s["required"] = required }
        return s
    }
    private static func str(_ d: String) -> [String: Any] { ["type": "string", "description": d] }
}

@MainActor
struct MCPToolHelper {
    let store: CalendarStore
    private var cal: Calendar { store.cal }

    // MARK: Argument parsing

    private func string(_ a: [String: Any], _ k: String) -> String? {
        guard let s = a[k] as? String else { return nil }
        return s
    }
    private func required(_ a: [String: Any], _ k: String) throws -> String {
        guard let s = string(a, k)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else {
            throw MCPToolError("Missing required argument `\(k)`.")
        }
        return s
    }
    private func date(_ a: [String: Any], _ k: String) throws -> MCPDate.Parsed? {
        guard let s = string(a, k) else { return nil }
        guard let p = MCPDate.parse(s, calendar: cal) else {
            throw MCPToolError("`\(k)` must be ISO 8601 (e.g. 2026-10-12T14:30:00-06:00 or 2026-10-12), got \"\(s)\".")
        }
        return p
    }
    private func scope(_ a: [String: Any]) throws -> RecurrenceScope {
        switch string(a, "scope") {
        case nil, "this_event": return .thisEvent
        case "this_and_following": return .thisAndFollowing
        case "all": return .all
        case let s?: throw MCPToolError("`scope` must be this_event, this_and_following or all, got \"\(s)\".")
        }
    }
    private func emails(_ a: [String: Any], _ k: String) throws -> [String]? {
        guard let raw = a[k] else { return nil }
        guard let list = raw as? [String] else { throw MCPToolError("`\(k)` must be an array of email addresses.") }
        let cleaned = list.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for e in cleaned where !e.contains("@") { throw MCPToolError("\"\(e)\" is not an email address.") }
        return cleaned
    }

    // MARK: Output

    private func kind(_ s: Source) -> String { s.isEventKit ? "eventkit" : (s.isICS ? "ics" : "google") }

    func listCalendars() -> Any {
        let def = store.defaultSource?.id
        return ["calendars": store.calendars.map { s -> [String: Any] in
            ["id": s.id, "name": s.name, "account": s.groupTitle, "kind": kind(s),
             "writable": s.canWrite && !s.isICS, "visible": store.isVisible(s), "is_default": s.id == def]
        }]
    }

    private func masked(_ e: CalEvent) -> Bool { e.isBusyOnly || e.isPrivate }

    private func summary(_ e: CalEvent, masked hide: Bool) -> [String: Any] {
        var d: [String: Any] = ["id": e.id, "calendar_id": e.sourceId, "calendar": e.sourceName, "all_day": e.isAllDay]
        if e.isAllDay {
            d["start"] = MCPDate.day(e.start, calendar: cal)
            d["end"] = MCPDate.day(cal.date(byAdding: .day, value: -1, to: e.end) ?? e.end, calendar: cal)
        } else {
            d["start"] = MCPDate.string(e.start, timeZone: cal.timeZone)
            d["end"] = MCPDate.string(e.end, timeZone: cal.timeZone)
        }
        d["title"] = hide ? "Busy" : e.title
        if !hide {
            if !e.location.isEmpty { d["location"] = e.location }
            if let u = e.meetingURL { d["video_url"] = u.absoluteString }
            if e.isRecurring { d["recurring"] = true }
        } else { d["details_hidden"] = true }
        return d
    }

    private func detail(_ e: CalEvent) -> [String: Any] {
        var d = summary(e, masked: e.isBusyOnly)
        guard !e.isBusyOnly else { return d }
        d["can_edit"] = e.canEdit && (e.isEventKit || e.canModify || e.isGuestInviteOnly)
        d["time_zone"] = cal.timeZone.identifier
        if !e.notes.isEmpty { d["notes"] = e.notes.strippingHTML }
        if e.isPrivate { d["visibility"] = "private" }
        if e.isRecurring { d["recurring_series_id"] = e.recurringEventId ?? e.eventId }
        if let u = e.htmlLink { d["link"] = u.absoluteString }
        if e.isTentative { d["tentative"] = true }
        if e.isDeclined { d["declined"] = true }
        d["attendees"] = e.attendees.map { a -> [String: Any] in
            var x: [String: Any] = ["email": a.email, "response": a.response]
            if let n = a.name, !n.isEmpty { x["name"] = n }
            if a.isSelf { x["is_self"] = true }
            if a.isOrganizer { x["organizer"] = true }
            if a.isOptional { x["optional"] = true }
            return x
        }
        return d
    }

    // MARK: Fetching / locating events

    /// Events of `sources` overlapping `range`, fetched fresh (not limited to what the UI has loaded).
    private func fetchEvents(_ sources: [Source], _ range: Range<Date>) async -> (events: [CalEvent], errors: [String]) {
        if store.isDemo {
            let ids = Set(sources.map(\.id))
            return (store.displayEvents.filter { ids.contains($0.sourceId) && $0.start < range.upperBound && $0.end > range.lowerBound }, [])
        }
        var events: [CalEvent] = [], errors: [String] = []
        await withTaskGroup(of: FetchResult.self) { group in
            for s in sources { group.addTask { await CalendarStore.fetch(s, range) } }
            for await r in group {
                events += r.events.filter { $0.start < range.upperBound && $0.end > range.lowerBound }
                if let e = r.error { errors.append(e) }
            }
        }
        return (events, errors)
    }

    /// Same meeting on several calendars counts once (mirrors `CalendarStore.rebuildDisplay`).
    private func deduped(_ events: [CalEvent]) -> [CalEvent] {
        var seen = Set<String>()
        return events.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
            .filter { seen.insert("\($0.uid)|\($0.start.timeIntervalSince1970)").inserted }
    }

    private func visibleCalendars() -> [Source] { store.calendars.filter { store.isVisible($0) } }

    /// Ids look like `<source id>|<event id>|<start timestamp>`; the timestamp lets us re-fetch a narrow window
    /// instead of relying on whatever the UI happens to have loaded.
    private func locate(_ id: String) async throws -> CalEvent {
        let known = store.eventsBySource.values.joined()
        if let e = known.first(where: { $0.id == id }) ?? store.displayEvents.first(where: { $0.id == id }) { return e }
        if let tail = id.split(separator: "|").last, let ts = Double(tail) {
            let at = Date(timeIntervalSince1970: ts)
            let window = at.addingTimeInterval(-86_400)..<at.addingTimeInterval(2 * 86_400)
            let (events, _) = await fetchEvents(store.calendars, window)
            if let e = events.first(where: { $0.id == id }) { return e }
        }
        throw MCPToolError("No event with id \"\(id)\" (it may have been deleted or moved).")
    }

    private func requireEditable(_ e: CalEvent) throws {
        if e.isICS { throw MCPToolError("\"\(e.sourceName)\" is a read-only subscription; its events can't be changed.") }
        if e.isOverlay || e.isBusyOnly { throw MCPToolError("This is someone else's calendar; it can't be changed.") }
        if !e.canEdit { throw MCPToolError("\"\(e.sourceName)\" is read-only for you; this event can't be changed.") }
    }

    // MARK: Tools

    func listEvents(_ a: [String: Any]) async throws -> Any {
        guard let start = try date(a, "start"), let end = try date(a, "end") else { throw MCPToolError("`start` and `end` are required.") }
        guard end.date > start.date else { throw MCPToolError("`end` must be after `start`.") }
        guard end.date.timeIntervalSince(start.date) <= 62 * 86_400 else { throw MCPToolError("The window can be at most 62 days; split it into smaller ranges.") }
        var sources = visibleCalendars()
        if let ids = a["calendar_ids"] as? [String] {
            let all = store.calendars
            if let bad = ids.first(where: { id in !all.contains { $0.id == id } }) { throw MCPToolError("Unknown calendar id \"\(bad)\". Call list_calendars.") }
            sources = all.filter { ids.contains($0.id) }
        }
        let (fetched, errors) = await fetchEvents(sources, start.date..<end.date)
        var events = deduped(fetched)
        if let q = string(a, "query")?.trimmingCharacters(in: .whitespaces), !q.isEmpty {
            events = events.filter { e in
                !masked(e) && [e.title, e.location, e.notes.strippingHTML].contains { $0.localizedCaseInsensitiveContains(q) }
            }
        }
        let limit = min(max((a["limit"] as? Int) ?? 50, 1), 200)
        let offset = Int(string(a, "cursor") ?? "") ?? 0
        let page = Array(events.dropFirst(offset).prefix(limit))
        var out: [String: Any] = ["events": page.map { summary($0, masked: masked($0)) }, "total": events.count]
        if offset + page.count < events.count { out["next_cursor"] = String(offset + page.count) }
        if !errors.isEmpty { out["warnings"] = errors }
        return out
    }

    func getEvent(_ a: [String: Any]) async throws -> Any {
        detail(try await locate(try required(a, "event_id")))
    }

    func createEvent(_ a: [String: Any]) async throws -> Any {
        let title = try required(a, "title")
        guard let start = try date(a, "start") else { throw MCPToolError("Missing required argument `start`.") }
        let allDay = (a["all_day"] as? Bool) ?? start.dateOnly
        let end = try date(a, "end")
        let source: Source
        if let id = string(a, "calendar_id") {
            guard let s = store.calendars.first(where: { $0.id == id }) else { throw MCPToolError("Unknown calendar id \"\(id)\". Call list_calendars.") }
            source = s
        } else if let s = store.defaultSource { source = s }
        else { throw MCPToolError("No writable calendar is available.") }
        guard source.canWrite, !source.isICS else { throw MCPToolError("\"\(source.name)\" is read-only. Pick a writable calendar (list_calendars).") }

        let s0 = allDay ? cal.startOfDay(for: start.date) : start.date
        var e0 = end?.date ?? s0.addingTimeInterval(Double(AppSettings.defaultDuration) * 60)
        if allDay { e0 = end.map { cal.startOfDay(for: $0.date) } ?? s0 }   // inclusive last day
        else if e0 <= s0 { throw MCPToolError("`end` must be after `start`.") }

        var draft = EventDraft(start: s0, end: e0, isAllDay: allDay, sourceId: source.id)
        draft.title = title
        draft.location = string(a, "location") ?? ""
        draft.notes = string(a, "notes") ?? ""
        var warnings: [String] = []
        if let list = try emails(a, "attendees"), !list.isEmpty {
            if source.isEventKit { warnings.append("Apple calendars can't take guests through EZCal; attendees were ignored.") }
            else { draft.attendees = list.map { Attendee(email: $0) } }
        }
        switch string(a, "video") {
        case nil, "none": break
        case "zoom": draft.video = .zoom
        case "meet":
            if source.isEventKit { warnings.append("Google Meet needs a Google calendar; no video link was added.") } else { draft.video = .meet }
        case let v?: throw MCPToolError("`video` must be none, zoom or meet, got \"\(v)\".")
        }
        if let r = string(a, "recurrence") {
            guard let opt = RecurrenceOption(rawValue: r) else { throw MCPToolError("`recurrence` must be none, daily, weekly, monthly or weekdays.") }
            draft.recurrence = opt
        }
        if let v = string(a, "visibility") {
            guard let vis = EventVisibility(rawValue: v) else { throw MCPToolError("`visibility` must be default, public or private.") }
            if source.isEventKit { if vis != .default { warnings.append("Apple calendars have no private visibility; ignored.") } } else { draft.visibility = vis }
        }

        let window: Range<Date> = allDay ? s0..<(cal.date(byAdding: .day, value: 1, to: e0) ?? e0) : s0..<e0
        let (before, _) = await fetchEvents(visibleCalendars(), window)
        let conflicts = deduped(before).filter { !$0.isDeclined && !$0.isOverlay }

        try await save(draft)

        let (after, _) = await fetchEvents([source], window)
        var out: [String: Any] = ["created": true]
        let known = Set(before.map(\.id))
        if let made = after.filter({ !known.contains($0.id) && $0.title == title }).max(by: { $0.start < $1.start })
            ?? after.first(where: { $0.title == title && $0.start == s0 }) {
            out["event"] = detail(made)
        } else {
            out["note"] = "The event was saved but its id could not be determined yet; find it with list_events."
        }
        if !conflicts.isEmpty { out["conflicts"] = conflicts.map { summary($0, masked: masked($0)) } }
        if !warnings.isEmpty { out["warnings"] = warnings }
        return out
    }

    func updateEvent(_ a: [String: Any]) async throws -> Any {
        let id = try required(a, "event_id")
        let e = try await locate(id)
        try requireEditable(e)
        let scope = try scope(a)

        var d = EventDraft(existing: e, title: e.title, start: e.start,
                           end: e.isAllDay ? (cal.date(byAdding: .day, value: -1, to: e.end) ?? e.end) : e.end,
                           isAllDay: e.isAllDay, sourceId: e.sourceId, location: e.location,
                           notes: e.notes.strippingHTML, attendees: e.attendees)
        d.visibility = e.visibility
        d.recurrenceScope = scope

        let newStart = try date(a, "start"), newEnd = try date(a, "end")
        if let allDay = a["all_day"] as? Bool { d.isAllDay = allDay }
        else if let s = newStart, s.dateOnly { d.isAllDay = true }
        if let t = string(a, "title") {
            let t = t.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { throw MCPToolError("`title` can't be empty.") }
            d.title = t
        }
        let duration = e.end.timeIntervalSince(e.start)
        if let s = newStart {
            d.start = d.isAllDay ? cal.startOfDay(for: s.date) : s.date
            if newEnd == nil { d.end = d.isAllDay ? d.start : s.date.addingTimeInterval(e.isAllDay ? Double(AppSettings.defaultDuration) * 60 : duration) }
        }
        if let n = newEnd { d.end = d.isAllDay ? cal.startOfDay(for: n.date) : n.date }
        if d.isAllDay && newStart == nil && newEnd == nil && !e.isAllDay { d.start = cal.startOfDay(for: e.start); d.end = d.start }
        if !d.isAllDay && e.isAllDay && newStart == nil { throw MCPToolError("Provide `start` (and `end`) when turning an all-day event into a timed one.") }
        if !d.isAllDay, d.end <= d.start { throw MCPToolError("The event must end after it starts.") }
        if d.isAllDay, d.end < d.start { throw MCPToolError("`end` can't be before `start`.") }
        if let l = string(a, "location") { d.location = l }
        if let n = string(a, "notes") { d.notes = n }
        var warnings: [String] = []
        if let list = try emails(a, "attendees") {
            if e.isEventKit { warnings.append("Apple calendars can't take guests through EZCal; attendees were left alone.") }
            else {
                let current = Dictionary(e.attendees.map { ($0.email.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
                d.attendees = list.map { current[$0.lowercased()] ?? Attendee(email: $0) }
            }
        }
        if let v = string(a, "video") {
            switch v {
            case "zoom": d.video = .zoom
            case "meet": if e.isEventKit { warnings.append("Google Meet needs a Google calendar; no video link was added.") } else { d.video = .meet }
            default: throw MCPToolError("`video` must be zoom or meet.")
            }
        }
        if let v = string(a, "visibility") {
            guard let vis = EventVisibility(rawValue: v) else { throw MCPToolError("`visibility` must be default, public or private.") }
            if !e.isEventKit { d.visibility = vis }
        }

        try await save(d)

        let around = d.start.addingTimeInterval(-86_400)..<d.end.addingTimeInterval(2 * 86_400)
        let (after, _) = await fetchEvents([store.calendars.first { $0.id == e.sourceId }].compactMap { $0 }, around)
        var out: [String: Any] = ["updated": true]
        if let now = after.first(where: { $0.eventId == e.eventId && $0.start >= d.start.addingTimeInterval(-60) }) ?? after.first(where: { $0.eventId == e.eventId }) {
            out["event"] = detail(now)
        }
        if e.isRecurring { out["scope"] = scopeName(scope) }
        if !warnings.isEmpty { out["warnings"] = warnings }
        return out
    }

    func deleteEvent(_ a: [String: Any]) async throws -> Any {
        let id = try required(a, "event_id")
        let e = try await locate(id)
        try requireEditable(e)
        let scope = try scope(a)
        let summarized = summary(e, masked: false)

        store.errorMessage = nil
        let prev = store.sheet
        await store.delete(e, scope: scope)
        if prev != nil { store.sheet = prev }

        let around = e.start.addingTimeInterval(-86_400)..<e.end.addingTimeInterval(86_400)
        let (after, _) = await fetchEvents([store.calendars.first { $0.id == e.sourceId }].compactMap { $0 }, around)
        if after.contains(where: { $0.id == e.id }) {
            throw MCPToolError("The event could not be deleted\(store.errorMessage.map { ": \($0)" } ?? ".")")
        }
        var out: [String: Any] = ["deleted": true, "event": summarized]
        if e.isRecurring { out["scope"] = scopeName(scope) }
        return out
    }

    func findFreeTime(_ a: [String: Any]) async throws -> Any {
        guard let minutes = a["duration_minutes"] as? Int, minutes > 0 else { throw MCPToolError("`duration_minutes` must be a positive integer.") }
        guard let s = try date(a, "start"), let e = try date(a, "end") else { throw MCPToolError("`start` and `end` are required.") }
        let first = cal.startOfDay(for: s.date)
        let last = cal.startOfDay(for: e.date)
        guard last > first else { throw MCPToolError("`end` must be after `start`.") }
        guard let n = cal.dateComponents([.day], from: first, to: last).day, n <= 30 else { throw MCPToolError("Search at most 30 days at a time.") }
        let days = (0..<n).compactMap { cal.date(byAdding: .day, value: $0, to: first) }
        let window = first..<last
        let who = try emails(a, "attendee_emails") ?? []

        let (mine, _) = await fetchEvents(visibleCalendars(), window)
        let myBusy: [Range<Date>] = deduped(mine).filter { !$0.isAllDay && !$0.isDeclined && !$0.isOverlay }.compactMap { ev in
            let lo = max(ev.start, window.lowerBound), hi = min(ev.end, window.upperBound)
            return lo < hi ? lo..<hi : nil
        }
        let busy = await store.busyRanges(emails: who, window: window, accountId: nil)
        let slots = SlotFinder.findSlots(emails: who, busy: busy, myBusy: myBusy, duration: Double(minutes) * 60,
                                         days: days, workingHours: AppSettings.workingHours,
                                         limit: min(max((a["limit"] as? Int) ?? 10, 1), 100), calendar: cal)
        return ["slots": slots.map { slot -> [String: Any] in
            var d: [String: Any] = ["start": MCPDate.string(slot.start, timeZone: cal.timeZone), "end": MCPDate.string(slot.end, timeZone: cal.timeZone)]
            if !slot.attendees.isEmpty {
                d["attendees"] = slot.attendees.map { ["email": $0.email, "status": $0.unknown ? "unknown" : ($0.busy ? "busy" : "free")] }
            }
            return d
        }]
    }

    private func scopeName(_ s: RecurrenceScope) -> String {
        switch s { case .thisEvent: return "this_event"; case .thisAndFollowing: return "this_and_following"; case .all: return "all" }
    }

    /// `CalendarStore.save` closes whatever sheet the user has open; put it back so an agent edit doesn't eat a draft.
    private func save(_ d: EventDraft) async throws {
        let prev = store.sheet
        defer { if prev != nil { store.sheet = prev } }
        do { try await store.save(d) }
        catch { throw MCPToolError((error as? APIError).map { "\($0)" } ?? error.localizedDescription) }
    }
}
#endif
