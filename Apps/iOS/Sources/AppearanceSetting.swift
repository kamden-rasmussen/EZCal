import SwiftUI

/// User override for light/dark; `.system` follows the device.
enum AppearanceSetting: String, CaseIterable, Identifiable {
    case system, light, dark
    static let key = "appearance"
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
