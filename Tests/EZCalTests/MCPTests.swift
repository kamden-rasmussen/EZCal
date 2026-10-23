import XCTest
@testable import EZCal

@MainActor
final class MCPProtocolTests: XCTestCase {
    private func dispatcher(readOnly: Bool = false) -> MCPDispatcher {
        MCPDispatcher(tools: [
            MCPTool(name: "echo", description: "d", schema: ["type": "object"], writes: false) { a in ["got": a["x"] ?? NSNull()] },
            MCPTool(name: "write", description: "d", schema: ["type": "object"], writes: true) { _ in "done" },
            MCPTool(name: "boom", description: "d", schema: ["type": "object"], writes: false) { _ in throw MCPToolError("nope") },
        ], isReadOnly: { readOnly })
    }

    private func call(_ d: MCPDispatcher, _ obj: Any) async -> [String: Any]? {
        let data = try! JSONSerialization.data(withJSONObject: obj)
        guard let out = await d.handle(data) else { return nil }
        return try! JSONSerialization.jsonObject(with: out) as? [String: Any]
    }

    func testInitializeEchoesSupportedVersionAndAdvertisesTools() async {
        let r = await call(dispatcher(), ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "2025-03-26"]])
        let result = r?["result"] as? [String: Any]
        XCTAssertEqual(result?["protocolVersion"] as? String, "2025-03-26")
        XCTAssertNotNil((result?["capabilities"] as? [String: Any])?["tools"])
        XCTAssertEqual(r?["id"] as? Int, 1)
    }

    func testUnknownVersionFallsBackToLatestSupported() async {
        let r = await call(dispatcher(), ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "1999-01-01"]])
        XCTAssertEqual((r?["result"] as? [String: Any])?["protocolVersion"] as? String, MCPDispatcher.supportedVersions[0])
    }

    func testNotificationsGetNoReply() async {
        let r = await call(dispatcher(), ["jsonrpc": "2.0", "method": "notifications/initialized"])
        XCTAssertNil(r)
    }

    func testToolsListAndCall() async {
        let d = dispatcher()
        let list = await call(d, ["jsonrpc": "2.0", "id": "a", "method": "tools/list"])
        let names = ((list?["result"] as? [String: Any])?["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String }
        XCTAssertEqual(names, ["echo", "write", "boom"])

        let r = await call(d, ["jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": ["name": "echo", "arguments": ["x": "hi"]]])
        let result = r?["result"] as? [String: Any]
        XCTAssertEqual(result?["isError"] as? Bool, false)
        let text = ((result?["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        XCTAssertTrue(text.contains("\"got\" : \"hi\""), text)
    }

    func testToolErrorsComeBackAsIsErrorResults() async {
        let r = await call(dispatcher(), ["jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": ["name": "boom"]])
        let result = r?["result"] as? [String: Any]
        XCTAssertEqual(result?["isError"] as? Bool, true)
        XCTAssertEqual(((result?["content"] as? [[String: Any]])?.first?["text"] as? String), "nope")
    }

    func testReadOnlyModeRefusesWritingTools() async {
        let d = dispatcher(readOnly: true)
        let w = await call(d, ["jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": ["name": "write"]])
        XCTAssertEqual((w?["result"] as? [String: Any])?["isError"] as? Bool, true)
        let ok = await call(d, ["jsonrpc": "2.0", "id": 5, "method": "tools/call", "params": ["name": "echo", "arguments": [:]]])
        XCTAssertEqual((ok?["result"] as? [String: Any])?["isError"] as? Bool, false)
    }

    func testProtocolErrors() async {
        let unknownMethod = await call(dispatcher(), ["jsonrpc": "2.0", "id": 6, "method": "nope"])
        XCTAssertEqual((unknownMethod?["error"] as? [String: Any])?["code"] as? Int, -32601)
        let unknownTool = await call(dispatcher(), ["jsonrpc": "2.0", "id": 7, "method": "tools/call", "params": ["name": "zzz"]])
        XCTAssertEqual((unknownTool?["error"] as? [String: Any])?["code"] as? Int, -32602)
        let parse = await dispatcher().handle(Data("{not json".utf8))
        let parsed = parse.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        XCTAssertEqual((parsed?["error"] as? [String: Any])?["code"] as? Int, -32700)
    }

    func testBatchRepliesOnlyToRequests() async {
        let d = dispatcher()
        let data = try! JSONSerialization.data(withJSONObject: [
            ["jsonrpc": "2.0", "id": 1, "method": "ping"],
            ["jsonrpc": "2.0", "method": "notifications/initialized"],
        ])
        let out = await d.handle(data)
        let arr = out.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] }
        XCTAssertEqual(arr?.count, 1)
    }
}

