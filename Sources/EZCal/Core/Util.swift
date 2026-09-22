import Foundation
import SwiftUI
import Security

// MARK: - Color

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255,
                  opacity: 1)
    }
}

enum Palette {
    /// Colors handed out to coworkers as they're added.
    static let people = ["#E5484D", "#3E63DD", "#30A46C", "#F76B15", "#8E4EC6", "#12A594", "#D6409F", "#978365", "#0090FF", "#C2A000"]
}

// MARK: - Dates

enum RFC3339 {
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func parse(_ s: String) -> Date? { plain.date(from: s) ?? fractional.date(from: s) }
    /// UTC "Z" form; safe to put in a query string.
    static func string(_ d: Date) -> String { plain.string(from: d) }
    static func parseDay(_ s: String) -> Date? { dateOnly.date(from: s) }
    static func dayString(_ d: Date) -> String { dateOnly.string(from: d) }
}

extension Calendar {
    func endOfDay(_ d: Date) -> Date { date(byAdding: .day, value: 1, to: startOfDay(for: d))! }
}

// MARK: - HTML-ish text cleanup (Google descriptions can contain HTML)

extension String {
    var strippingHTML: String {
        var s = self
        s = s.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "</(p|div|li)>", with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (k, v) in ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&nbsp;": " "] {
            s = s.replacingOccurrences(of: k, with: v)
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Keychain

enum Keychain {
    private static let service = "com.ezcal.app"

    static func set(_ value: String, for key: String) {
        remove(key)
        guard !value.isEmpty else { return }
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8),
        ]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func remove(_ key: String) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(q as CFDictionary)
    }
}

// MARK: - Settings

/// Thin wrapper over UserDefaults/Keychain. Views bind to the same keys with @AppStorage.
enum AppSettings {
    static let defaults = UserDefaults.standard

    static var googleClientID: String { defaults.string(forKey: "googleClientID") ?? "" }
    static var googleClientSecret: String { Keychain.get("googleClientSecret") ?? "" }
    static var zoomClientID: String { defaults.string(forKey: "zoomClientID") ?? "" }
    static var zoomClientSecret: String { Keychain.get("zoomClientSecret") ?? "" }

    static var hasGoogleCredentials: Bool { !googleClientID.isEmpty }
    static var hasZoomCredentials: Bool { !zoomClientID.isEmpty && !zoomClientSecret.isEmpty }

    // Zoom meeting defaults (Settings → Zoom); see `ZoomMeetingOptions`.
    static var zoomWaitingRoom: Bool { defaults.object(forKey: "zoomWaitingRoom") as? Bool ?? true }
    static var zoomMuteOnEntry: Bool { defaults.object(forKey: "zoomMuteOnEntry") as? Bool ?? false }
    static var zoomJoinBeforeHost: Bool { defaults.object(forKey: "zoomJoinBeforeHost") as? Bool ?? false }
    static var zoomHostVideo: Bool { defaults.object(forKey: "zoomHostVideo") as? Bool ?? true }
    static var zoomParticipantVideo: Bool { defaults.object(forKey: "zoomParticipantVideo") as? Bool ?? false }
    static var zoomPasscodeEnabled: Bool { defaults.object(forKey: "zoomPasscodeEnabled") as? Bool ?? true }

    static var showWeekends: Bool { defaults.object(forKey: "showWeekends") as? Bool ?? true }
    /// 0 = follow system
    static var firstWeekday: Int { defaults.integer(forKey: "firstWeekday") }
    static var defaultDuration: Int { let d = defaults.integer(forKey: "defaultDuration"); return d > 0 ? d : 60 }
    static var defaultVideo: String { defaults.string(forKey: "defaultVideo") ?? "none" }
    static var hourHeight: Double { let h = defaults.double(forKey: "hourHeight"); return h > 0 ? h : 56 }

    /// Off by default: notifications are opt-in, requested only once the user turns this on (see
    /// NotificationService.ensureAuthorized), never at launch.
    static var notificationsEnabled: Bool { defaults.bool(forKey: "notificationsEnabled") }
    static var notificationLeadMinutes: Int {
        let v = defaults.integer(forKey: "notificationLeadMinutes")
        return [1, 5, 10, 15].contains(v) ? v : 5
    }
    static var notificationVideoOnly: Bool { defaults.bool(forKey: "notificationVideoOnly") }
}
