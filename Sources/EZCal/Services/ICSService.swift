import Foundation
import CryptoKit

/// A user's subscription to a read-only .ics feed. Identity is the feed URL itself (via `id`, a stable
/// hash of it), so re-adding the same URL updates the existing subscription instead of duplicating it.
struct ICSSubscription: Codable, Identifiable, Hashable, Sendable {
    var url: URL
    var name: String
    var colorHex: String

    var id: String { ICSService.cacheKey(for: url) }

    /// The `Source` this subscription appears as everywhere else in the app (sidebar, palette, grid).
    /// `accessRole` defaults to "reader", so `canWrite` is false and the event editor/RSVP/delete UI
    /// hide themselves automatically — no other file needs to know ICS calendars are read-only.
    var source: Source {
        Source(id: "ics|\(id)", accountId: "ics", calendarId: url.absoluteString,
               name: name, colorHex: colorHex, kind: .calendar)
    }
}

/// Fetches, caches to disk and parses read-only iCalendar subscriptions. `ICSParser` (Core) does the
/// pure parsing/RRULE-expansion; this file owns the networking and the on-disk cache so a feed that's
/// briefly unreachable keeps showing its last-known events instead of going blank.
final class ICSService: @unchecked Sendable {
    static let shared = ICSService()

    private let session: URLSession
    private let cacheDir: URL

    private init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 20
        session = URLSession(configuration: cfg)
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        cacheDir = base.appendingPathComponent("EZCal/ICSCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    static func cacheKey(for url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Accepts `webcal://` (rewritten to `https://`, its plain-GET equivalent) and `https://`/`http://`.
    static func normalizeURL(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("webcal://") { s = "https://" + s.dropFirst("webcal://".count) }
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", url.host != nil else { return nil }
        return url
    }

    private func paths(for key: String) -> (body: URL, meta: URL) {
        (cacheDir.appendingPathComponent("\(key).ics"), cacheDir.appendingPathComponent("\(key).meta.json"))
    }

    private struct Meta: Codable { var etag: String?; var lastModified: String? }

    /// Downloads (conditionally, via ETag/Last-Modified so an unchanged feed is a cheap 304) and parses
    /// the events for one subscription's `Source` within `range`. On any network or parse failure the
    /// last successfully cached body (if any) is reused, and the failure is reported as `error` rather
    /// than thrown, so one broken subscription never blocks the others.
    func fetchAndParse(_ source: Source, range: Range<Date>) async -> (events: [CalEvent], error: String?) {
        guard let url = URL(string: source.calendarId) else {
            return ([], "\(source.name): invalid subscription URL")
        }
        let key = Self.cacheKey(for: url)
        let (bodyPath, metaPath) = paths(for: key)
        var meta = (try? Data(contentsOf: metaPath)).flatMap { try? JSONDecoder().decode(Meta.self, from: $0) } ?? Meta()

        var request = URLRequest(url: url)
        request.setValue("text/calendar", forHTTPHeaderField: "Accept")
        if let etag = meta.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let lastModified = meta.lastModified { request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since") }

        var fetchError: String?
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                fetchError = "\(source.name): no response"
                return await result(bodyPath: bodyPath, source: source, range: range, error: fetchError)
            }
            switch http.statusCode {
            case 304:
                break   // cached body is still current
            case 200..<300:
                try data.write(to: bodyPath, options: .atomic)
                meta.etag = http.value(forHTTPHeaderField: "ETag") ?? meta.etag
                meta.lastModified = http.value(forHTTPHeaderField: "Last-Modified")
                if let encoded = try? JSONEncoder().encode(meta) { try? encoded.write(to: metaPath, options: .atomic) }
            case 404:
                fetchError = "\(source.name): feed not found (404)"
            case 401, 403:
                fetchError = "\(source.name): access denied (\(http.statusCode)) — this feed may require a private link"
            default:
                fetchError = "\(source.name): server returned \(http.statusCode)"
            }
        } catch {
            fetchError = "\(source.name): \(error.localizedDescription)"
        }
        return await result(bodyPath: bodyPath, source: source, range: range, error: fetchError)
    }

    private func result(bodyPath: URL, source: Source, range: Range<Date>, error: String?) async -> (events: [CalEvent], error: String?) {
        guard let text = try? String(contentsOf: bodyPath, encoding: .utf8) else {
            return ([], error ?? "\(source.name): not fetched yet")
        }
        let events = ICSParser.parse(text).flatMap { expand($0, source: source, range: range) }
        return (events, error)
    }

    private func expand(_ ev: ICSEvent, source: Source, range: Range<Date>) -> [CalEvent] {
        let duration = ev.end.timeIntervalSince(ev.start)
        let starts: [Date]
        if let rule = ev.recurrence {
            starts = rule.occurrences(seriesStart: ev.start, timeZone: ev.timeZone, range: range)
                .filter { !ev.exceptionDates.contains($0) }
        } else {
            starts = (ev.start < range.upperBound && ev.end > range.lowerBound) ? [ev.start] : []
        }
        return starts.map { start in
            CalEvent(
                id: "\(source.id)|\(ev.uid)|\(start.timeIntervalSince1970)", eventId: ev.uid,
                sourceId: source.id, calendarId: source.calendarId, accountId: source.accountId,
                uid: ev.uid, title: ev.summary.isEmpty ? "(No title)" : ev.summary,
                start: start, end: start.addingTimeInterval(duration), isAllDay: ev.isAllDay,
                location: ev.location, notes: ev.description, attendees: [],
                htmlLink: ev.url, meetingURL: MeetingLink.find(in: [ev.location, ev.description, ev.url?.absoluteString ?? ""]),
                colorHex: source.colorHex, sourceName: source.name,
                ownerName: nil, isOverlay: false, canEdit: false, isBusyOnly: false,
                isRecurring: ev.recurrence != nil, zoomMeetingID: nil, isTentative: false, isDeclined: false)
        }
    }

    /// Removes a subscription's cached body/metadata (called when the user removes it).
    func forget(_ subscription: ICSSubscription) {
        let (body, meta) = paths(for: subscription.id)
        try? FileManager.default.removeItem(at: body)
        try? FileManager.default.removeItem(at: meta)
    }
}
