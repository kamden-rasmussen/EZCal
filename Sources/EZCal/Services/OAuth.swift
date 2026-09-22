import Foundation
import Network
import CryptoKit
import AppKit

enum APIError: LocalizedError {
    case missingCredentials(String)
    case notSignedIn
    case http(Int, String)
    case oauth(String)
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials(let s): return "\(s) client credentials are missing. Add them in Settings."
        case .notSignedIn: return "Not signed in."
        case .http(let code, let msg): return "HTTP \(code): \(msg)"
        case .oauth(let msg): return "Sign-in failed: \(msg)"
        case .invalid(let msg): return msg
        }
    }
}

struct TokenSet: Codable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
    var isExpired: Bool { expiresAt < Date().addingTimeInterval(60) }
}

struct OAuthConfig: Sendable {
    var authURL: URL
    var tokenURL: URL
    var clientID: String
    var clientSecret: String
    var scopes: [String] = []
    var extraAuthParams: [String: String] = [:]
    var basicAuth = false
    var fixedPort: UInt16? = nil
    var redirectHost = "127.0.0.1"
    var callbackPath = "/"
}

enum OAuth {
    /// Runs the full browser-based authorization-code + PKCE flow against a loopback redirect.
    static func authorize(_ c: OAuthConfig) async throws -> TokenSet {
        let server = LoopbackServer()
        let port = try await server.start(port: c.fixedPort)
        defer { server.stop() }

        let redirect = "http://\(c.redirectHost):\(port)\(c.callbackPath)"
        let verifier = randomString(48)
        let challenge = base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = randomString(16)

        var items: [URLQueryItem] = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: c.clientID),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
        ]
        if !c.scopes.isEmpty { items.append(.init(name: "scope", value: c.scopes.joined(separator: " "))) }
        for (k, v) in c.extraAuthParams { items.append(.init(name: k, value: v)) }

        var comps = URLComponents(url: c.authURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = items
        guard let authURL = comps.url else { throw APIError.invalid("Bad auth URL") }
        await MainActor.run { _ = NSWorkspace.shared.open(authURL) }

        let cb = try await server.waitForCallback(timeout: 300)
        let q = URLComponents(url: cb, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func val(_ n: String) -> String? { q.first { $0.name == n }?.value }

        if let err = val("error") { throw APIError.oauth(val("error_description") ?? err) }
        guard val("state") == state else { throw APIError.oauth("State mismatch") }
        guard let code = val("code") else { throw APIError.oauth("No authorization code returned") }

        return try await tokenRequest(c, params: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirect,
            "code_verifier": verifier,
        ], previousRefresh: nil)
    }

    static func refresh(_ c: OAuthConfig, token: TokenSet) async throws -> TokenSet {
        guard let rt = token.refreshToken else { throw APIError.notSignedIn }
        return try await tokenRequest(c, params: ["grant_type": "refresh_token", "refresh_token": rt], previousRefresh: rt)
    }

    private static func tokenRequest(_ c: OAuthConfig, params: [String: String], previousRefresh: String?) async throws -> TokenSet {
        var body = params
        var req = URLRequest(url: c.tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        if c.basicAuth {
            let cred = Data("\(c.clientID):\(c.clientSecret)".utf8).base64EncodedString()
            req.setValue("Basic \(cred)", forHTTPHeaderField: "Authorization")
        } else {
            body["client_id"] = c.clientID
            if !c.clientSecret.isEmpty { body["client_secret"] = c.clientSecret }
        }
        req.httpBody = Data(formEncode(body).utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(status), let access = json["access_token"] as? String else {
            let msg = (json["error_description"] as? String) ?? (json["reason"] as? String) ?? (json["error"] as? String) ?? "HTTP \(status)"
            throw APIError.oauth(msg)
        }
        let expires = (json["expires_in"] as? Double) ?? 3600
        return TokenSet(accessToken: access,
                        refreshToken: (json["refresh_token"] as? String) ?? previousRefresh,
                        expiresAt: Date().addingTimeInterval(expires))
    }

    // MARK: helpers

    static func formEncode(_ p: [String: String]) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return p.map { k, v in
            "\(k.addingPercentEncoding(withAllowedCharacters: allowed)!)=\(v.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&")
    }

    private static func randomString(_ bytes: Int) -> String {
        var b = [UInt8](repeating: 0, count: bytes)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes, &b)
        return base64URL(Data(b))
    }

    private static func base64URL(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Token storage / refresh coordination

enum Provider: Sendable {
    case google(String)   // account email
    case zoom

    var key: String {
        switch self {
        case .google(let e): return "token.google.\(e)"
        case .zoom: return "token.zoom"
        }
    }

    func config() throws -> OAuthConfig {
        switch self {
        case .google: return try OAuthConfig.google()
        case .zoom: return try OAuthConfig.zoom()
        }
    }
}

extension OAuthConfig {
    static func google() throws -> OAuthConfig {
        guard AppSettings.hasGoogleCredentials else { throw APIError.missingCredentials("Google") }
        return OAuthConfig(
            authURL: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenURL: URL(string: "https://oauth2.googleapis.com/token")!,
            clientID: AppSettings.googleClientID,
            clientSecret: AppSettings.googleClientSecret,
            scopes: [
                "openid", "email", "profile",
                "https://www.googleapis.com/auth/calendar",
                "https://www.googleapis.com/auth/directory.readonly",
            ],
            extraAuthParams: ["access_type": "offline", "prompt": "consent select_account"]
        )
    }

    /// Zoom "General app" (user-managed OAuth). Register http://localhost:48291/callback as the redirect URL.
    static func zoom() throws -> OAuthConfig {
        guard AppSettings.hasZoomCredentials else { throw APIError.missingCredentials("Zoom") }
        return OAuthConfig(
            authURL: URL(string: "https://zoom.us/oauth/authorize")!,
            tokenURL: URL(string: "https://zoom.us/oauth/token")!,
            clientID: AppSettings.zoomClientID,
            clientSecret: AppSettings.zoomClientSecret,
            basicAuth: true,
            fixedPort: 48291,
            redirectHost: "localhost",
            callbackPath: "/callback"
        )
    }
}

enum TokenStore {
    static func load(_ p: Provider) -> TokenSet? {
        guard let s = Keychain.get(p.key), let d = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TokenSet.self, from: d)
    }
    static func save(_ t: TokenSet, for p: Provider) {
        if let d = try? JSONEncoder().encode(t), let s = String(data: d, encoding: .utf8) { Keychain.set(s, for: p.key) }
    }
    static func remove(_ p: Provider) { Keychain.remove(p.key) }
}

