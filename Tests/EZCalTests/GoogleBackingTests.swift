import XCTest
@testable import EZCal

final class GoogleBackingTests: XCTestCase {
    func testGoogleUIDSuffix() {
        XCTAssertTrue(GoogleBacking.isGoogleUID("abc123def456@google.com"))
        XCTAssertTrue(GoogleBacking.isGoogleUID("abc123def456_R20250416T010000@GOOGLE.COM"))
        XCTAssertFalse(GoogleBacking.isGoogleUID("DFBB5E62-FAA0-48DE-A61E-969BF2F7692C"))
        XCTAssertFalse(GoogleBacking.isGoogleUID(nil))
    }

    func testMatchesConnectedAccount() {
        let accts = [Account(email: "me@example.com"), Account(email: "jane.doe@gmail.com")]
        XCTAssertEqual(GoogleBacking.matchesConnectedAccount(["ME@example.com"], accounts: accts)?.email, "me@example.com")
        XCTAssertEqual(GoogleBacking.matchesConnectedAccount(["jane.doe", "Holidays"], accounts: accts)?.email, "jane.doe@gmail.com")
        XCTAssertNil(GoogleBacking.matchesConnectedAccount(["iCloud"], accounts: accts))
    }
}
