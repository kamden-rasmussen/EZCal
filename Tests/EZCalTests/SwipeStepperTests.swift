import XCTest
@testable import EZCal

final class SwipeStepperTests: XCTestCase {
    func testDayModeStepsEveryPointsPerStepAndCarriesRemainder() {
        var s = SwipeStepper(pointsPerStep: 28)
        s.beginGesture()
        XCTAssertEqual(s.add(-100), [1, 1, 1])   // 100 / 28 = 3 rem 16
        XCTAssertEqual(s.add(-12), [1])          // 16 + 12 = 28
        XCTAssertEqual(s.add(30), [-1])
    }

    func testMonthGestureIsCappedAtOneStep() {
        var s = SwipeStepper(pointsPerStep: 90, maxStepsPerGesture: 1)
        s.beginGesture()
        var total: [Int] = []
        for _ in 0..<200 { total += s.add(-20) }   // a long, fast swipe (4000pt)
        XCTAssertEqual(total, [1])
        s.endGesture()
        s.beginGesture()
        XCTAssertEqual(s.add(200), [-1])           // next gesture works again
    }

    func testSmallPullDoesNothing() {
        var s = SwipeStepper(pointsPerStep: 90, maxStepsPerGesture: 1)
        s.beginGesture()
        XCTAssertEqual(s.add(-50), [])
        XCTAssertEqual(s.add(-30), [])
    }

    func testWheelTicksAreThrottled() {
        var s = SwipeStepper(pointsPerStep: 90, maxStepsPerGesture: 1, minWheelInterval: 0.35)
        XCTAssertEqual(s.wheelTick(-10, at: 100.0), 1)
        XCTAssertNil(s.wheelTick(-10, at: 100.1))
        XCTAssertNil(s.wheelTick(10, at: 100.3))
        XCTAssertEqual(s.wheelTick(10, at: 100.5), -1)
    }

    func testUnthrottledWheel() {
        var s = SwipeStepper(pointsPerStep: 28)
        XCTAssertEqual(s.wheelTick(-10, at: 1), 1)
        XCTAssertEqual(s.wheelTick(-10, at: 1), 1)
    }
}
