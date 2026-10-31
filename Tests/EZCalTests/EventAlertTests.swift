import XCTest
import EventKit
@testable import EZCal

final class EventAlertTests: XCTestCase {
    func testLabels() {
        XCTAssertEqual(EventAlert.label(0), "At time of event")
        XCTAssertEqual(EventAlert.label(5), "5 minutes before")
        XCTAssertEqual(EventAlert.label(1), "1 minute before")
        XCTAssertEqual(EventAlert.label(60), "1 hour before")
        XCTAssertEqual(EventAlert.label(120), "2 hours before")
        XCTAssertEqual(EventAlert.label(1440), "1 day before")
        XCTAssertEqual(EventAlert.label(10080), "1 week before")
        XCTAssertEqual(EventAlert.label(90), "90 minutes before")
    }

    func testNormalizedSortsDedupesAndCaps() {
        XCTAssertEqual(EventAlert.normalized([30, 5, 5, -3]), [0, 5, 30])
        XCTAssertEqual(EventAlert.normalized([1, 2, 3, 4, 5, 6, 7]).count, EventAlert.maxCount)
    }

    func testEventKitRoundTrip() {
        let alarms = EventAlert.ekAlarms([10, 1440])
        XCTAssertEqual(alarms.map(\.relativeOffset), [-600, -86400])
        XCTAssertEqual(EventAlert.minutes(from: alarms), [10, 1440])
        let absolute = EKAlarm(absoluteDate: Date())
        XCTAssertEqual(EventAlert.minutes(from: alarms + [absolute]), [10, 1440], "absolute alarms are ignored")
        XCTAssertEqual(EventAlert.minutes(from: nil), [])
    }

    func testGoogleMapping() {
        let body = EventAlert.googleReminders([15, 0])
        XCTAssertEqual(body["useDefault"] as? Bool, false)
        let o = body["overrides"] as? [[String: Any]]
        XCTAssertEqual(o?.compactMap { $0["minutes"] as? Int }, [0, 15])
        XCTAssertEqual(o?.first?["method"] as? String, "popup")
        XCTAssertNil(EventAlert.minutes(fromGoogle: true, overrides: nil))
        XCTAssertEqual(EventAlert.minutes(fromGoogle: false, overrides: [("popup", 10), ("email", 60), (nil, 5)]), [5, 10])
    }

    func testChangesOnlyWhenDifferent() {
        XCTAssertNil(EventAlert.changes(draft: nil, existing: [5], isNew: false))
        XCTAssertNil(EventAlert.changes(draft: [5], existing: [5], isNew: false))
        XCTAssertEqual(EventAlert.changes(draft: [10], existing: [5], isNew: false), [10])
        XCTAssertEqual(EventAlert.changes(draft: [], existing: [5], isNew: false), [])
        XCTAssertEqual(EventAlert.changes(draft: [10], existing: nil, isNew: false), [10])
        XCTAssertEqual(EventAlert.changes(draft: [], existing: nil, isNew: true), [])
        XCTAssertNil(EventAlert.changes(draft: nil, existing: nil, isNew: true))
    }

    func testDefaultAlertsSetting() {
        let saved = AppSettings.defaultAlerts
        defer { AppSettings.defaultAlerts = saved }
        AppSettings.defaultAlerts = nil
        XCTAssertNil(AppSettings.defaultAlerts)
        AppSettings.defaultAlerts = []
        XCTAssertEqual(AppSettings.defaultAlerts, [])
        AppSettings.defaultAlerts = [60, 10]
        XCTAssertEqual(AppSettings.defaultAlerts, [10, 60])
    }
}
