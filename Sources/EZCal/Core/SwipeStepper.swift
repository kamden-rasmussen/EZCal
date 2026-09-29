import Foundation
import CoreGraphics

/// Turns a stream of horizontal scroll deltas into discrete navigation steps. Pure (no AppKit) so the
/// pacing rules can be unit tested.
///
/// Why this exists: Month view used to be driven by the same "one day per 28pt" swipe as the time
/// grids. A single trackpad swipe emits dozens of steps, and every step re-renders the 42-cell month
/// and kicked off a full network fetch, so the app stalled ("dies every time"). Month now gets a big
/// step size, a cap on steps per gesture, and a minimum interval between wheel ticks.
struct SwipeStepper {
    var pointsPerStep: CGFloat
    /// Max steps one gesture (began...ended) may emit. nil = unlimited.
    var maxStepsPerGesture: Int?
    /// Minimum seconds between phase-less (mouse wheel) steps.
    var minWheelInterval: TimeInterval

    private(set) var accumulated: CGFloat = 0
    private(set) var stepsThisGesture = 0
    private var lastWheelStep: TimeInterval = -.infinity

    init(pointsPerStep: CGFloat, maxStepsPerGesture: Int? = nil, minWheelInterval: TimeInterval = 0) {
        self.pointsPerStep = pointsPerStep
        self.maxStepsPerGesture = maxStepsPerGesture
        self.minWheelInterval = minWheelInterval
    }

    mutating func beginGesture() { accumulated = 0; stepsThisGesture = 0 }
    mutating func endGesture() { accumulated = 0; stepsThisGesture = 0 }

    /// Feeds a delta from a phased (trackpad) gesture; returns steps to take (+1 forward, -1 back).
    mutating func add(_ dx: CGFloat) -> [Int] {
        accumulated += dx
        var out: [Int] = []
        while abs(accumulated) >= pointsPerStep {
            let dir = accumulated < 0 ? 1 : -1
            accumulated += CGFloat(dir) * pointsPerStep
            if let cap = maxStepsPerGesture, stepsThisGesture >= cap {
                // Over the cap: swallow the excess so a long pull can't queue up more steps.
                accumulated = 0
                break
            }
            stepsThisGesture += 1
            out.append(dir)
        }
        return out
    }

    /// A phase-less wheel tick at `timestamp`; returns the step to take, or nil if throttled.
    mutating func wheelTick(_ dx: CGFloat, at timestamp: TimeInterval) -> Int? {
        guard timestamp - lastWheelStep >= minWheelInterval else { return nil }
        lastWheelStep = timestamp
        return dx < 0 ? 1 : -1
    }
}
