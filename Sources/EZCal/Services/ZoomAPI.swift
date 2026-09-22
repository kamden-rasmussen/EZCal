import Foundation

struct ZoomMeeting: Sendable {
    var id: Int
    var joinURL: String
    var password: String?
}

/// Meeting options surfaced in the event editor (when creating a Zoom meeting) and as defaults in
/// Settings → Zoom. These map straight onto Zoom's documented `settings` object for Create/Update
/// Meeting: https://developers.zoom.us/docs/api/meetings/#tag/meetings/POST/users/{userId}/meetings
struct ZoomMeetingOptions: Equatable, Sendable {
    var waitingRoom: Bool
    var muteOnEntry: Bool
    var joinBeforeHost: Bool
    var hostVideoOn: Bool
    var participantVideoOn: Bool
    /// Off means "no passcode": we send an empty `password` so Zoom doesn't require one (subject to
    /// the account's own security policy, which can force a passcode regardless — untested against
    /// a real Zoom account since we have no test credentials).
    var passcodeEnabled: Bool

    /// Read from Settings → Zoom; a fresh `EventDraft` (and `attachZoom`'s one-click path) start here.
    static var defaults: ZoomMeetingOptions {
        ZoomMeetingOptions(waitingRoom: AppSettings.zoomWaitingRoom,
                            muteOnEntry: AppSettings.zoomMuteOnEntry,
                            joinBeforeHost: AppSettings.zoomJoinBeforeHost,
                            hostVideoOn: AppSettings.zoomHostVideo,
                            participantVideoOn: AppSettings.zoomParticipantVideo,
                            passcodeEnabled: AppSettings.zoomPasscodeEnabled)
    }

    /// The `settings` object sent with the create/update request.
    var settingsPayload: [String: Any] {
        [
            "waiting_room": waitingRoom,
            "mute_upon_entry": muteOnEntry,
            "join_before_host": joinBeforeHost,
            "host_video": hostVideoOn,
            "participant_video": participantVideoOn,
        ]
    }
}

enum ZoomAPI {
    private static let base = "https://api.zoom.us/v2"

    static var isConnected: Bool { TokenStore.load(.zoom) != nil }

    static func connect() async throws {
        let token = try await OAuth.authorize(try OAuthConfig.zoom())
        TokenStore.save(token, for: .zoom)
    }

    static func disconnect() { TokenStore.remove(.zoom) }