final class MCPHTTPTests: XCTestCase {
    private func parse(_ s: String) -> MCPHTTPRequest.Parse { MCPHTTPRequest.parse(Data(s.utf8)) }

    func testParsesACompleteRequest() {
        let body = "{\"a\":1}"
        guard case .complete(let r) = parse("POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:47900\r\nAuthorization: Bearer abc\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)") else { return XCTFail() }
        XCTAssertEqual(r.method, "POST")
        XCTAssertEqual(r.path, "/mcp")
        XCTAssertEqual(r.bearerToken, "abc")
        XCTAssertEqual(String(data: r.body, encoding: .utf8), body)
    }

    func testWaitsForTheRestOfTheBody() {
        XCTAssertEqual(parse("POST /mcp HTTP/1.1\r\nContent-Length: 10\r\n\r\nabc"), .needMore)
        XCTAssertEqual(parse("POST /mcp HTTP/1.1\r\nContent-Le"), .needMore)
    }

    func testRejectsChunkedAndGarbage() {
        guard case .invalid = parse("POST /mcp HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n") else { return XCTFail() }
        guard case .invalid = parse("nonsense\r\n\r\n") else { return XCTFail() }
        guard case .invalid = parse("POST /mcp HTTP/1.1\r\nContent-Length: 99999999\r\n\r\n") else { return XCTFail() }
    }

    func testOnlyLoopbackHostsAndOriginsAreAllowed() {
        func req(_ h: [String: String]) -> MCPHTTPRequest { MCPHTTPRequest(method: "POST", path: "/mcp", headers: h, body: Data()) }
        XCTAssertTrue(req(["host": "127.0.0.1:47900"]).isLoopbackOnly)
        XCTAssertTrue(req(["host": "localhost:47900", "origin": "http://localhost:3000"]).isLoopbackOnly)
        XCTAssertTrue(req(["host": "[::1]:47900"]).isLoopbackOnly)
        XCTAssertFalse(req(["host": "evil.example"]).isLoopbackOnly)
        XCTAssertFalse(req(["host": "127.0.0.1:47900", "origin": "https://evil.example"]).isLoopbackOnly)
        XCTAssertFalse(req([:]).isLoopbackOnly)
    }

    func testTokenComparison() {
        XCTAssertTrue(mcpTokensMatch("abc123", "abc123"))
        XCTAssertFalse(mcpTokensMatch("abc123", "abc124"))
        XCTAssertFalse(mcpTokensMatch("abc", "abc123"))
    }

    func testResponseFraming() {
        let r = String(data: MCPHTTPRequest.response(status: 200, body: Data("{}".utf8)), encoding: .utf8)!
        XCTAssertTrue(r.hasPrefix("HTTP/1.1 200 OK\r\n"))
        XCTAssertTrue(r.contains("Content-Length: 2\r\n"))
        XCTAssertTrue(r.hasSuffix("\r\n\r\n{}"))
    }
}

