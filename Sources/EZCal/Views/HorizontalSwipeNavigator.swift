import SwiftUI
import AppKit

/// Two-finger trackpad swipe left/right = previous/next period, the way Calendar.app and Notion
/// Calendar behave. A plain `scrollWheel` override on a background NSView won't see these events:
/// SwiftUI's `ScrollView` is backed by a real `NSScrollView`, and AppKit hit-tests scroll events
/// straight to it (or a descendant), so an ancestor/sibling never gets first crack at them. Tapping
/// a local `NSEvent` monitor sidesteps hit-testing entirely — it sees every scroll event bound for
/// this window before normal dispatch, and we forward anything that isn't a clear horizontal swipe
/// unchanged, so the grid's own vertical scrolling is untouched.
struct HorizontalSwipeNavigator: NSViewRepresentable {
    /// -1 = previous period, +1 = next period.
    let onSwipe: (Int) -> Void

    final class Coordinator {
        var monitor: Any?
        weak var window: NSWindow?
        var accumulated: CGFloat = 0
        var triggered = false
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
            // qualifying tick is its own swipe, no accumulation needed.
            guard abs(dx) > 10 else { return false }
            onSwipe(dx < 0 ? 1 : -1)
            return true
        }

        if event.phase.contains(.began) { c.accumulated = 0; c.triggered = false }
        defer { if event.phase.contains(.ended) || event.phase.contains(.cancelled) { c.accumulated = 0; c.triggered = false } }
        guard !c.triggered else { return true }

        c.accumulated += dx
        let threshold: CGFloat = 70
        if c.accumulated < -threshold { c.triggered = true; onSwipe(1) }
        else if c.accumulated > threshold { c.triggered = true; onSwipe(-1) }
        return true
    }
}
