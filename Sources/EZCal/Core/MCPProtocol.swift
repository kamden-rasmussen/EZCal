import Foundation

/// Minimal Model Context Protocol (JSON-RPC 2.0) plumbing for the in-app agent server (issue #69):
/// `initialize`, `ping`, `tools/list` and `tools/call` over the Streamable HTTP transport's plain-JSON mode.
/// Pure and I/O-free so it is unit-testable; the socket lives in `Services/MCPServer.swift` and the calendar
/// tools in `Store/MCPTools.swift`.

/// Thrown by a tool to report a failure to the agent (returned as an `isError` tool result, not a protocol error).
struct MCPToolError: Error, LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct MCPTool {
    let name: String
    let description: String
    /// JSON Schema for the arguments object.
    let schema: [String: Any]
    /// Tools that create, change or delete data; refused while the server is in read-only mode.
    let writes: Bool
    /// Returns any JSON-serializable value; it is sent to the agent as pretty text.
    let run: @MainActor ([String: Any]) async throws -> Any
}

@MainActor
final class MCPDispatcher {
    static let supportedVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    var tools: [MCPTool]
    var isReadOnly: () -> Bool

    init(tools: [MCPTool], isReadOnly: @escaping () -> Bool = { false }) {
        self.tools = tools
        self.isReadOnly = isReadOnly
    }

    /// Handles one POST body. Returns nil when nothing should be sent back (notifications / responses only).
    func handle(_ body: Data) async -> Data? {
        guard let json = try? JSONSerialization.jsonObject(with: body) else {
            return encode(error(id: nil, code: -32700, message: "Parse error"))
        }
        if let batch = json as? [Any] {
            if batch.isEmpty { return encode(error(id: nil, code: -32600, message: "Empty batch")) }
            var out: [[String: Any]] = []
            for item in batch { if let r = await handleOne(item) { out.append(r) } }
            return out.isEmpty ? nil : encode(out)
        }
        guard let r = await handleOne(json) else { return nil }
        return encode(r)
    }

    private func handleOne(_ item: Any) async -> [String: Any]? {
        guard let msg = item as? [String: Any], msg["jsonrpc"] as? String == "2.0" else {
            return error(id: nil, code: -32600, message: "Invalid request")
        }
        let id = msg["id"]
        // No method: a response to something we never sent. Ignore.
        guard let method = msg["method"] as? String else { return nil }
        let params = msg["params"] as? [String: Any] ?? [:]
        // Notifications (no id) never get a reply.
        if id == nil { return nil }

        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String ?? ""
            let version = Self.supportedVersions.contains(asked) ? asked : Self.supportedVersions[0]
            return result(id: id, [
                "protocolVersion": version,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "ezcal", "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"],
                "instructions": "Read and manage the user's calendar events across Google and Apple Calendar accounts. "
                    + "Times are ISO 8601 (e.g. 2026-10-12T14:30:00-06:00); without an offset they are in the user's local time zone. "
                    + "Call list_calendars first to see calendar ids; event ids from any tool work in every other tool.",
            ])
        case "ping":
            return result(id: id, [:])
        case "tools/list":
            return result(id: id, ["tools": tools.map { t -> [String: Any] in
                ["name": t.name, "description": t.description, "inputSchema": t.schema]
            }])
        case "tools/call":
            guard let name = params["name"] as? String, let tool = tools.first(where: { $0.name == name }) else {
                return error(id: id, code: -32602, message: "Unknown tool")
            }
            return result(id: id, await call(tool, params["arguments"] as? [String: Any] ?? [:]))
        default:
            return error(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    private func call(_ tool: MCPTool, _ args: [String: Any]) async -> [String: Any] {
        if tool.writes && isReadOnly() {
            return toolResult("EZCal's agent access is read-only. Ask the user to allow changes in EZCal → Settings → Agents.", isError: true)
        }
        do {
            let value = try await tool.run(args)
            return toolResult(Self.text(value), isError: false)
        } catch {
            return toolResult((error as? MCPToolError)?.message ?? error.localizedDescription, isError: true)
        }
    }

    static func text(_ value: Any) -> String {
        if let s = value as? String { return s }
        guard JSONSerialization.isValidJSONObject(value),
              let d = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .prettyPrinted]),
              let s = String(data: d, encoding: .utf8) else { return "\(value)" }
        return s
    }

    private func toolResult(_ text: String, isError: Bool) -> [String: Any] {
        ["content": [["type": "text", "text": text]], "isError": isError]
    }
    private func result(id: Any?, _ r: [String: Any]) -> [String: Any] { ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": r] }
    private func error(id: Any?, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]]
    }
    private func encode(_ v: Any) -> Data? { try? JSONSerialization.data(withJSONObject: v) }
}

// MARK: - Dates in tool arguments / results

enum MCPDate {
    struct Parsed: Equatable { var date: Date; var dateOnly: Bool }