final class MCPDateTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Denver")!
        return c
    }

    func testParsesOffsetLocalAndDateOnly() {
        let withOffset = MCPDate.parse("2026-10-12T14:30:00-06:00", calendar: cal)
        XCTAssertEqual(withOffset?.dateOnly, false)
        let local = MCPDate.parse("2026-10-12T14:30", calendar: cal)
        XCTAssertEqual(local?.date, withOffset?.date)   // Denver is UTC-6 in October (MDT: -06:00)
        let day = MCPDate.parse("2026-10-12", calendar: cal)
        XCTAssertEqual(day?.dateOnly, true)
        XCTAssertEqual(cal.component(.hour, from: day!.date), 0)
        XCTAssertNil(MCPDate.parse("next tuesday", calendar: cal))
        XCTAssertNil(MCPDate.parse("2026-13-40", calendar: cal))
    }

    func testFormatsWithOffset() {
        let d = MCPDate.parse("2026-10-12T14:30:00-06:00", calendar: cal)!.date
        XCTAssertEqual(MCPDate.string(d, timeZone: cal.timeZone), "2026-10-12T14:30:00-06:00")
        XCTAssertEqual(MCPDate.day(d, calendar: cal), "2026-10-12")
    }
}

@MainActor
final class MCPToolsTests: XCTestCase {
    private func store() -> CalendarStore {
        let s = CalendarStore()
        s.calendars = [
            Source(id: "cal|a@x.com|a@x.com", accountId: "a@x.com", calendarId: "a@x.com", name: "Work", colorHex: "#336699", kind: .calendar, accessRole: "owner"),
            Source(id: "ek|home", accountId: "ek:iCloud", calendarId: "home", name: "Home", colorHex: "#339966", kind: .calendar, accessRole: "owner"),
            Source(id: "ics|holidays", accountId: "ics", calendarId: "holidays", name: "Holidays", colorHex: "#999999", kind: .calendar, accessRole: "reader"),
        ]
        return s
    }

    private func run(_ s: CalendarStore, _ tool: String, _ args: [String: Any]) async -> (text: String, isError: Bool) {
        let d = MCPDispatcher(tools: MCPTools.all(store: s))
        let body = try! JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": tool, "arguments": args]])
        let out = await d.handle(body)!
        let r = (try! JSONSerialization.jsonObject(with: out) as! [String: Any])["result"] as! [String: Any]
        return (((r["content"] as! [[String: Any]])[0]["text"] as! String), r["isError"] as! Bool)
    }

    func testEveryToolIsListedAndWritesAreFlagged() {
        let tools = MCPTools.all(store: store())
        XCTAssertEqual(Set(tools.map(\.name)), ["list_calendars", "list_events", "get_event", "create_event", "update_event", "delete_event", "find_free_time",
                                                   "list_reminder_lists", "list_reminders", "create_reminder", "update_reminder", "delete_reminder"])
        XCTAssertEqual(Set(tools.filter(\.writes).map(\.name)), ["create_event", "update_event", "delete_event", "create_reminder", "update_reminder", "delete_reminder"])
    }

    func testToolsCarryTitlesAndBehaviourHints() {
        let tools = Dictionary(uniqueKeysWithValues: MCPTools.all(store: store()).map { ($0.name, MCPDispatcher.listing($0)) })
        for (name, t) in tools { XCTAssertNotNil(t["title"], name) }
        func hints(_ n: String) -> [String: Any] { tools[n]!["annotations"] as! [String: Any] }
        for n in ["list_calendars", "list_events", "get_event", "find_free_time"] {
            XCTAssertEqual(hints(n)["readOnlyHint"] as? Bool, true, n)
            XCTAssertNil(hints(n)["destructiveHint"], n)
        }
        XCTAssertEqual(hints("create_event")["readOnlyHint"] as? Bool, false)
        XCTAssertEqual(hints("create_event")["destructiveHint"] as? Bool, false)
        for n in ["update_event", "delete_event"] {
            XCTAssertEqual(hints(n)["readOnlyHint"] as? Bool, false, n)
            XCTAssertEqual(hints(n)["destructiveHint"] as? Bool, true, n)
        }
    }