/// Serializes refreshes so a burst of parallel requests only refreshes once.
actor TokenManager {
    static let shared = TokenManager()
    private var inflight: [String: Task<TokenSet, Error>] = [:]

    func accessToken(for p: Provider, force: Bool = false) async throws -> String {
        guard let t = TokenStore.load(p) else { throw APIError.notSignedIn }
        if !force && !t.isExpired { return t.accessToken }
        if let task = inflight[p.key] { return try await task.value.accessToken }

        let cfg = try p.config()
        let task = Task { try await OAuth.refresh(cfg, token: t) }
        inflight[p.key] = task
        defer { inflight[p.key] = nil }
        let fresh = try await task.value
        TokenStore.save(fresh, for: p)
        return fresh.accessToken
    }
}

// MARK: - Loopback HTTP server that catches the OAuth redirect

private final class Flag: @unchecked Sendable { var isSet = false }

final class LoopbackServer: @unchecked Sendable {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "ezcal.loopback")
    private var continuation: CheckedContinuation<URL, Error>?
    private var pending: Result<URL, Error>?
    private var port: UInt16 = 0

    func start(port: UInt16?) async throws -> UInt16 {
        let params = NWParameters.tcp
        let nwPort: NWEndpoint.Port = port.flatMap { NWEndpoint.Port(rawValue: $0) } ?? .any
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: nwPort)
        params.allowLocalEndpointReuse = true
        let l = try NWListener(using: params)
        listener = l

        let bound: UInt16 = try await withCheckedThrowingContinuation { cont in
            let done = Flag()
            l.stateUpdateHandler = { state in
                guard !done.isSet else { return }
                switch state {
                case .ready:
                    done.isSet = true
                    cont.resume(returning: l.port?.rawValue ?? 0)
                case .failed(let e):
                    done.isSet = true
                    cont.resume(throwing: e)
                default: break
                }
            }
            l.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
            l.start(queue: queue)
        }
        self.port = bound
        return bound
    }

    func waitForCallback(timeout: TimeInterval) async throws -> URL {
        queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.deliver(.failure(APIError.oauth("Timed out waiting for the browser.")))
        }
        return try await withCheckedThrowingContinuation { cont in
            queue.async {
                if let r = self.pending { self.pending = nil; cont.resume(with: r) }
                else { self.continuation = cont }
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func deliver(_ r: Result<URL, Error>) {
        if let c = continuation { continuation = nil; c.resume(with: r) }
        else if pending == nil { pending = r }
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, _ in
            guard let self, let data, let text = String(data: data, encoding: .utf8) else { conn.cancel(); return }
            let line = text.split(separator: "\r\n", maxSplits: 1).first.map(String.init) ?? ""
            let parts = line.split(separator: " ")
            guard parts.count >= 2, let url = URL(string: "http://127.0.0.1:\(self.port)\(parts[1])") else { conn.cancel(); return }

            let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let isCallback = q.contains { $0.name == "code" || $0.name == "error" }
            let ok = !q.contains { $0.name == "error" }
            let html = """
            <html><head><meta charset="utf-8"><title>EZCal</title></head>
            <body style="font-family:-apple-system,sans-serif;text-align:center;padding-top:15vh;color:#222">
            <h2>\(isCallback ? (ok ? "You're signed in ✓" : "Sign-in failed") : "Not found")</h2>
            <p>You can close this tab and return to EZCal.</p></body></html>
            """
            let resp = "HTTP/1.1 \(isCallback ? "200 OK" : "404 Not Found")\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
            conn.send(content: Data(resp.utf8), completion: .contentProcessed { _ in conn.cancel() })
            if isCallback { self.deliver(.success(url)) }
        }
    }
}
