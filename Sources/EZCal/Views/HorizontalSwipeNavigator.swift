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
    /// Called once per day advanced: -1 = one day back, +1 = one day forward.
    let onStepDay: (Int) -> Void

    /// Points of accumulated horizontal delta per day advanced. Small on purpose — this should read
    /// as a smooth, continuous pull, not a springy threshold you have to shove past.
    private static let pointsPerDay: CGFloat = 28

    final class Coordinator {
        var monitor: Any?
        weak var window: NSWindow?
        var accumulated: CGFloat = 0
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // The view has no window yet on this pass; grab it once AppKit finishes attaching us.
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            context.coordinator.window = window
            context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak coordinator = context.coordinator] event in
                guard let coordinator, coordinator.window === event.window else { return event }
                return handle(event, coordinator) ? nil : event
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let m = coordinator.monitor { NSEvent.removeMonitor(m) }
    }

    /// Returns true if the event was a horizontal swipe we've consumed.
    private func handle(_ event: NSEvent, _ c: Coordinator) -> Bool {
        // Inertial scrolling after fingers lift: never treat as a fresh gesture, just let it fizzle.
        guard event.momentumPhase == [] else { return false }

        let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
        guard abs(dx) > abs(dy) else { return false }

        if event.phase == [] {
            // A plain scroll wheel with no gesture phases (rare on modern trackpads/mice): each
            // qualifying tick advances one day, no accumulation needed.
            guard abs(dx) > 4 else { return false }
            onStepDay(dx < 0 ? 1 : -1)
            return true
        }

        if event.phase.contains(.began) { c.accumulated = 0 }
        defer { if event.phase.contains(.ended) || event.phase.contains(.cancelled) { c.accumulated = 0 } }

        // Consume the delta in whole-day chunks, carrying any remainder — a long, fast swipe can
        // advance several days in one gesture, same as dragging further would in a paged scroller.
        c.accumulated += dx
        while abs(c.accumulated) >= Self.pointsPerDay {
            if c.accumulated < 0 { c.accumulated += Self.pointsPerDay; onStepDay(1) }
            else { c.accumulated -= Self.pointsPerDay; onStepDay(-1) }
        }
        return true
    }
}