    func testUpdateAndDeleteRequireTheCurrentEventState() {
        let tools = Dictionary(uniqueKeysWithValues: MCPTools.all(store: store()).map { ($0.name, $0) })
        for n in ["update_event", "delete_event"] {
            XCTAssertEqual(Set(tools[n]!.schema["required"] as! [String]), ["event_id", "current_title", "current_start"], n)
        }
        XCTAssertNotNil((tools["update_event"]!.schema["properties"] as! [String: Any])["calendar_id"])
    }

    func testReminderToolsNeedRemindersSwitchedOn() async {
        let s = store()
        s.tasks.enabled = false
        for (tool, args) in [("list_reminder_lists", [:]), ("list_reminders", [:]), ("create_reminder", ["title": "x"]),
                             ("update_reminder", ["reminder_id": "r", "current_title": "x"]), ("delete_reminder", ["reminder_id": "r", "current_title": "x"])] as [(String, [String: Any])] {
            let r = await run(s, tool, args)
            XCTAssertTrue(r.isError, tool)
            XCTAssertTrue(r.text.contains("Reminders isn't switched on"), "\(tool): \(r.text)")
        }
    }

    func testReminderWritesAreDestructiveOnlyForUpdateAndDelete() {
        let tools = Dictionary(uniqueKeysWithValues: MCPTools.all(store: store()).map { ($0.name, MCPDispatcher.listing($0)) })
        func hints(_ n: String) -> [String: Any] { tools[n]!["annotations"] as! [String: Any] }
        XCTAssertEqual(hints("list_reminders")["readOnlyHint"] as? Bool, true)
        XCTAssertEqual(hints("create_reminder")["destructiveHint"] as? Bool, false)
        XCTAssertEqual(hints("update_reminder")["destructiveHint"] as? Bool, true)
        XCTAssertEqual(hints("delete_reminder")["destructiveHint"] as? Bool, true)
    }

    func testListCalendarsReportsKindAndWritable() async throws {
        let (text, isError) = await run(store(), "list_calendars", [:])
        XCTAssertFalse(isError)
        let cals = (try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any])["calendars"] as! [[String: Any]]
        XCTAssertEqual(cals.map { $0["kind"] as! String }, ["google", "eventkit", "ics"])
        XCTAssertEqual(cals.map { $0["writable"] as! Bool }, [true, true, false])
    }

    func testCreateRejectsBadInputWithoutTouchingAnything() async {
        let s = store()
        var r = await run(s, "create_event", ["start": "2026-10-12T10:00:00-06:00"])
        XCTAssertTrue(r.isError); XCTAssertTrue(r.text.contains("title"))
        r = await run(s, "create_event", ["title": "x", "start": "soon"])
        XCTAssertTrue(r.isError); XCTAssertTrue(r.text.contains("ISO 8601"))
        r = await run(s, "create_event", ["title": "x", "start": "2026-10-12T10:00:00-06:00", "calendar_id": "nope"])
        XCTAssertTrue(r.isError); XCTAssertTrue(r.text.contains("Unknown calendar"))
        r = await run(s, "create_event", ["title": "x", "start": "2026-10-12T10:00:00-06:00", "calendar_id": "ics|holidays"])
        XCTAssertTrue(r.isError); XCTAssertTrue(r.text.contains("read-only"))
        r = await run(s, "create_event", ["title": "x", "start": "2026-10-12T10:00:00-06:00", "end": "2026-10-12T09:00:00-06:00", "calendar_id": "ek|home"])
        XCTAssertTrue(r.isError); XCTAssertTrue(r.text.contains("after"))
        r = await run(s, "create_event", ["title": "x", "start": "2026-10-12T10:00:00-06:00", "calendar_id": "ek|home", "recurrence": "yearly"])
        XCTAssertTrue(r.isError); XCTAssertTrue(r.text.contains("recurrence"))
    }

    func testUnknownEventIdsAreClearNotFoundErrors() async {
        let s = CalendarStore()
        for tool in ["get_event", "update_event", "delete_event"] {
            let r = await run(s, tool, ["event_id": "cal|a|a|e1|1790000000"])
            XCTAssertTrue(r.isError, tool)
            XCTAssertTrue(r.text.contains("No event with id"), "\(tool): \(r.text)")
        }
    }

    func testListEventsValidatesTheWindow() async {
        let s = store()
        var r = await run(s, "list_events", ["start": "2026-10-12", "end": "2026-10-11"])
        XCTAssertTrue(r.isError)
        r = await run(s, "list_events", ["start": "2026-01-01", "end": "2026-12-31"])
        XCTAssertTrue(r.isError); XCTAssertTrue(r.text.contains("62 days"))
        r = await run(s, "list_events", ["start": "2026-10-12", "end": "2026-10-13", "calendar_ids": ["zzz"]])
        XCTAssertTrue(r.isError); XCTAssertTrue(r.text.contains("Unknown calendar"))
    }

    func testFindFreeTimeValidatesArguments() async {
        let s = store()
        var r = await run(s, "find_free_time", ["duration_minutes": 0, "start": "2026-10-12", "end": "2026-10-14"])
        XCTAssertTrue(r.isError)
        r = await run(s, "find_free_time", ["duration_minutes": 30, "start": "2026-10-12", "end": "2026-12-14"])
        XCTAssertTrue(r.isError); XCTAssertTrue(r.text.contains("30 days"))
    }
}

