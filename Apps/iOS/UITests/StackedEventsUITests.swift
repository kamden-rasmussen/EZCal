import XCTest

/// #122: the same meeting on several calendars is ONE stacked card; genuinely different overlapping events still
/// split; the overlap layout setting changes how they're laid out. Demo data puts "Team planning" on three
/// calendars (stacked) with an overlapping "Vendor call" on Sundays.
final class StackedEventsUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["EZCAL_DEMO"] = "1"
        app.launch()
    }

    private func anyEl(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func all(_ id: String) -> XCUIElementQuery { app.descendants(matching: .any).matching(identifier: id) }

    /// Day tab, stepping day by day until the Sunday that holds the stacked demo meeting.
    private func goToStackDay() {
        let b = app.segmentedControls["tabPicker"].buttons["Day"]
        XCTAssertTrue(b.waitForExistence(timeout: 10))
        b.tap()
        for _ in 0..<8 {
            if anyEl("dayStackedEvent").waitForExistence(timeout: 1) { return }
            app.buttons["nextButton"].tap()
        }
        XCTFail("no stacked event in the next week")
    }

    private func setOverlapMode(_ name: String) {
        app.buttons["menuButton"].tap()
        app.buttons["settingsButton"].tap()
        let p = anyEl("overlapLayoutPicker")
        for _ in 0..<6 where !(p.exists && p.isHittable) { app.swipeUp() }
        XCTAssertTrue(p.exists, "overlap picker missing")
        p.tap()
        app.buttons[name].firstMatch.tap()
        for _ in 0..<6 where !app.buttons["settingsDoneButton"].isHittable { app.swipeDown() }
        app.buttons["settingsDoneButton"].tap()
    }

    func testStackedCardAppearsOnceForMultiCalendarMeeting() throws {
        goToStackDay()
        XCTAssertEqual(all("dayStackedEvent").count, 1, "three copies must fold into one card")
        XCTAssertEqual(anyEl("dayStackedEvent").label, "Team planning, on 3 calendars")
        let copies = all("dayEvent").allElementsBoundByIndex.filter { $0.label == "Team planning" }
        XCTAssertTrue(copies.isEmpty, "individual copies must not be drawn separately")
    }

    func testTappingStackListsCalendarsAndOpensEvent() throws {
        goToStackDay()
        anyEl("dayStackedEvent").tap()
        XCTAssertTrue(anyEl("stackCalendarsHeader").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["On 3 calendars"].exists || anyEl("stackCalendarsHeader").label.localizedCaseInsensitiveContains("On 3 calendars"))
        XCTAssertEqual(all("stackCalendarRow").count, 3)
        for name in ["Me", "Team", "Home"] { XCTAssertTrue(app.buttons["\(name), open event"].exists, "\(name) missing") }
        app.buttons["Team, open event"].tap()
        XCTAssertTrue(app.staticTexts["detailTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["detailTitle"].label, "Team planning")
        app.buttons["doneButton"].tap()
    }

    func testGenuinelyOverlappingEventStillSplitsSideBySide() throws {
        goToStackDay()
        let vendor = all("dayEvent").allElementsBoundByIndex.first { $0.label == "Vendor call" }
        XCTAssertNotNil(vendor, "Vendor call missing")
        let stack = anyEl("dayStackedEvent")
        XCTAssertLessThanOrEqual(stack.frame.maxX, vendor!.frame.minX + 4, "side by side: columns must not overlap")
        XCTAssertGreaterThan(vendor!.frame.minX, stack.frame.minX)
    }

    func testOverlapModeSettingChangesLayout() throws {
        goToStackDay()
        setOverlapMode("Overlap (cascade)")
        let vendor = all("dayEvent").allElementsBoundByIndex.first { $0.label == "Vendor call" }
        XCTAssertNotNil(vendor)
        let stack = anyEl("dayStackedEvent")
        XCTAssertLessThan(vendor!.frame.minX, stack.frame.maxX - 20, "cascade: the later card overlays the stack")
        XCTAssertGreaterThan(vendor!.frame.width, stack.frame.width * 0.5, "cascade: cards stay wide")
        setOverlapMode("Side by side")
        let v2 = all("dayEvent").allElementsBoundByIndex.first { $0.label == "Vendor call" }!
        XCTAssertLessThanOrEqual(anyEl("dayStackedEvent").frame.maxX, v2.frame.minX + 4)
    }
}
