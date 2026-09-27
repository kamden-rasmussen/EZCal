import XCTest

final class EZCaliOSUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["EZCAL_DEMO"] = "1"
        app.launch()
    }

    private var picker: XCUIElement { app.segmentedControls["tabPicker"] }
    private func selectTab(_ name: String) {
        let b = picker.buttons[name]
        XCTAssertTrue(b.waitForExistence(timeout: 10))
        b.tap()
    }
    private func anyEl(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private var dayTitle: XCUIElement { app.staticTexts["dayTitle"] }

    /// Saturday events in demo data are day 5 of the week; we just need a day with events, so use Today.
    func testAgendaShowsEventsAndDetailSheet() throws {
        let row = app.buttons.matching(identifier: "agendaRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let title = app.staticTexts["detailTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        app.buttons["doneButton"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
        XCTAssertTrue(row.exists)
    }

    func testTabSwitchAndNavigation() throws {
        selectTab("Day")
        XCTAssertTrue(dayTitle.waitForExistence(timeout: 5))
        let today = dayTitle.label
        app.buttons["nextButton"].tap()
        XCTAssertNotEqual(dayTitle.label, today)
        app.buttons["prevButton"].tap()
        XCTAssertEqual(dayTitle.label, today)
        app.buttons["prevButton"].tap()
        let prev = dayTitle.label
        XCTAssertNotEqual(prev, today)
        app.buttons["todayButton"].tap()
        XCTAssertEqual(dayTitle.label, today)
        selectTab("Agenda")
        XCTAssertTrue(app.otherElements["agendaList"].exists || app.collectionViews["agendaList"].exists)
    }

    func testAgendaNextChangesContent() throws {
        let list = app.collectionViews["agendaList"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        let before = list.staticTexts.firstMatch.label
        for _ in 0..<2 { app.buttons["nextButton"].tap() }
        // Agenda starts at the anchor, so the first section header moves.
        XCTAssertNotEqual(list.staticTexts.firstMatch.label, before)
        app.buttons["todayButton"].tap()
        XCTAssertEqual(list.staticTexts.firstMatch.label, before)
    }

    func testDayEventBlockOpensDetail() throws {
        selectTab("Day")
        // Move forward until a timed event block is visible (demo data is week-relative).
        var found = false
        for _ in 0..<7 {
            if anyEl("dayEvent").waitForExistence(timeout: 1) { found = true; break }
            app.buttons["nextButton"].tap()
        }
        XCTAssertTrue(found, "no timed events in the next week")
        anyEl("dayEvent").tap()
        XCTAssertTrue(app.staticTexts["detailTitle"].waitForExistence(timeout: 5))
        app.buttons["doneButton"].tap()
        XCTAssertTrue(app.staticTexts["detailTitle"].waitForNonExistence(timeout: 5))
    }

    func testEmptyDayInDayView() throws {
        selectTab("Day")
        // Demo data spans -1...+1 weeks; 30 days out is guaranteed empty.
        for _ in 0..<30 { app.buttons["nextButton"].tap() }
        XCTAssertTrue(dayTitle.exists)
        XCTAssertFalse(anyEl("dayEvent").exists)
        XCTAssertFalse(anyEl("allDayEvent").exists)
        app.buttons["todayButton"].tap()
    }

    func testDayScrollEndsWithLastHourVisible() throws {
        selectTab("Day")
        let grid = app.scrollViews.firstMatch
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        for _ in 0..<6 { grid.swipeUp(velocity: .fast) }
        let hour = anyEl("hour-23")
        XCTAssertTrue(hour.waitForExistence(timeout: 3), "23:00 row missing")
        let bar = app.buttons["todayButton"]
        XCTAssertTrue(bar.exists)
        XCTAssertLessThanOrEqual(hour.frame.maxY, bar.frame.minY, "23:00 row hidden behind bottom bar")
    }

    func testPullToRefreshDoesNotCrash() throws {
        let list = app.collectionViews["agendaList"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        start.press(forDuration: 0.1, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)))
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        XCTAssertEqual(app.state, .runningForeground)
        selectTab("Day")
        let grid = app.scrollViews.firstMatch
        grid.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
            .press(forDuration: 0.1, thenDragTo: grid.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
        XCTAssertEqual(app.state, .runningForeground)
    }
}
