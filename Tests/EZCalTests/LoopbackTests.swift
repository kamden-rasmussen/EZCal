import XCTest
@testable import EZCal

final class LoopbackTests: XCTestCase {
    func testCapturesOAuthRedirect() async throws {
        let server = LoopbackServer()
        let port = try await server.start(port: nil)
        defer { server.stop() }
        XCTAssertGreaterThan(port, 0)

        async let callback = server.waitForCallback(timeout: 10)

        // The browser first asks for a favicon-ish path; that must not complete the flow.
        let (_, r404) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/favicon.ico")!)
        XCTAssertEqual((r404 as? HTTPURLResponse)?.statusCode, 404)

        let (body, r) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/?code=abc123&state=xyz")!)
        XCTAssertEqual((r as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(String(data: body, encoding: .utf8)!.contains("signed in"))

        let url = try await callback
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.first { $0.name == "code" }?.value, "abc123")
        XCTAssertEqual(items.first { $0.name == "state" }?.value, "xyz")
    }

    func testFixedPortAndTimeout() async throws {
        let server = LoopbackServer()
        _ = try await server.start(port: 48292)
        defer { server.stop() }
        do {
            _ = try await server.waitForCallback(timeout: 0.3)
            XCTFail("should time out")
        } catch { /* expected */ }
    }
}
