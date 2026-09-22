import XCTest
import Network
@testable import EZCal

/// A tiny loopback HTTP server for exercising `ICSService`'s real networking path (conditional GET,
/// caching, error fallback) without hitting the network. Each request is answered by `handler`, which
/// receives the incoming request headers and returns a status code, response headers and body.
private final class ICSTestServer: @unchecked Sendable {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "ezcal.icstest")
    var handler: (@Sendable ([String: String]) -> (Int, [String: String], Data))?

    /// Tiny mutable box so the state-update handler below doesn't need to capture a `var` across
    /// concurrent invocations (which the Swift 6 concurrency checker flags even though the listener
    /// only ever calls it serially on `queue`).
    private final class ResumeFlag: @unchecked Sendable { var done = false }

    func start() async throws -> UInt16 {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
        params.allowLocalEndpointReuse = true
        let l = try NWListener(using: params)
        listener = l
        let flag = ResumeFlag()
        let port: UInt16 = try await withCheckedThrowingContinuation { cont in
            l.stateUpdateHandler = { state in
                guard !flag.done else { return }
                switch state {
                case .ready: flag.done = true; cont.resume(returning: l.port?.rawValue ?? 0)
                case .failed(let e): flag.done = true; cont.resume(throwing: e)
                default: break
                }
            }
            l.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
            l.start(queue: queue)
        }
        return port
    }

    func stop() { listener?.cancel(); listener = nil }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, _ in
            guard let self, let data, let text = String(data: data, encoding: .utf8) else { conn.cancel(); return }
            var headers: [String: String] = [:]
            for line in text.split(separator: "\r\n").dropFirst() {
                let parts = line.split(separator: ":", maxSplits: 1)
                if parts.count == 2 { headers[String(parts[0]).trimmingCharacters(in: .whitespaces)] = String(parts[1]).trimmingCharacters(in: .whitespaces) }
            }
            let (status, respHeaders, body) = self.handler?(headers) ?? (500, [:], Data())
            let statusText = ["200": "OK", "304": "Not Modified", "404": "Not Found"][String(status)] ?? "Error"
            var headerLines = respHeaders.map { "\($0.key): \($0.value)" }.joined(separator: "\r\n")
            if !headerLines.isEmpty { headerLines += "\r\n" }
            var resp = Data("HTTP/1.1 \(status) \(statusText)\r\n\(headerLines)Content-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
            resp.append(body)
            conn.send(content: resp, completion: .contentProcessed { _ in conn.cancel() })
        }
    }
}

/// Mutable counter shared with a `@Sendable` server handler closure; the handler only ever runs
/// serially on the test server's own queue, so plain mutation is safe despite the `Sendable` bound.
private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

final class ICSServiceTests: XCTestCase {
    private func source(_ url: URL, name: String = "Feed") -> Source {
        Source(id: "ics|\(ICSService.cacheKey(for: url))", accountId: "ics", calendarId: url.absoluteString,
               name: name, colorHex: "#3E63DD", kind: .calendar)
    }

    private let dayRange: Range<Date> = {
        let c = Calendar(identifier: .gregorian)
        let s = c.date(from: DateComponents(year: 2020, month: 1, day: 1))!
        let e = c.date(from: DateComponents(year: 2030, month: 1, day: 1))!
        return s..<e
    }()

    private let sampleICS = """
    BEGIN:VCALENDAR
    BEGIN:VEVENT
    UID:1@example.com
    SUMMARY:Season opener
    DTSTART:20260410T180000Z
    DTEND:20260410T210000Z
    LOCATION:Stadium
    END:VEVENT
    END:VCALENDAR
    """

    func testFetchesParsesAndCachesEvents() async throws {
        let server = ICSTestServer()
        let port = try await server.start()
        defer { server.stop() }
        let body = Data(sampleICS.utf8)
        server.handler = { _ in (200, ["ETag": "\"v1\""], body) }

        let url = URL(string: "http://127.0.0.1:\(port)/cal.ics")!
        let src = source(url)
        let (events, error) = await ICSService.shared.fetchAndParse(src, range: dayRange)

        XCTAssertNil(error)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.title, "Season opener")
        XCTAssertEqual(events.first?.location, "Stadium")
        XCTAssertEqual(events.first?.sourceId, src.id)
        XCTAssertFalse(events.first!.canEdit)   // subscriptions are always read-only
    }

    func testConditionalGETSendsETagAndHandles304() async throws {
        let server = ICSTestServer()
        let port = try await server.start()
        defer { server.stop() }
        let body = Data(sampleICS.utf8)
        let sawIfNoneMatch = Box<String?>(nil)
        let requestCount = Box(0)
        server.handler = { headers in
            requestCount.value += 1
            if requestCount.value == 1 { return (200, ["ETag": "\"abc\""], body) }
            sawIfNoneMatch.value = headers["If-None-Match"]
            return (304, [:], Data())
        }

        let url = URL(string: "http://127.0.0.1:\(port)/etag.ics")!
        let src = source(url)

        let first = await ICSService.shared.fetchAndParse(src, range: dayRange)
        XCTAssertEqual(first.events.count, 1)

        let second = await ICSService.shared.fetchAndParse(src, range: dayRange)
        XCTAssertNil(second.error)
        XCTAssertEqual(second.events.count, 1, "a 304 should still return the cached body's events")
        XCTAssertEqual(sawIfNoneMatch.value, "\"abc\"", "the second request should present the ETag from the first response")
        XCTAssertEqual(requestCount.value, 2)
    }

    func testServerErrorFallsBackToLastGoodCacheAndReportsError() async throws {
        let server = ICSTestServer()
        let port = try await server.start()
        defer { server.stop() }
        let body = Data(sampleICS.utf8)
        let requestCount = Box(0)
        server.handler = { _ in
            requestCount.value += 1
            return requestCount.value == 1 ? (200, [:], body) : (500, [:], Data())
        }

        let url = URL(string: "http://127.0.0.1:\(port)/flaky.ics")!
        let src = source(url)

        let good = await ICSService.shared.fetchAndParse(src, range: dayRange)
        XCTAssertNil(good.error)
        XCTAssertEqual(good.events.count, 1)

        let broken = await ICSService.shared.fetchAndParse(src, range: dayRange)
        XCTAssertNotNil(broken.error, "a server error should be surfaced")
        XCTAssertEqual(broken.events.count, 1, "but the previously-cached events should still be shown, not blanked out")
    }

    func testMissingFeedReturnsNoEventsAndAnError() async throws {
        let server = ICSTestServer()
        let port = try await server.start()
        defer { server.stop() }
        server.handler = { _ in (404, [:], Data()) }

        let url = URL(string: "http://127.0.0.1:\(port)/missing.ics")!
        let (events, error) = await ICSService.shared.fetchAndParse(source(url), range: dayRange)
        XCTAssertTrue(events.isEmpty)
        XCTAssertNotNil(error)
    }

    func testNormalizeURLAcceptsWebcalAndRejectsGarbage() {
        XCTAssertEqual(ICSService.normalizeURL("webcal://example.com/team.ics")?.scheme, "https")
        XCTAssertEqual(ICSService.normalizeURL("https://example.com/team.ics")?.absoluteString, "https://example.com/team.ics")
        XCTAssertNil(ICSService.normalizeURL("not a url"))
        XCTAssertNil(ICSService.normalizeURL("ftp://example.com/team.ics"))
        XCTAssertNil(ICSService.normalizeURL(""))
    }
}
