import Foundation
import SwiftUI
import Observation
import EventKit

private struct FetchResult: Sendable {
    var sourceId: String
    var events: [CalEvent] = []
    var access: PersonAccess?
    var error: String?
}

@MainActor @Observable
final class CalendarStore {
    // Persisted
    var accounts: [Account] = []
    var people: [Source] = []
    private(set) var hidden: Set<String> = []
    private var knownCalendars: Set<String> = []

    // Loaded
    var calendars: [Source] = []
    var eventsBySource: [String: [CalEvent]] = [:]
    private(set) var displayEvents: [CalEvent] = []
    var upcoming: [CalEvent] = []
    var personAccess: [String: PersonAccess] = [:]

    // UI state
    var mode: ViewMode
    var anchor = Date()
    var isLoading = false
    var isSigningIn = false
    var errorMessage: String?
    var sheet: ActiveSheet?
    var zoomConnected = ZoomAPI.isConnected
    /// True only when a Zoom call just failed because the token was expired/revoked — distinct from
    /// `!zoomConnected` so the error banner doesn't offer "Reconnect" for someone who never connected Zoom.
    var zoomNeedsReconnect = false
    var eventKitEnabled = false
    /// `EZCAL_DEMO=1`: fake calendars and events, nothing read from or written to your accounts.
    let isDemo = ProcessInfo.processInfo.environment["EZCAL_DEMO"] != nil

    // Keyboard-driven state
    var focusedEventID: String?
    var deleteRequest: CalEvent?
    var showAddPerson = false
    var columnVisibility: NavigationSplitViewVisibility = .all
    var paletteQuery = ""

    /// Text shown next to the menu-bar icon, e.g. "Standup · 12m". Kept as plain state (updated by a timer)
    /// because a self-updating view inside a MenuBarExtra label makes SwiftUI spin at 100% CPU.
    var menuBarText = ""

    var hasAnyAccount: Bool { !accounts.isEmpty || eventKitEnabled }

    private var generation = 0
    private let defaults = UserDefaults.standard