    /// Accepts RFC 3339 (`2026-10-12T14:30:00-06:00`, `…Z`), a local date-time without an offset
    /// (`2026-10-12T14:30[:00]`, `2026-10-12 14:30`), or a bare date (`2026-10-12`, local midnight, `dateOnly`).
    static func parse(_ raw: String, calendar: Calendar = .current) -> Parsed? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if let d = RFC3339.parse(s) { return Parsed(date: d, dateOnly: false) }
        for (format, dateOnly) in [("yyyy-MM-dd'T'HH:mm:ss", false), ("yyyy-MM-dd'T'HH:mm", false),
                                   ("yyyy-MM-dd HH:mm:ss", false), ("yyyy-MM-dd HH:mm", false), ("yyyy-MM-dd", true)] {
            let f = DateFormatter()
            f.calendar = calendar
            f.timeZone = calendar.timeZone
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = format
            f.isLenient = false
            if let d = f.date(from: s) { return Parsed(date: d, dateOnly: dateOnly) }
        }
        return nil
    }

    /// ISO 8601 with the local UTC offset, e.g. `2026-10-12T14:30:00-06:00`.
    static func string(_ d: Date, timeZone: TimeZone = .current) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = timeZone
        f.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        return f.string(from: d)
    }

    static func day(_ d: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

// MARK: - HTTP framing

/// Just enough HTTP/1.1 for a localhost JSON endpoint: one request per connection, `Content-Length` bodies.
struct MCPHTTPRequest: Equatable {
    var method: String
    var path: String
    var headers: [String: String]   // lowercased names
    var body: Data

    enum Parse: Equatable {
        case needMore
        case invalid(String)
        case complete(MCPHTTPRequest)
    }

    static let maxSize = 2 * 1024 * 1024

    static func parse(_ data: Data) -> Parse {
        guard let sep = data.range(of: Data("\r\n\r\n".utf8)) else {
            return data.count > 16 * 1024 ? .invalid("headers too large") : .needMore
        }
        guard let head = String(data: data[..<sep.lowerBound], encoding: .utf8) else { return .invalid("bad headers") }
        var lines = head.components(separatedBy: "\r\n")
        let request = lines.removeFirst().split(separator: " ")
        guard request.count == 3 else { return .invalid("bad request line") }
        var headers: [String: String] = [:]
        for l in lines {
            guard let colon = l.firstIndex(of: ":") else { return .invalid("bad header") }
            headers[l[..<colon].lowercased()] = l[l.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        if headers["transfer-encoding"] != nil { return .invalid("chunked bodies are not supported") }
        let length = Int(headers["content-length"] ?? "0") ?? -1
        guard length >= 0, length <= maxSize else { return .invalid("bad content length") }
        let bodyStart = sep.upperBound
        guard data.count - bodyStart >= length else { return .needMore }
        return .complete(MCPHTTPRequest(method: String(request[0]), path: String(request[1]), headers: headers,
                                        body: data.subdata(in: bodyStart..<(bodyStart + length))))
    }

    static func response(status: Int, body: Data? = nil, extra: [String: String] = [:]) -> Data {
        let reasons = [200: "OK", 202: "Accepted", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden",
                       404: "Not Found", 405: "Method Not Allowed", 413: "Payload Too Large"]
        var head = "HTTP/1.1 \(status) \(reasons[status] ?? "Error")\r\nConnection: close\r\nContent-Length: \(body?.count ?? 0)\r\n"
        if body != nil { head += "Content-Type: application/json\r\n" }
        for (k, v) in extra { head += "\(k): \(v)\r\n" }
        return Data((head + "\r\n").utf8) + (body ?? Data())
    }

    /// `Host` must be loopback and any `Origin` must be too, so a web page can't talk to the server (DNS rebinding / CSRF).
    var isLoopbackOnly: Bool {
        func loopback(_ s: String) -> Bool {
            let host = s.replacingOccurrences(of: "http://", with: "").replacingOccurrences(of: "https://", with: "")
                .split(separator: "/").first.map(String.init) ?? s
            let name = host.hasPrefix("[") ? String(host.dropFirst().prefix { $0 != "]" }) : String(host.split(separator: ":").first ?? "")
            return ["127.0.0.1", "localhost", "::1"].contains(name.lowercased())
        }
        guard let host = headers["host"], loopback(host) else { return false }
        if let origin = headers["origin"], !loopback(origin) { return false }
        return true
    }

    var bearerToken: String? {
        guard let h = headers["authorization"], h.lowercased().hasPrefix("bearer ") else { return nil }
        return String(h.dropFirst(7)).trimmingCharacters(in: .whitespaces)
    }
}

/// Constant-time string comparison for the access token.
func mcpTokensMatch(_ a: String, _ b: String) -> Bool {
    let x = Array(a.utf8), y = Array(b.utf8)
    guard x.count == y.count else { return false }
    var diff: UInt8 = 0
    for i in 0..<x.count { diff |= x[i] ^ y[i] }
    return diff == 0
}
