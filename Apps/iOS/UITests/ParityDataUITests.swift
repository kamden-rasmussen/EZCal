import XCTest

/// Settings / calendar list / subscriptions / tasks parity tests (demo mode, in-memory only).
final class ParityDataUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["EZCAL_DEMO"] = "1"
        app.launch()
    }

    private func anyEl(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func openSettings() {
        app.buttons["menuButton"].tap()
        app.buttons["settingsButton"].tap()
    }
    /// Settings is a lazy Form in a medium sheet; swipe until the element is on screen.
    @discardableResult private func reveal(_ el: XCUIElement) -> XCUIElement {
        for _ in 0..<6 where !(el.exists && el.isHittable) { app.swipeUp() }
        XCTAssertTrue(el.exists, "\(el) not found")
        return el
    }
    private func openCalendars() {
        app.buttons["menuButton"].tap()
        app.buttons["calendarsButton"].tap()
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
}
