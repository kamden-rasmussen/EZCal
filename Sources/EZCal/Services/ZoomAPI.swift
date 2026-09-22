import Foundation

struct ZoomMeeting: Sendable {
    var id: Int
    var joinURL: String
    var password: String?
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
            let token = try await TokenManager.shared.accessToken(for: .zoom, force: attempt > 0)
            var req = URLRequest(url: URL(string: base + path)!)
            req.httpMethod = method
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let json {
                req.httpBody = try JSONSerialization.data(withJSONObject: json)
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            let (d, r) = try await URLSession.shared.data(for: req)
            let status = (r as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 && attempt == 0 { continue }
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

    static func createMeeting(topic: String, start: Date, end: Date, agenda: String = "") async throws -> ZoomMeeting {
        var body = timing(start, end)
        body["topic"] = topic
        body["type"] = 2
        if !agenda.isEmpty { body["agenda"] = String(agenda.prefix(1900)) }
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
