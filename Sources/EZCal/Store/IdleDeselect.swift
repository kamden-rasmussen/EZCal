import Foundation
#if os(macOS)
import AppKit
#endif

/// Auto-clears the focused/selected event after a couple of minutes of inactivity, so a stray
/// selection (from browsing around the grid) doesn't linger forever — see issue #30.
extension CalendarStore {
    static let idleDeselectTimeout: TimeInterval = 120

    /// Installs an app-wide activity monitor and starts the idle-check loop. Safe to call more than
    /// once — only the first call does anything.
    func startIdleDeselectWatcher() {
        guard activityMonitor == nil else { return }
        // A local monitor sees every matching event bound for this app before normal dispatch, so it
        // catches clicks/keys/scrolls anywhere (menus, sidebar, dialogs) without threading an
        // "activity" callback through every view. Always returns the event unchanged — this only
        // observes, never consumes.
        #if os(macOS)
        activityMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        ) { [weak self] event in
            self?.registerActivity()
            return event
        }
        #else
        // No global event monitor on iOS: the UI layer calls `registerActivity()` from touch handlers.
        activityMonitor = true
        #endif
        Task { [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
                guard let self else { return }
                self.deselectIfIdle()
            }
        }
    }

    func registerActivity() { lastInteractionAt = Date() }

    /// Clears the current selection once it's sat idle past the timeout, closing the docked detail
    /// panel too if it's showing that same event.
    func deselectIfIdle(now: Date = Date()) {
        guard focusedEventID != nil, Self.idleExceeded(lastInteraction: lastInteractionAt, now: now) else { return }
        if case .detail(let e) = sheet, e.id == focusedEventID { sheet = nil }
        focusedEventID = nil
    }

    static func idleExceeded(lastInteraction: Date, now: Date, timeout: TimeInterval = 120) -> Bool {
        now.timeIntervalSince(lastInteraction) >= timeout
    }
}
