#if os(macOS)
import Foundation
import Network
import Observation

/// Hosts EZCal's MCP endpoint (issue #69): `POST http://127.0.0.1:<port>/mcp`, bound to loopback only, every request
/// needing `Authorization: Bearer <token>`. Off until switched on in Settings → Agents. It lives in the app so it can
/// reuse the store's save/routing (Google + Apple Calendar), the Keychain tokens and the calendars permission.
@MainActor @Observable
final class MCPServer {
    static let shared = MCPServer()

    enum Status: Equatable { case off, starting, running(UInt16), failed(String) }
    private(set) var status: Status = .off

    static let defaultPort = 47900
    static let tokenKey = "mcpToken"

    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var dispatcher: MCPDispatcher?
    @ObservationIgnored private weak var store: CalendarStore?

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "mcpEnabled") }
    static var isReadOnly: Bool { UserDefaults.standard.bool(forKey: "mcpReadOnly") }
    static var port: UInt16 {
        let p = UserDefaults.standard.integer(forKey: "mcpPort")
        return UInt16(exactly: p > 0 ? p : defaultPort) ?? UInt16(defaultPort)
    }

    /// The per-install access token, created on first use and kept in the Keychain.
    static func token() -> String {
        if let t = Keychain.get(tokenKey), !t.isEmpty { return t }
        return regenerateToken()
    }
    @discardableResult static func regenerateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let t = bytes.map { String(format: "%02x", $0) }.joined()
        Keychain.set(t, for: tokenKey)
        return t
    }

    func attach(_ store: CalendarStore) { self.store = store; sync() }

    /// Starts or stops the listener to match Settings (also restarts it when the port changed).
    func sync() {
        guard Self.isEnabled, let store else { stop(); return }
        if case .running(let p) = status, p == Self.port { return }
        if case .starting = status { return }
        stop()
        start(store)
    }

    func restart() { stop(); sync() }

    func stop() {
        listener?.cancel(); listener = nil
        dispatcher = nil
        status = .off
    }

    private func start(_ store: CalendarStore) {
        let port = Self.port
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { status = .failed("Invalid port"); return }
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)
        do {
            let l = try NWListener(using: params)
            let d = MCPDispatcher(tools: MCPTools.all(store: store), isReadOnly: { Self.isReadOnly })
            dispatcher = d
            status = .starting
            l.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self, self.listener === l else { return }
                    switch state {
                    case .ready: self.status = .running(port)
                    case .failed(let e): self.status = .failed(e.localizedDescription); self.listener = nil
                    default: break
                    }
                }
            }
            l.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in self?.accept(conn) }
            }
            listener = l
            l.start(queue: .main)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    // MARK: Connections

    private func accept(_ conn: NWConnection) {
        conn.start(queue: .main)
        // Drop connections that never finish a request.
        let timeout = DispatchWorkItem { conn.cancel() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeout)
        read(conn, buffer: Data(), timeout: timeout)
    }

    private func read(_ conn: NWConnection, buffer: Data, timeout: DispatchWorkItem) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, done, error in
            Task { @MainActor in
                guard let self else { conn.cancel(); return }
                var buf = buffer
                if let data { buf.append(data) }
                if error != nil || (done && data == nil) { conn.cancel(); return }
                switch MCPHTTPRequest.parse(buf) {
                case .needMore:
                    self.read(conn, buffer: buf, timeout: timeout)
                case .invalid:
                    self.send(conn, MCPHTTPRequest.response(status: 400), timeout)
                case .complete(let req):
                    let reply = await self.route(req)
                    self.send(conn, reply, timeout)
                }
            }
        }
    }

    private func send(_ conn: NWConnection, _ data: Data, _ timeout: DispatchWorkItem) {
        conn.send(content: data, completion: .contentProcessed { _ in
            timeout.cancel()
            conn.cancel()
        })
    }

    private func route(_ req: MCPHTTPRequest) async -> Data {
        guard req.isLoopbackOnly else { return MCPHTTPRequest.response(status: 403) }
        guard let presented = req.bearerToken, mcpTokensMatch(presented, Self.token()) else {
            return MCPHTTPRequest.response(status: 401, extra: ["WWW-Authenticate": "Bearer"])
        }
        guard req.path == "/mcp" || req.path.hasPrefix("/mcp?") else { return MCPHTTPRequest.response(status: 404) }
        guard req.method == "POST" else { return MCPHTTPRequest.response(status: 405, extra: ["Allow": "POST"]) }
        guard let dispatcher else { return MCPHTTPRequest.response(status: 404) }
        if let out = await dispatcher.handle(req.body) { return MCPHTTPRequest.response(status: 200, body: out) }
        return MCPHTTPRequest.response(status: 202)
    }
}
#endif
