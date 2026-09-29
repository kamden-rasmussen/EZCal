import XCTest
@testable import EZCal

@MainActor
final class UpdateCheckerTests: XCTestCase {
    private func release(_ tag: String, draft: Bool = false, pre: Bool = false) -> GitHubRelease {
        GitHubRelease(tagName: tag, draft: draft, prerelease: pre)
    }

    func testVersionParsing() {
        XCTAssertEqual(SemVer("1.2.3")?.parts, [1, 2, 3])
        XCTAssertEqual(SemVer("2")?.parts, [2])
        XCTAssertNil(SemVer(""))
        XCTAssertNil(SemVer("1..2"))
        XCTAssertNil(SemVer("1.2.3.4"))
        XCTAssertNil(SemVer("1.2.x"))
        XCTAssertNil(SemVer("1.2.3-beta"))
        XCTAssertNil(SemVer("v1.2.3"))
    }

    func testNumericComparison() {
        XCTAssertTrue(SemVer("1.10.0")! > SemVer("1.9.0")!)
        XCTAssertTrue(SemVer("1.0.1")! > SemVer("1.0.0")!)
        XCTAssertTrue(SemVer("2.0.0")! > SemVer("1.99.99")!)
        XCTAssertEqual(SemVer("1.0")!, SemVer("1.0.0")!)
        XCTAssertFalse(SemVer("1.0.0")! < SemVer("1.0.0")!)
    }

    func testTagFilteringPicksHighestEzcalRelease() {
        let releases = [
            release("ezcal-v1.9.0"), release("ezcal-v1.10.0"),
            release("other-v9.0.0"),                 // another app in the tap
            release("ezcal-v3.0.0", draft: true),
            release("ezcal-v4.0.0", pre: true),
            release("ezcal-vbogus"), release("v5.0.0"),
        ]
        XCTAssertEqual(UpdateChecker.latestVersion(in: releases), SemVer("1.10.0"))
        XCTAssertNil(UpdateChecker.latestVersion(in: [release("other-v1.0.0")]))
        XCTAssertNil(UpdateChecker.latestVersion(in: []))
    }

    private func json(_ tags: [String]) -> Data {
        let items = tags.map { "{\"tag_name\":\"\($0)\",\"draft\":false,\"prerelease\":false,\"name\":\"x\"}" }
        return Data("[\(items.joined(separator: ","))]".utf8)
    }

    func testDetectsNewerVersion() async {
        let data = json(["ezcal-v1.10.0", "ezcal-v1.9.0"])
        let c = UpdateChecker(currentVersion: "1.9.0", fetch: { data })
        await c.check()
        XCTAssertEqual(c.status, .available(SemVer("1.10.0")!))
        XCTAssertEqual(c.availableVersion, SemVer("1.10.0"))
    }

    func testUpToDate() async {
        let data = json(["ezcal-v1.9.0", "ezcal-v1.10.0"])
        let c = UpdateChecker(currentVersion: "1.10.0", fetch: { data })
        await c.check()
        XCTAssertEqual(c.status, .upToDate)
        XCTAssertNil(c.availableVersion)
    }

    func testAutomaticFailureIsSilentAndManualFailureIsReported() async {
        let c = UpdateChecker(currentVersion: "1.0.0", fetch: { throw URLError(.notConnectedToInternet) })
        await c.check()
        XCTAssertEqual(c.status, .idle)
        await c.check(manual: true)
        XCTAssertEqual(c.status, .failed)
    }

    func testFailedAutomaticCheckKeepsKnownUpdate() async {
        let data = json(["ezcal-v1.1.0"])
        final class Flag: @unchecked Sendable { var fail = false }
        let flag = Flag()
        let c = UpdateChecker(currentVersion: "1.0.0", fetch: {
            if flag.fail { throw URLError(.timedOut) }
            return data
        })
        await c.check()
        flag.fail = true
        await c.check()
        XCTAssertEqual(c.availableVersion, SemVer("1.1.0"))
        XCTAssertEqual(c.status, .available(SemVer("1.1.0")!))
    }
}
