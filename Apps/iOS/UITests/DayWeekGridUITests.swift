import XCTest

final class DayWeekGridUITests: EZCalUITestCase {

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

    func testLongPressDragMovesEvent() throws {
        let ev = firstDayEvent()
        let before = ev.value as? String
        // Drag towards the middle of the screen so we never end up under the bars.
        let down = ev.frame.midY < app.frame.midY
        let from = ev.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let to = from.withOffset(CGVector(dx: 0, dy: down ? 84 : -84))   // 1.5 h at 56 pt/h
        from.press(forDuration: 0.8, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
        let moved = anyEl("dayEvent")
        XCTAssertTrue(finishEdit { moved.exists && moved.value as? String != before }, "event time should change after a move")
        XCTAssertFalse(app.staticTexts["detailTitle"].exists, "a drag must not open details")
    }

    func testResizeHandlesChangeEndAndStart() throws {
        let ev = firstDayEvent()
        let before = ev.value as? String ?? ""
        // Lift without moving: selects the block and shows the handles.
        ev.press(forDuration: 0.8)
        let bottom = anyEl("resizeBottom")
        XCTAssertTrue(bottom.waitForExistence(timeout: 5), "handles should show after lifting")
        bottom.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: bottom.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .withOffset(CGVector(dx: 0, dy: 56)))
        finishEdit { (self.anyEl("dayEvent").value as? String ?? "") != before }
        let afterBottom = anyEl("dayEvent").value as? String ?? ""
        XCTAssertNotEqual(afterBottom, before, "end time should change after resizing the bottom")
        let startBefore = before.components(separatedBy: " – ").first
        XCTAssertEqual(afterBottom.components(separatedBy: " – ").first, startBefore, "bottom resize keeps the start")

        let top = anyEl("resizeTop")
        XCTAssertTrue(top.waitForExistence(timeout: 5))
        top.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: top.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .withOffset(CGVector(dx: 0, dy: -28)))
        finishEdit { (self.anyEl("dayEvent").value as? String ?? "") != afterBottom }
        let afterTop = anyEl("dayEvent").value as? String ?? ""
        XCTAssertNotEqual(afterTop.components(separatedBy: " – ").first, startBefore, "top resize should change the start")
        XCTAssertEqual(afterTop.components(separatedBy: " – ").last, afterBottom.components(separatedBy: " – ").last)
    }

    func testTapStillOpensDetailsAfterDragSupport() throws {
        let ev = firstDayEvent()
        ev.tap()
        XCTAssertTrue(app.staticTexts["detailTitle"].waitForExistence(timeout: 5))
    }

    func testWeekLongPressDragMovesEventAcrossDays() throws {
        let found = visibleWeekEvent()
        let ev = try XCTUnwrap(found, "no week event on screen")
        let label = ev.label
        let before = ev.frame
        let left = before.midX > 250
        let from = ev.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        from.press(forDuration: 0.8, thenDragTo: from.withOffset(CGVector(dx: left ? -52 : 52, dy: 56)))
        let moved = app.descendants(matching: .any).matching(identifier: "weekDayEvent")
            .matching(NSPredicate(format: "label == %@", label)).firstMatch
        finishEdit { moved.exists && abs(moved.frame.midX - before.midX) > 25 }
        XCTAssertTrue(moved.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(abs(moved.frame.midX - before.midX), 25, "event should land in the neighbouring day column")
        XCTAssertGreaterThan(moved.frame.minY, before.minY + 20, "and an hour later")
        XCTAssertFalse(app.staticTexts["detailTitle"].exists)
    }

    func testWeekResizeBottomHandle() throws {
        let found = visibleWeekEvent()
        let ev = try XCTUnwrap(found, "no week event on screen")
        let label = ev.label
        let beforeH = ev.frame.height
        ev.press(forDuration: 0.8)
        let bottom = anyEl("resizeBottom")
        XCTAssertTrue(bottom.waitForExistence(timeout: 5))
        let c = bottom.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        c.press(forDuration: 0.1, thenDragTo: c.withOffset(CGVector(dx: 0, dy: 56)))
        let after = app.descendants(matching: .any).matching(identifier: "weekDayEvent")
            .matching(NSPredicate(format: "label == %@", label)).firstMatch
        finishEdit { after.exists && after.frame.height > beforeH + 20 }
        XCTAssertGreaterThan(after.frame.height, beforeH + 20)
    }

    func testWeekGridPullToRefreshAndAllDayOverflow() throws {
        selectTab("Day")
        pickGrid("Week")
        let grid = app.scrollViews.firstMatch
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        grid.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
            .press(forDuration: 0.1, thenDragTo: grid.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(anyEl("weekDayGridBackground").exists)
    }

    func testDayTabShowsDateOnlyOnce() throws {
        selectTab("Day")
        let title = anyEl("dayTitle")
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertFalse(title.label.isEmpty)
        XCTAssertEqual(app.navigationBars.firstMatch.staticTexts.count, 0,
                       "Day tab must not repeat the date as a nav-bar title")
    }

    // MARK: - 3-day view (#133)

    func testThreeDayViewShowsThreeColumnsAndPagesByThree() throws {
        selectTab("Day")
        pickGrid("3 Day")
        XCTAssertTrue(dayTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(anyEl("weekDayGridBackground").waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "weekDayGridBackground").count, 3)
        let before = dayTitle.label
        app.buttons["nextButton"].tap()
        XCTAssertNotEqual(dayTitle.label, before)
        app.buttons["prevButton"].tap()
        XCTAssertEqual(dayTitle.label, before)
        app.scrollViews.firstMatch.swipeLeft()
        XCTAssertNotEqual(dayTitle.label, before)
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
}