final class MCPStdioBridgeTests: XCTestCase {
    private func json(_ d: Data?) -> [String: Any]? {
        d.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    func testFlagDetection() {
        XCTAssertTrue(MCPStdioBridge.isRequested(["EZCal", "--mcp-stdio"]))
        XCTAssertFalse(MCPStdioBridge.isRequested(["EZCal"]))
    }

    func testUndeliverableRequestsGetAJSONRPCError() {
        let req = Data(#"{"jsonrpc":"2.0","id":7,"method":"tools/list"}"#.utf8)
        let r = json(MCPStdioBridge.errorReply(for: req, message: "down"))
        XCTAssertEqual(r?["id"] as? Int, 7)
        XCTAssertEqual((r?["error"] as? [String: Any])?["message"] as? String, "down")
    }

    func testNotificationsGetNoErrorReply() {
        let note = Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8)
        XCTAssertNil(MCPStdioBridge.errorReply(for: note, message: "down"))
    }

    func testRepliesAreCompactedToOneLine() {
        let pretty = Data("{\n  \"a\": 1,\n  \"b\": [1, 2]\n}".utf8)
        let line = MCPStdioBridge.compact(pretty).flatMap { String(data: $0, encoding: .utf8) }
        XCTAssertEqual(line, #"{"a":1,"b":[1,2]}"#)
    }

    func testTargetNeedsATokenAndHonoursThePort() throws {
        let d = UserDefaults(suiteName: "MCPStdioBridgeTests")!
        d.removePersistentDomain(forName: "MCPStdioBridgeTests")
        XCTAssertEqual(MCPStdioBridge.target(defaults: d, token: nil).failureValue, .noToken)
        XCTAssertEqual(try MCPStdioBridge.target(defaults: d, token: "t").get().0.absoluteString, "http://127.0.0.1:47900/mcp")
        d.set(48001, forKey: "mcpPort")
        XCTAssertEqual(try MCPStdioBridge.target(defaults: d, token: "t").get().0.port, 48001)
    }

    func testDesktopConfigPointsAtTheBinaryWithoutAToken() throws {
        let cfg = MCPStdioBridge.claudeDesktopConfig(executable: "/Applications/EZCal.app/Contents/MacOS/EZCal")
        let obj = try JSONSerialization.jsonObject(with: Data(cfg.utf8)) as? [String: Any]
        let entry = (obj?["mcpServers"] as? [String: Any])?["ezcal"] as? [String: Any]
        XCTAssertEqual(entry?["command"] as? String, "/Applications/EZCal.app/Contents/MacOS/EZCal")
        XCTAssertEqual(entry?["args"] as? [String], ["--mcp-stdio"])
        XCTAssertFalse(cfg.lowercased().contains("bearer"))
    }
}

private extension Result {
    var failureValue: Failure? { if case .failure(let e) = self { return e }; return nil }
}
