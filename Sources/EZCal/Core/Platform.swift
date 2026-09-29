import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Thin wrappers over the handful of AppKit/UIKit calls the shared layers need.
enum Platform {
    @MainActor static func open(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }

    @MainActor static func copyToClipboard(_ string: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #else
        UIPasteboard.general.string = string
        #endif
    }
}

extension Notification.Name {
    /// Posted where there's no system Settings window (iOS); the UI presents its own settings screen.
    static let ezcalOpenSettings = Notification.Name("ezcalOpenSettings")
}
