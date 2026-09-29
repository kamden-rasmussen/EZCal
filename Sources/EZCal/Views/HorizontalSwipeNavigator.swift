import SwiftUI
import AppKit

/// Two-finger trackpad swipe (or a horizontal scroll wheel) glides through the calendar a day at a
/// time — the further you pull, the more days it advances, rather than snapping a whole week or
/// month per gesture. A plain `scrollWheel` override on a background NSView won't see these events:
/// SwiftUI's `ScrollView` is backed by a real `NSScrollView`, and AppKit hit-tests scroll events
/// straight to it (or a descendant), so an ancestor/sibling never gets first crack at them. Tapping
/// a local `NSEvent` monitor sidesteps hit-testing entirely — it sees every scroll event bound for
/// this window before normal dispatch, and we forward anything that isn't a clear horizontal swipe
/// unchanged, so the grid's own vertical scrolling is untouched.
struct HorizontalSwipeNavigator: NSViewRepresentable {
    /// Called once per step: -1 = back, +1 = forward. What a step means (a day, a month) is up to
    /// the caller, which should read the current mode when invoked.
    let onStep: (Int) -> Void
    /// Pacing for the current view mode. Refreshed in `updateNSView`, so switching modes takes effect.
    let config: SwipeStepper

    final class Coordinator {
        var monitor: Any?
        weak var window: NSWindow?
        var parent: HorizontalSwipeNavigator?
        var stepper = SwipeStepper(pointsPerStep: 28)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.parent = self
        context.coordinator.stepper = config
        // The view has no window yet on this pass; grab it once AppKit finishes attaching us.
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            context.coordinator.window = window
            context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak coordinator = context.coordinator] event in
                guard let coordinator, coordinator.window === event.window else { return event }
                return coordinator.parent?.handle(event, coordinator) == true ? nil : event
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let c = context.coordinator
        c.parent = self
        // Only swap the stepper when pacing actually changed, so an in-flight gesture isn't reset.
        if c.stepper.pointsPerStep != config.pointsPerStep
            || c.stepper.maxStepsPerGesture != config.maxStepsPerGesture
            || c.stepper.minWheelInterval != config.minWheelInterval {
            c.stepper = config
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let m = coordinator.monitor { NSEvent.removeMonitor(m) }
    }

    /// Returns true if the event was a horizontal swipe we've consumed.
    /// Returns true if the event was a horizontal swipe we've consumed.
    fileprivate func handle(_ event: NSEvent, _ c: Coordinator) -> Bool {
        // Inertial scrolling after fingers lift: never treat as a fresh gesture, just let it fizzle.
        guard event.momentumPhase == [] else { return false }

        let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
        guard abs(dx) > abs(dy) else { return false }

        if event.phase == [] {
            // A plain scroll wheel with no gesture phases (rare on modern trackpads/mice): each
            // qualifying tick advances one step (throttled), no accumulation needed.
            guard abs(dx) > 4 else { return false }
            if let step = c.stepper.wheelTick(dx, at: event.timestamp) { onStep(step) }
            return true
        }

        if event.phase.contains(.began) { c.stepper.beginGesture() }
        defer { if event.phase.contains(.ended) || event.phase.contains(.cancelled) { c.stepper.endGesture() } }

        // Consume the delta in whole steps, carrying any remainder.
        for step in c.stepper.add(dx) { onStep(step) }
        return true
    }
}
