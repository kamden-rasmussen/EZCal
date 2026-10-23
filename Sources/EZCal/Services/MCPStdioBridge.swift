#if os(macOS)
import Foundation

/// `EZCal --mcp-stdio` (issue #86): a stdio MCP server for clients that can't send an `Authorization` header over
/// HTTP, such as Claude Desktop. It runs in the same signed binary as the app, so it reads the access token from the
/// Keychain without a prompt and forwards each newline-delimited JSON-RPC message to the running app's loopback
/// endpoint. The client's config is then just the executable path: no Node, and no token in a config file.
enum MCPStdioBridge {
    static let flag = "--mcp-stdio"

    static func isRequested(_ arguments: [String] = CommandLine.arguments) -> Bool { arguments.contains(flag) }

    /// Entry point for the flag: serves stdin until the client closes it, then exits. Never shows UI.
    static func run() -> Never {
        while let line = readLine(strippingNewline: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if let reply = forward(Data(trimmed.utf8)) { write(reply) }
        }
        exit(0)
    }

    /// The endpoint and token the app's server is configured with, or why they're unavailable.
    static func target(defaults: UserDefaults = .standard, token: String? = Keychain.get("mcpToken")) -> Result<(URL, String), Failure> {
        guard let token, !token.isEmpty else { return .failure(.noToken) }
        let stored = defaults.integer(forKey: "mcpPort")
        let port = stored > 0 ? stored : 47900
        guard let url = URL(string: "http://127.0.0.1:\(port)/mcp") else { return .failure(.noToken) }
        return .success((url, token))
    }

    enum Failure: Error, Equatable {
        case noToken, unreachable, rejected

        var message: String {
            switch self {
            case .noToken: return "EZCal has no agent access token yet. Open EZCal → Settings → Agents and switch on “Let AI agents use my calendar”."
            case .unreachable: return "Couldn't reach EZCal. Make sure the app is running and “Let AI agents use my calendar” is on in Settings → Agents."
            case .rejected: return "EZCal rejected the access token. Quit and reopen the client; if it persists, check that this is the same EZCal that has agent access switched on."
            }
        }
    }

    /// One request in, one reply line out (nil for notifications, which get none).
    private static func forward(_ body: Data) -> Data? {
        switch target() {
        case .failure(let f): return errorReply(for: body, message: f.message)
        case .success(let (url, token)):
            var req = URLRequest(url: url, timeoutInterval: 120)
            req.httpMethod = "POST"
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            var result: (Data?, HTTPURLResponse?) = (nil, nil)
            let done = DispatchSemaphore(value: 0)
            URLSession.shared.dataTask(with: req) { data, response, _ in
                result = (data, response as? HTTPURLResponse)
                done.signal()
            }.resume()
            done.wait()
            guard let http = result.1 else { return errorReply(for: body, message: Failure.unreachable.message) }
            switch http.statusCode {
            case 200: return result.0.flatMap(compact)
            case 202: return nil
            case 401: return errorReply(for: body, message: Failure.rejected.message)
            default: return errorReply(for: body, message: "EZCal answered HTTP \(http.statusCode).")
            }
        }
    }

    /// stdio framing is one message per line, so drop any pretty-printing from the reply.
    static func compact(_ json: Data) -> Data? {
        guard let obj = try? JSONSerialization.jsonObject(with: json) else { return nil }
        return try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    /// A JSON-RPC error for a request we couldn't deliver; nil when the message had no id (a notification).
    static func errorReply(for request: Data, message: String) -> Data? {
        guard let msg = (try? JSONSerialization.jsonObject(with: request)) as? [String: Any],
              let id = msg["id"], !(id is NSNull) else { return nil }
        let reply: [String: Any] = ["jsonrpc": "2.0", "id": id, "error": ["code": -32000, "message": message]]
        return try? JSONSerialization.data(withJSONObject: reply, options: [.sortedKeys])
    }

    private static func write(_ data: Data) {
        var out = data
        out.append(0x0A)
        FileHandle.standardOutput.write(out)
    }

    /// The `claude_desktop_config.json` entry for this install (Settings → Agents → "Copy config").
    static func claudeDesktopConfig(executable: String) -> String {
        let obj: [String: Any] = ["mcpServers": ["ezcal": ["command": executable, "args": [flag]]]]
        let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}
#endif