    private static func request(_ method: String, _ path: String, json: [String: Any]? = nil) async throws -> Data {
        for attempt in 0..<2 {
            let token: String
            do {
                token = try await TokenManager.shared.accessToken(for: .zoom, force: attempt > 0)
            } catch {
                // The refresh token itself was rejected (expired/revoked) — no amount of retrying helps.
                throw APIError.zoomReconnectNeeded(error.localizedDescription)
            }
            var req = URLRequest(url: URL(string: base + path)!)
            req.httpMethod = method
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let json {
                req.httpBody = try JSONSerialization.data(withJSONObject: json)
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            let (d, r) = try await URLSession.shared.data(for: req)
            let status = (r as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 {
                if attempt == 0 { continue } // retry once with a forced refresh
                throw APIError.zoomReconnectNeeded("Zoom's access token was rejected.")
            }
            guard (200..<300).contains(status) else {
                let msg = ((try? JSONSerialization.jsonObject(with: d)) as? [String: Any])?["message"] as? String ?? "HTTP \(status)"
                throw APIError.http(status, "Zoom: \(msg)")
            }
            return d
        }
        throw APIError.notSignedIn
    }

    private static func timing(_ start: Date, _ end: Date) -> [String: Any] {
        [
            "start_time": RFC3339.string(start),
            "duration": max(1, Int(end.timeIntervalSince(start) / 60)),
            "timezone": TimeZone.current.identifier,
        ]
    }

    /// Pure request-body construction, kept separate from `createMeeting` so it can be unit-tested
    /// without a network call (we have no Zoom credentials to test against in this environment).
    static func createMeetingBody(topic: String, start: Date, end: Date, agenda: String, options: ZoomMeetingOptions) -> [String: Any] {
        var body = timing(start, end)
        body["topic"] = topic
        body["type"] = 2
        if !agenda.isEmpty { body["agenda"] = String(agenda.prefix(1900)) }
        body["settings"] = options.settingsPayload
        if !options.passcodeEnabled { body["password"] = "" }
        return body
    }

    static func createMeeting(topic: String, start: Date, end: Date, agenda: String = "",
                              options: ZoomMeetingOptions = .defaults) async throws -> ZoomMeeting {
        let body = createMeetingBody(topic: topic, start: start, end: end, agenda: agenda, options: options)
        let d = try await request("POST", "/users/me/meetings", json: body)
        guard let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let id = j["id"] as? Int, let url = j["join_url"] as? String else {
            throw APIError.invalid("Zoom returned an unexpected response.")
        }
        return ZoomMeeting(id: id, joinURL: url, password: j["password"] as? String)
    }

    static func updateMeeting(id: String, topic: String, start: Date, end: Date) async {
        var body = timing(start, end)
        body["topic"] = topic
        _ = try? await request("PATCH", "/meetings/\(id)", json: body)
    }

    static func deleteMeeting(id: String) async {
        _ = try? await request("DELETE", "/meetings/\(id)")
    }
}

// MARK: - Notes formatting

/// Pure formatting for what EZCal writes into an event's notes/description for a Zoom meeting: the
/// human-readable "Join Zoom Meeting" block, and (for Apple Calendar events only) a hidden marker
/// line that remembers the meeting id.
///
/// EventKit has no field for arbitrary app metadata, so a marker line in `notes` is where we keep
/// the Zoom meeting id for iCloud/Apple Calendar events. We chose this over a local id map keyed by
/// the event's `eventIdentifier` because the marker travels with the event itself — it survives
/// EZCal being reinstalled, another Mac editing the same iCloud event, and EventKit occasionally
/// reassigning identifiers — whereas a local map would silently go stale in all of those cases.
/// The marker is wrapped in zero-width spaces so it renders as nothing in Calendar.app and in
/// EZCal's own notes field; `EventKitService` strips it before showing notes anywhere.
enum ZoomNotes {
    static func block(for meeting: ZoomMeeting, html: Bool) -> String {
        var lines = ["Join Zoom Meeting", meeting.joinURL, "", "Meeting ID: \(meeting.id)"]
        if let p = meeting.password, !p.isEmpty { lines.append("Passcode: \(p)") }
        if html {
            lines[1] = "<a href=\"\(meeting.joinURL)\">\(meeting.joinURL)</a>"
            return lines.joined(separator: "<br>")
        }
        return lines.joined(separator: "\n")
    }

    static func appending(_ block: String, to notes: String, html: Bool) -> String {
        if notes.isEmpty { return block }
        return notes + (html ? "<br><br>" : "\n\n") + block
    }

    /// Removes a previously-appended Zoom block (and any bare Zoom link) from notes/description, for
    /// "Remove Zoom link". Matches by content rather than position so user edits around the block
    /// survive. Works line-by-line on `\n`-separated text, which covers EventKit notes (always plain
    /// text) and the common Google case (a plain-text description); a Google description that is
    /// itself HTML — `appending(_:to:html:)` then joins with "<br>" instead of "\n" — isn't split into
    /// per-line matches here, so removal on that rarer path is best-effort and may remove more than
    /// just the Zoom block. Untested against a real Google/Zoom account.
    static func removingZoomBlock(from text: String) -> String {
        guard !text.isEmpty else { return text }
        let kept = text.components(separatedBy: "\n").filter { line -> Bool in
            let l = line.trimmingCharacters(in: .whitespaces)
            if l.isEmpty { return true } // blank lines are collapsed below, not filtered here
            if l == "Join Zoom Meeting" { return false }
            if l.hasPrefix("Meeting ID:") { return false }
            if l.hasPrefix("Passcode:") { return false }
            if l.lowercased().contains("zoom.us") || l.lowercased().contains("zoom.com") { return false }
            return true
        }
        // Collapse runs of blank lines left behind and trim the ends.
        var out: [String] = []
        for line in kept {
            let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty
            if isBlank && (out.isEmpty || out.last!.trimmingCharacters(in: .whitespaces).isEmpty) { continue }
            out.append(line)
        }
        while out.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { out.removeLast() }
        return out.joined(separator: "\n")
    }

    // MARK: Hidden marker (EventKit meeting-id remembrance)

    private static let zw = "\u{200B}"
    private static let markerPrefix = "EZCAL-ZOOM:"
    private static let markerRegex = try! NSRegularExpression(pattern: "\\n?\(zw)\(markerPrefix)(\\d+)\(zw)")

    static func marker(id: String) -> String { "\(zw)\(markerPrefix)\(id)\(zw)" }

    /// The Zoom meeting id embedded in `notes`, if any.
    static func meetingID(in notes: String) -> String? {
        guard let m = markerRegex.firstMatch(in: notes, range: NSRange(notes.startIndex..., in: notes)),
              let r = Range(m.range(at: 1), in: notes) else { return nil }
        return String(notes[r])
    }

    static func strippingMarker(_ notes: String) -> String {
        markerRegex.stringByReplacingMatches(in: notes, range: NSRange(notes.startIndex..., in: notes), withTemplate: "")
    }

    /// Notes with any existing marker replaced by one for `id`, or removed entirely when `id` is nil.
    static func applyingMarker(id: String?, to notes: String) -> String {
        let base = strippingMarker(notes)
        guard let id else { return base }
        return base.isEmpty ? marker(id: id) : base + "\n" + marker(id: id)
    }
}
