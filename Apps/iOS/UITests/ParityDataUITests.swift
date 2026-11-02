import XCTest

/// Settings / calendar list / subscriptions / tasks parity tests (demo mode, in-memory only).
final class ParityDataUITests: EZCalUITestCase {
    private func openSettings() {
        openMenuItem("settingsButton", expecting: "settingsDoneButton")
    }
    /// Settings is a lazy Form in a medium sheet; swipe until the element is on screen.
    @discardableResult private func reveal(_ el: XCUIElement) -> XCUIElement {
        for _ in 0..<6 where !(el.exists && el.isHittable) { app.swipeUp() }
        XCTAssertTrue(el.exists, "\(el) not found")
        return el
    }
    private func openCalendars() {
        openMenuItem("calendarsButton", expecting: "calendarsDoneButton")
    }

    func testSettingsHasParityControls() throws {
        openSettings()
        XCTAssertTrue(anyEl("showWeekendsToggle").waitForExistence(timeout: 5))
        reveal(anyEl("weekStartPicker"))
        reveal(anyEl("hourHeightSlider"))
        reveal(anyEl("appearancePicker"))
        reveal(anyEl("defaultVideoPicker"))
        // Flip weekends and appearance; the app must stay alive and settings still usable.
        for _ in 0..<6 where !app.switches["showWeekendsToggle"].isHittable { app.swipeDown() }
        let w = app.switches["showWeekendsToggle"]
        let before = w.value as? String
        w.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertNotEqual(w.value as? String, before)
        reveal(anyEl("appearancePicker")).tap()
        app.buttons["Dark"].tap()
        reveal(anyEl("appearancePicker")).tap()
        app.buttons["System"].tap()
        for _ in 0..<6 where !app.buttons["settingsDoneButton"].isHittable { app.swipeDown() }
        app.buttons["settingsDoneButton"].tap()
    }

    /// Working hours (#117): the days and start/end rows exist, and tapping a day chip toggles it.
    func testSettingsWorkingHoursDaysToggle() throws {
        openSettings()
        let sunday = reveal(app.buttons["workDay-1"])   // off by default (Mon-Fri)
        reveal(anyEl("workStartPicker"))
        reveal(anyEl("workEndPicker"))
        let before = sunday.isSelected
        sunday.tap()
        XCTAssertTrue(waitUntil(timeout: 5) { sunday.isSelected != before }, "tapping a day chip should toggle it")
    }

    // MARK: - Calendar list

    func testColorPickerShowsSwatchesAndReset() throws {
        openCalendars()
        let dot = anyEl("calendarColor-Home")
        XCTAssertTrue(dot.waitForExistence(timeout: 5))
        dot.tap()
        let sw = anyEl("swatch-#E5484D")
        XCTAssertTrue(sw.waitForExistence(timeout: 5))
        XCTAssertFalse(anyEl("resetColorButton").exists, "no override yet")
        sw.tap()
        XCTAssertTrue(anyEl("resetColorButton").waitForExistence(timeout: 5))
        anyEl("resetColorButton").tap()
        XCTAssertTrue(anyEl("resetColorButton").waitForNonExistence(timeout: 5))
        app.buttons["colorDoneButton"].tap()
        app.buttons["calendarsDoneButton"].tap()
    }

    func testShowAllHideAll() throws {
        openCalendars()
        let names = ["Me", "Team", "Home", "Family", "City League"]
        func states() -> [String?] { names.map { app.switches["calendarToggle-\($0)"].value as? String } }
        XCTAssertTrue(app.switches["calendarToggle-Me"].waitForExistence(timeout: 5))
        app.buttons["hideAllCalendars"].tap()
        XCTAssertEqual(states(), Array(repeating: "0", count: names.count))
        app.buttons["showAllCalendars"].tap()
        XCTAssertEqual(states(), Array(repeating: "1", count: names.count))
        app.buttons["calendarsDoneButton"].tap()
    }

    /// Drags `mover`'s reorder handle onto the top edge of `anchor`'s row and returns whether `mover` is now above it.
    /// Entering edit mode animates every row (the handles slide in) and the handle's frame is not final until that
    /// settles; resolving it early gives "Activation point invalid" (#152). So wait for the handle to be hittable
    /// and for its frame to stop changing, then drag using frames read once.
    private func dragRow(_ mover: String, above anchor: String) -> Bool {
        let moverRow = app.cells.containing(.staticText, identifier: mover).firstMatch
        let anchorRow = app.cells.containing(.staticText, identifier: anchor).firstMatch
        let h = moverRow.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Reorder'")).firstMatch
        XCTAssertTrue(h.waitForExistence(timeout: 10), "\(mover) row should show a reorder handle")
        XCTAssertTrue(anchorRow.waitForExistence(timeout: 10))
        var last = CGRect.null
        XCTAssertTrue(waitUntil(timeout: 10) {
            let f = h.frame, stable = h.isHittable && f == last && !f.isEmpty
            last = f
            return stable
        }, "reorder handle never settled")
        let handle = h.frame, target = anchorRow.frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let from = origin.withOffset(CGVector(dx: handle.midX, dy: handle.midY))
        let to = origin.withOffset(CGVector(dx: handle.midX, dy: target.minY + 4))
        from.press(forDuration: 0.8, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 1)
        let a = app.staticTexts[mover], b = app.staticTexts[anchor]
        return waitUntil(timeout: 5) { a.exists && b.exists && a.frame.minY < b.frame.minY }
    }

    func testReorderCalendarsInEditMode() throws {
        openCalendars()
        let me = app.switches["calendarToggle-Me"], team = app.switches["calendarToggle-Team"]
        XCTAssertTrue(team.waitForExistence(timeout: 5))
        // The calendar order is persisted (also in demo mode, in the simulator's defaults), so a previous run on
        // this simulator may have left Team above Me. Drag whichever is lower above the other.
        let (top, bottom) = me.frame.minY < team.frame.minY ? ("Me", "Team") : ("Team", "Me")
        app.buttons["reorderCalendarsButton"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Reorder'")).firstMatch
            .waitForExistence(timeout: 10), "edit mode should show reorder handles")
        XCTAssertTrue(dragRow(bottom, above: top), "\(bottom) should move above \(top)")
        // Put the order back so later tests on this simulator see the default.
        XCTAssertTrue(dragRow(top, above: bottom), "\(top) should move back above \(bottom)")
    }

    // MARK: - ICS subscriptions

    func testAddAndRemoveSubscription() throws {
        openCalendars()
        app.buttons["addSubscriptionButton"].tap()
        let url = app.textFields["subscriptionURLField"]
        XCTAssertTrue(url.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["subscriptionAdd"].isEnabled)
        url.tap(); url.typeText("not a url")
        app.textFields["subscriptionNameField"].tap()
        app.textFields["subscriptionNameField"].typeText("Test Feed")
        app.buttons["subscriptionAdd"].tap()
        XCTAssertTrue(anyEl("subscriptionError").waitForExistence(timeout: 5), "invalid URL should show an inline error")
        url.tap()
        url.press(forDuration: 1.0)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
        url.typeText("webcal://example.com/test.ics")
        app.buttons["subscriptionAdd"].tap()
        let toggle = app.switches["calendarToggle-Test Feed"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "new subscription should appear in the list")
        let cell = app.cells.containing(.switch, identifier: "calendarToggle-Test Feed").firstMatch
        cell.swipeLeft()
        app.buttons["removeSubscription-Test Feed"].tap()
        app.buttons.matching(identifier: "confirmRemoveSubscription").firstMatch.tap()
        XCTAssertTrue(toggle.waitForNonExistence(timeout: 5))
    }
}