    init() {
        mode = ViewMode(rawValue: defaults.string(forKey: "viewMode") ?? "") ?? .week
        accounts = Self.load("accounts", [Account].self) ?? []
        people = Self.load("people", [Source].self) ?? []
        hidden = Set(Self.load("hidden", [String].self) ?? [])
        knownCalendars = Set(Self.load("knownCalendars", [String].self) ?? [])
        eventKitEnabled = (defaults.bool(forKey: "eventKitEnabled") && EventKitService.shared.isAuthorized) || isDemo
        if let m = ProcessInfo.processInfo.environment["EZCAL_MODE"], let mm = ViewMode(rawValue: m) { mode = mm }

        Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
                self?.updateMenuBarText()
            }
        }

        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: EventKitService.shared.store, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.eventKitEnabled else { return }
                await self.loadCalendars()
                await self.reload()
                await self.refreshUpcoming()
            }
        }
    }

    // MARK: - Apple Calendar (EventKit)

    func enableEventKit() async {
        do {
            guard try await EventKitService.shared.requestAccess() else {
                errorMessage = "Calendar access was denied. Enable EZCal in System Settings → Privacy & Security → Calendars."
                return
            }
            eventKitEnabled = true
            defaults.set(true, forKey: "eventKitEnabled")
            errorMessage = nil
            await refreshAll()
        } catch { errorMessage = error.localizedDescription }
    }

    func disableEventKit() {
        eventKitEnabled = false
        defaults.set(false, forKey: "eventKitEnabled")
        calendars.removeAll { $0.isEventKit }
        eventsBySource = eventsBySource.filter { !$0.key.hasPrefix("ek|") }
        rebuildDisplay()
    }

    // MARK: - Persistence

    private static func load<T: Decodable>(_ key: String, _ type: T.Type) -> T? {
        guard let d = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }
    private func save<T: Encodable>(_ v: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(v), forKey: key)
    }
    private func persist() {
        save(accounts, "accounts"); save(people, "people")
        save(Array(hidden), "hidden"); save(Array(knownCalendars), "knownCalendars")
    }

    // MARK: - Calendar math

    var cal: Calendar {
        var c = Calendar.current
        let fw = AppSettings.firstWeekday
        if fw > 0 { c.firstWeekday = fw }
        return c
    }

    /// Monday of the Monday-to-Sunday week containing `d`, regardless of the week-start setting.
    func mondayStart(_ d: Date) -> Date {
        var c = Calendar.current
        c.firstWeekday = 2
        return c.date(from: c.dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)) ?? c.startOfDay(for: d)
    }

    func weekStart(_ d: Date) -> Date {
        let c = cal
        return c.date(from: c.dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)) ?? c.startOfDay(for: d)
    }

    var visibleDays: [Date] {
        let c = cal
        switch mode {
        case .day:
            return [c.startOfDay(for: anchor)]
        case .workWeek:
            let start = mondayStart(anchor)
            return (0..<5).map { c.date(byAdding: .day, value: $0, to: start)! }
        case .week:
            let start = weekStart(anchor)
            let all = (0..<7).map { c.date(byAdding: .day, value: $0, to: start)! }
            return AppSettings.showWeekends ? all : all.filter { !c.isDateInWeekend($0) }
        case .month:
            let first = c.date(from: c.dateComponents([.year, .month], from: anchor))!
            let start = weekStart(first)
            return (0..<42).map { c.date(byAdding: .day, value: $0, to: start)! }
        }
    }

    /// Range we ask Google for. Always includes every visible day (weekends included).
    var fetchRange: Range<Date> {
        let c = cal
        switch mode {
        case .day: return c.startOfDay(for: anchor)..<c.endOfDay(anchor)
        case .workWeek:
            let s = mondayStart(anchor)
            return s..<c.date(byAdding: .day, value: 5, to: s)!
        case .week:
            let s = weekStart(anchor)
            return s..<c.date(byAdding: .day, value: 7, to: s)!
        case .month:
            let d = visibleDays
            return d.first!..<c.endOfDay(d.last!)
        }
    }

    /// Range text and year, shown in two weights in the top bar ("September 21 – 27" + "2026").
    var titleParts: (main: String, year: String) {
        let days = visibleDays
        let year = anchor.formatted(.dateTime.year())
        switch mode {
        case .day: return (anchor.formatted(.dateTime.weekday(.wide).month(.wide).day()), year)
        case .month: return (anchor.formatted(.dateTime.month(.wide)), year)
        case .week, .workWeek:
            guard let f = days.first, let l = days.last else { return ("", year) }
            let sameMonth = cal.isDate(f, equalTo: l, toGranularity: .month)
            let main = sameMonth
                ? "\(f.formatted(.dateTime.month(.wide).day())) – \(l.formatted(.dateTime.day()))"
                : "\(f.formatted(.dateTime.month(.abbreviated).day())) – \(l.formatted(.dateTime.month(.abbreviated).day()))"
            let fy = f.formatted(.dateTime.year()), ly = l.formatted(.dateTime.year())
            return (main, fy == ly ? fy : "\(fy) – \(ly)")
        }
    }

    var title: String {
        let p = titleParts
        return mode == .month ? "\(p.main) \(p.year)" : "\(p.main), \(p.year)"
    }

    func step(_ n: Int) {
        let c = cal
        switch mode {
        case .day: anchor = c.date(byAdding: .day, value: n, to: anchor)!
        case .week, .workWeek: anchor = c.date(byAdding: .weekOfYear, value: n, to: anchor)!
        case .month: anchor = c.date(byAdding: .month, value: n, to: anchor)!
        }
        scheduleReload()
    }

    func goToday() { anchor = Date(); scheduleReload() }
    func goTo(_ d: Date) { anchor = d; scheduleReload() }
    func setMode(_ m: ViewMode) {
        mode = m
        defaults.set(m.rawValue, forKey: "viewMode")
        scheduleReload()
    }

    func scheduleReload() { Task { await reload() } }

    // MARK: - Sources

    var allSources: [Source] { calendars + people }
    func isVisible(_ s: Source) -> Bool { !hidden.contains(s.id) }

    func toggle(_ s: Source) {
        if hidden.contains(s.id) {
            hidden.remove(s.id)
            persist()
            if eventsBySource[s.id] == nil { scheduleReload() } else { rebuildDisplay() }
        } else {
            hidden.insert(s.id)
            persist()
            rebuildDisplay()
        }
    }

    func setPeopleVisible(_ visible: Bool) {
        for p in people { if visible { hidden.remove(p.id) } else { hidden.insert(p.id) } }
        persist()
        if visible { scheduleReload() } else { rebuildDisplay() }
    }

    func addPerson(_ p: DirectoryPerson) {
        guard let acct = accounts.first else { return }
        addPerson(name: p.name, email: p.email, accountId: acct.id)
    }

    func addPerson(name: String, email: String, accountId: String? = nil) {
        guard let acct = accountId ?? accounts.first?.id else { return }
        let email = email.lowercased().trimmingCharacters(in: .whitespaces)
        let id = Source.personID(account: acct, email: email)
        guard !people.contains(where: { $0.id == id }) else { hidden.remove(id); persist(); scheduleReload(); return }
        let color = Palette.people[people.count % Palette.people.count]
        people.append(Source(id: id, accountId: acct, calendarId: email,
                             name: name.isEmpty ? email : name, colorHex: color, kind: .person))
        hidden.remove(id)
        persist()
        scheduleReload()
    }

    func removePerson(_ s: Source) {
        people.removeAll { $0.id == s.id }
        eventsBySource[s.id] = nil
        hidden.remove(s.id)
        personAccess[s.id] = nil
        persist()
        rebuildDisplay()
    }

    // MARK: - Accounts

    func signIn() async {
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            let token = try await OAuth.authorize(try OAuthConfig.google())
            let acct = try await GoogleAPI.userInfo(accessToken: token.accessToken)
            TokenStore.save(token, for: .google(acct.email))
            if !accounts.contains(where: { $0.id == acct.id }) { accounts.append(acct) }
            persist()
            errorMessage = nil
            await refreshAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut(_ a: Account) {
        TokenStore.remove(.google(a.email))
        accounts.removeAll { $0.id == a.id }
        calendars.removeAll { $0.accountId == a.id }
        people.removeAll { $0.accountId == a.id }
        eventsBySource = eventsBySource.filter { !$0.key.contains("|\(a.id)|") }
        persist()
        rebuildDisplay()
    }

    func connectZoom() async {
        do { try await ZoomAPI.connect(); zoomConnected = true; zoomNeedsReconnect = false; errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }

    func disconnectZoom() { ZoomAPI.disconnect(); zoomConnected = false; zoomNeedsReconnect = false }

    // MARK: - Loading

    func bootstrap() async {
        await refreshAll()
    }

    func refreshAll() async {
        if isDemo { loadDemo(); return }
        await loadCalendars()
        await reload()
        await refreshUpcoming()
    }

    func loadCalendars() async {
        var result: [Source] = []
        var firstError: String?
        for acct in accounts {
            do {
                let items = try await GoogleAPI(accountId: acct.id).calendarList()
                for i in items {
                    let id = Source.calendarID(account: acct.id, calendar: i.id)
                    if !knownCalendars.contains(id) {
                        knownCalendars.insert(id)
                        if i.selected != true && i.primary != true { hidden.insert(id) }
                    }
                    result.append(Source(id: id, accountId: acct.id, calendarId: i.id,
                                         name: i.summaryOverride ?? i.summary ?? i.id,
                                         colorHex: i.backgroundColor ?? "#4285F4",
                                         kind: .calendar, accessRole: i.accessRole ?? "reader"))
                }
            } catch {
                firstError = firstError ?? "\(acct.email): \(error.localizedDescription)"
            }
        }
        if !accounts.isEmpty && result.isEmpty && firstError != nil {
            errorMessage = firstError
            result = calendars.filter { !$0.isEventKit }   // keep what we had
        }
        if eventKitEnabled {
            for s in EventKitService.shared.sources() {
                if !knownCalendars.contains(s.id) {
                    knownCalendars.insert(s.id)
                    if EventKitService.shared.isBirthdayCalendar(s.calendarId) { hidden.insert(s.id) }
                }
                result.append(s)
            }
        }
        if !result.isEmpty || accounts.isEmpty { calendars = result }
        persist()
    }

    func reload() async {
        if isDemo { loadDemo(); return }
        generation += 1
        let gen = generation
        guard hasAnyAccount else {
            eventsBySource = [:]; rebuildDisplay(); return
        }
        let range = fetchRange
        let sources = allSources.filter(isVisible)
        isLoading = true

        var fresh: [String: [CalEvent]] = [:]
        var access: [String: PersonAccess] = [:]
        var firstError: String?
        await withTaskGroup(of: FetchResult.self) { group in
            for s in sources { group.addTask { await Self.fetch(s, range) } }
            for await r in group {
                fresh[r.sourceId] = r.events
                if let a = r.access { access[r.sourceId] = a }
                if let e = r.error, firstError == nil { firstError = e }
            }
        }
        guard gen == generation else { return }
        // Keep cached events for hidden sources, replace the ones we just fetched.
        for (k, v) in fresh { eventsBySource[k] = v }
        for (k, v) in access { personAccess[k] = v }
        errorMessage = firstError
        isLoading = false
        rebuildDisplay()
    }

    func refreshUpcoming() async {
        let now = Date()
        let range = now.addingTimeInterval(-3600)..<now.addingTimeInterval(36 * 3600)
        let sources = calendars.filter(isVisible)
        var out: [CalEvent] = []
        await withTaskGroup(of: FetchResult.self) { group in
            for s in sources { group.addTask { await Self.fetch(s, range) } }
            for await r in group { out += r.events }
        }
        var seen = Set<String>()
        upcoming = out
            .filter { !$0.isAllDay && !$0.isDeclined && $0.end > now && seen.insert($0.uid + "\($0.start.timeIntervalSince1970)").inserted }
            .sorted { $0.start < $1.start }
        updateMenuBarText()
    }

    func updateMenuBarText(now: Date = Date()) {
        var text = ""
        if let e = nextMeeting {
            let mins = Int(e.start.timeIntervalSince(now) / 60)
            let title = e.title.count > 22 ? String(e.title.prefix(21)) + "…" : e.title
            if mins <= 0 { text = "\(title) · now" }
            else if mins < 60 { text = "\(title) · \(mins)m" }
        }
        if text != menuBarText { menuBarText = text }
    }

    nonisolated private static func fetch(_ s: Source, _ range: Range<Date>) async -> FetchResult {
        if s.isEventKit {
            return FetchResult(sourceId: s.id, events: EventKitService.shared.events(for: s, range: range))
        }
        let api = GoogleAPI(accountId: s.accountId)
        switch s.kind {
        case .calendar:
            do {
                let items = try await api.events(calendarId: s.calendarId, range: range)
                return FetchResult(sourceId: s.id, events: items.compactMap { EventMapper.map($0, source: s) })
            } catch {
                return FetchResult(sourceId: s.id, error: "\(s.name): \(error.localizedDescription)")
            }
        case .person:
            let first = s.name.split(separator: " ").first.map(String.init) ?? s.name
            do {
                let items = try await api.events(calendarId: s.calendarId, range: range)
                let events = items.compactMap { EventMapper.map($0, source: s, ownerName: first, ownerEmail: s.calendarId) }
                return FetchResult(sourceId: s.id, events: events, access: .full)
            } catch APIError.http(let code, _) where code == 403 || code == 404 {
                // Details aren't shared with us; fall back to free/busy blocks.
                do {
                    let fb = try await api.freeBusy(ids: [s.calendarId], range: range)
                    guard case .some(.some(let slots)) = fb[s.calendarId] else {
                        return FetchResult(sourceId: s.id, access: PersonAccess.none)
                    }
                    return FetchResult(sourceId: s.id,
                                       events: slots.map { EventMapper.busyEvent($0, source: s, ownerName: first) },
                                       access: .busyOnly)
                } catch {
                    return FetchResult(sourceId: s.id, access: PersonAccess.none)
                }
            } catch {
                return FetchResult(sourceId: s.id, error: "\(s.name): \(error.localizedDescription)")
            }
        }
    }

    /// Flattens visible sources into one list, merging the same meeting seen on several calendars.
    func rebuildDisplay() {
        var seen = Set<String>()
        var real: [CalEvent] = []
        var busy: [CalEvent] = []
        for s in allSources where isVisible(s) {
            for e in eventsBySource[s.id] ?? [] {
                if e.isBusyOnly { busy.append(e); continue }
                if seen.insert("\(e.uid)|\(e.start.timeIntervalSince1970)").inserted { real.append(e) }
            }
        }
        // A "Busy" block that exactly matches a real event is just that event.
        let realSlots = Set(real.map { "\($0.start.timeIntervalSince1970)|\($0.end.timeIntervalSince1970)" })
        busy.removeAll { realSlots.contains("\($0.start.timeIntervalSince1970)|\($0.end.timeIntervalSince1970)") }
        displayEvents = real + busy
    }

    // MARK: - Queries for views

    func events(on day: Date) -> (allDay: [CalEvent], timed: [CalEvent]) {
        let c = cal
        let s = c.startOfDay(for: day), e = c.endOfDay(day)
        let hit = displayEvents.filter { $0.start < e && max($0.end, $0.start.addingTimeInterval(1)) > s }
        return (hit.filter(\.isAllDay).sorted { $0.start < $1.start },
                hit.filter { !$0.isAllDay }.sorted { $0.start < $1.start })
    }

    var nextMeeting: CalEvent? {
        let now = Date()
        return upcoming.first { $0.end > now }
    }

    // MARK: - Creating / editing

    var defaultSource: Source? {
        let writable = calendars.filter { $0.canWrite && isVisible($0) }
        return writable.first { $0.calendarId == $0.accountId } ?? writable.first ?? calendars.first { $0.canWrite }
    }

    func newDraft(start: Date? = nil, end: Date? = nil, allDay: Bool = false) {
        guard let src = defaultSource else {
            errorMessage = "No writable calendar available yet."
            return
        }
        let c = cal
        let s: Date
        if let start { s = start } else {
            let now = Date()
            let m = c.component(.minute, from: now)
            s = c.date(bySettingHour: c.component(.hour, from: now), minute: m < 30 ? 30 : 0, second: 0, of: now)!
                .addingTimeInterval(m < 30 ? 0 : 3600)
        }
        let e = end ?? s.addingTimeInterval(Double(AppSettings.defaultDuration) * 60)
        var d = EventDraft(start: s, end: e, isAllDay: allDay, sourceId: src.id)
        switch AppSettings.defaultVideo {
        case "zoom": d.video = .zoom
        case "meet": d.video = .meet
        default: break
        }
        sheet = .editor(d)
    }

    func editDraft(_ e: CalEvent) {
        var end = e.end
        if e.isAllDay { end = cal.date(byAdding: .day, value: -1, to: e.end) ?? e.end }
        var d = EventDraft(existing: e, title: e.title, start: e.start, end: end, isAllDay: e.isAllDay,
                           sourceId: e.sourceId, location: e.location, notes: e.notes.strippingHTML,
                           attendees: e.attendees)
        d.video = .none
        sheet = .editor(d)
    }

    func save(_ d: EventDraft) async throws {
        let title = d.title.trimmingCharacters(in: .whitespaces)
        let existing = d.existing
        let calendarId: String, accountId: String
        if let existing { calendarId = existing.calendarId; accountId = existing.accountId }
        else if let src = calendars.first(where: { $0.id == d.sourceId }) { calendarId = src.calendarId; accountId = src.accountId }
        else { throw APIError.invalid("Pick a calendar.") }
        let api = GoogleAPI(accountId: accountId)
        let c = cal

        var start = d.start, end = d.end
        if d.isAllDay {
            start = c.startOfDay(for: d.start)
            end = c.date(byAdding: .day, value: 1, to: c.startOfDay(for: max(d.start, d.end)))!
        } else if end <= start {
            throw APIError.invalid("The event must end after it starts.")
        }
        let displayTitle = title.isEmpty ? "(No title)" : title

        let isEK = existing?.isEventKit ?? (calendars.first { $0.id == d.sourceId }?.isEventKit ?? false)
        var location = d.location
        var notes = d.notes
        var notesChanged = existing == nil || d.notes != existing!.notes.strippingHTML
        var rawNotes = notesChanged ? d.notes : (existing?.notes ?? "")
        var zoomId = existing?.zoomMeetingID
        var extProps: [String: Any]?
        var wantsMeet = false

        if d.video == .zoom, existing?.meetingURL == nil {
            let m = try await ZoomAPI.createMeeting(topic: displayTitle, start: start, end: end, agenda: "", options: d.zoomOptions)
            let html = !isEK && rawNotes.contains("<")
            rawNotes = ZoomNotes.appending(ZoomNotes.block(for: m, html: html), to: rawNotes, html: html)
            notesChanged = true
            if location.isEmpty { location = m.joinURL }
            zoomId = String(m.id)
            extProps = ["private": ["zoomMeetingId": String(m.id)]]
        } else if d.video == .meet, existing?.meetingURL == nil, !isEK {
            wantsMeet = true
        }
        _ = notes; notes = rawNotes

        if isEK {
            // The visible notes never contain the marker; re-embed it here so it survives the round trip.
            let ekNotes = notesChanged ? ZoomNotes.applyingMarker(id: zoomId, to: notes) : nil
            try EventKitService.shared.save(existing: existing, calendarId: calendarId, title: displayTitle,
                                            start: start, end: d.isAllDay ? c.startOfDay(for: max(d.start, d.end)) : end,
                                            allDay: d.isAllDay, location: location,
                                            notes: ekNotes)
            if let zid = zoomId, let existing, existing.zoomMeetingID != nil,
               (existing.start != start || existing.end != end || existing.title != title) {
                await ZoomAPI.updateMeeting(id: zid, topic: displayTitle, start: start, end: end)
            }
            sheet = nil
            await reload()
            await refreshUpcoming()
            return
        }

        func timeDict(_ date: Date) -> [String: Any] {
            d.isAllDay ? ["date": RFC3339.dayString(date)]
                       : ["dateTime": RFC3339.string(date), "timeZone": TimeZone.current.identifier]
        }
        var body: [String: Any] = [
            "summary": title,
            "location": location,
            "start": timeDict(start),
            "end": timeDict(end),
        ]
        if notesChanged { body["description"] = notes }
        if let extProps { body["extendedProperties"] = extProps }
        if existing != nil || !d.attendees.isEmpty {
            body["attendees"] = d.attendees.map { a -> [String: Any] in
                var x: [String: Any] = ["email": a.email]
                if existing != nil { x["responseStatus"] = a.response }
                if a.isOptional { x["optional"] = true }
                if a.isResource { x["resource"] = true }
                if let n = a.name, !n.isEmpty { x["displayName"] = n }
                return x
            }
        }
        if wantsMeet {
            body["conferenceData"] = ["createRequest": [
                "requestId": UUID().uuidString,
                "conferenceSolutionKey": ["type": "hangoutsMeet"],
            ]]
        }

        if let existing {
            try await api.patchEvent(calendarId: calendarId, eventId: existing.eventId, body: body, withMeet: wantsMeet)
            if let zid = zoomId, existing.zoomMeetingID != nil, (existing.start != start || existing.end != end || existing.title != title) {
                await ZoomAPI.updateMeeting(id: zid, topic: displayTitle, start: start, end: end)
            }
        } else {
            try await api.insertEvent(calendarId: calendarId, body: body, withMeet: wantsMeet)
        }
        sheet = nil
        await reload()
        await refreshUpcoming()
    }

    func delete(_ e: CalEvent) async {
        do {
            if e.isEventKit { try EventKitService.shared.delete(e) }
            else { try await GoogleAPI(accountId: e.accountId).deleteEvent(calendarId: e.calendarId, eventId: e.eventId) }
            if let z = e.zoomMeetingID { await ZoomAPI.deleteMeeting(id: z) }
            sheet = nil
            await reload()
            await refreshUpcoming()
        } catch { reportZoomError(error) }
    }

    /// One-click "add Zoom" for an event that already exists.
    func attachZoom(to e: CalEvent) async {
        do {
            let end = e.end > e.start ? e.end : e.start.addingTimeInterval(1800)
            let m = try await ZoomAPI.createMeeting(topic: e.title, start: e.start, end: end, options: .defaults)
            if e.isEventKit {
                let notes = ZoomNotes.applyingMarker(id: String(m.id),
                    to: ZoomNotes.appending(ZoomNotes.block(for: m, html: false), to: e.notes, html: false))
                try EventKitService.shared.save(existing: e, calendarId: e.calendarId, title: e.title,
                                                start: e.start, end: e.end, allDay: e.isAllDay,
                                                location: e.location.isEmpty ? m.joinURL : e.location,
                                                notes: notes)
                sheet = nil
                await reload()
                await refreshUpcoming()
                return
            }
            let html = e.notes.contains("<")
            var body: [String: Any] = [
                "description": ZoomNotes.appending(ZoomNotes.block(for: m, html: html), to: e.notes, html: html),
                "extendedProperties": ["private": ["zoomMeetingId": String(m.id)]],
            ]
            if e.location.isEmpty { body["location"] = m.joinURL }
            try await GoogleAPI(accountId: e.accountId).patchEvent(calendarId: e.calendarId, eventId: e.eventId, body: body)
            sheet = nil
            await reload()
            await refreshUpcoming()
        } catch { reportZoomError(error) }
    }

    /// "Remove Zoom link": deletes the meeting on Zoom's side (if we created it) and strips the block
    /// and hidden marker from the event's location/notes. Leaves other meeting links (Meet, a pasted
    /// Teams/Webex URL) untouched.
    func removeZoom(from e: CalEvent) async {
        guard e.meetingProvider == .zoom else { return }
        do {
            if let z = e.zoomMeetingID { await ZoomAPI.deleteMeeting(id: z) }
            let newLocation = e.location == e.meetingURL?.absoluteString ? "" : e.location
            let newNotes = ZoomNotes.removingZoomBlock(from: e.notes)
            if e.isEventKit {
                try EventKitService.shared.save(existing: e, calendarId: e.calendarId, title: e.title,
                                                start: e.start, end: e.end, allDay: e.isAllDay,
                                                location: newLocation,
                                                notes: ZoomNotes.applyingMarker(id: nil, to: newNotes))
            } else {
                var body: [String: Any] = ["location": newLocation, "description": newNotes]
                if e.zoomMeetingID != nil { body["extendedProperties"] = ["private": ["zoomMeetingId": NSNull()]] }
                try await GoogleAPI(accountId: e.accountId).patchEvent(calendarId: e.calendarId, eventId: e.eventId, body: body)
            }
            sheet = nil
            await reload()
            await refreshUpcoming()
        } catch { reportZoomError(error) }
    }

    /// Records the error for the banner and, when it's Zoom rejecting our token, flips `zoomConnected`
    /// so every "Connect Zoom" button in the app becomes a one-click reconnect.
    private func reportZoomError(_ error: Error) {
        errorMessage = error.localizedDescription
        if case APIError.zoomReconnectNeeded = error { zoomConnected = false; zoomNeedsReconnect = true }
    }

    func rsvp(_ e: CalEvent, _ response: String) async {
        let list = e.attendees.map { a -> [String: Any] in
            var x: [String: Any] = ["email": a.email, "responseStatus": a.isSelf ? response : a.response]
            if a.isOptional { x["optional"] = true }
            if a.isResource { x["resource"] = true }
            return x
        }
        do {
            try await GoogleAPI(accountId: e.accountId).patchEvent(calendarId: e.calendarId, eventId: e.eventId, body: ["attendees": list])
            sheet = nil
            await reload()
        } catch { errorMessage = error.localizedDescription }
    }

    // MARK: - Directory & availability

    func searchDirectory(_ q: String) async -> [DirectoryPerson] {
        let q = q.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2, let acct = accounts.first else { return [] }
        return (try? await GoogleAPI(accountId: acct.id).searchDirectory(q)) ?? []
    }

    /// Busy intervals per email within `window`; a nil entry means that person's availability isn't visible to us.
    func busyRanges(emails: [String], window: Range<Date>, accountId: String?) async -> [String: [Range<Date>]?] {
        guard !emails.isEmpty, let acct = accountId ?? accounts.first?.id else { return [:] }
        return (try? await GoogleAPI(accountId: acct).freeBusy(ids: emails, range: window)) ?? [:]
    }

    /// Your own visible events inside `window`, ignoring one event (the one being edited).
    func myBusy(in window: Range<Date>, excluding eventId: String?) -> [Range<Date>] {
        displayEvents
            .filter { !$0.isOverlay && !$0.isAllDay && !$0.isDeclined && $0.eventId != eventId }
            .compactMap { e -> Range<Date>? in
                let lo = max(e.start, window.lowerBound), hi = min(e.end, window.upperBound)
                return lo < hi ? lo..<hi : nil
            }
    }
}
