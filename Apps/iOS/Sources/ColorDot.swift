import SwiftUI
import UIKit

/// A calendar's color dot as a pre-rendered image. Menu-style `Picker`s draw item icons as monochrome templates, so a
/// `foregroundStyle` on an SF Symbol there comes out gray (#208); an `.alwaysOriginal` bitmap keeps its color.
enum ColorDot {
    @MainActor private static var cache: [String: UIImage] = [:]

    @MainActor static func image(hex: String, diameter: CGFloat = 14) -> Image {
        let key = "\(hex)|\(diameter)"
        if let cached = cache[key] { return Image(uiImage: cached) }
        let size = CGSize(width: diameter, height: diameter)
        let dot = UIGraphicsImageRenderer(size: size).image { _ in
            PlatformColor(hex: hex).setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
        }.withRenderingMode(.alwaysOriginal)
        cache[key] = dot
        return Image(uiImage: dot)
    }
}
