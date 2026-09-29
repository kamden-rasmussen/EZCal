import SwiftUI
#if os(macOS)
import AppKit
typealias PlatformColor = NSColor
#else
import UIKit
typealias PlatformColor = UIColor
#endif

extension PlatformColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        #if os(macOS)
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        #else
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        #endif
    }
}

/// Design tokens from the EZCal design canvas. Every color adapts to light/dark automatically.
enum Theme {
    /// A color that resolves differently in dark mode. The closure receives `isDark`.
    static func adaptive(_ resolve: @escaping (_ isDark: Bool) -> PlatformColor) -> Color {
        #if os(macOS)
        Color(nsColor: NSColor(name: nil) { a in resolve(a.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua) })
        #else
        Color(uiColor: UIColor { t in resolve(t.userInterfaceStyle == .dark) })
        #endif
    }

    static func dynamic(_ light: String, _ dark: String) -> Color {
        adaptive { $0 ? PlatformColor(hex: dark) : PlatformColor(hex: light) }
    }

    static let bg = dynamic("#FBFAF7", "#161615")
    static let side = dynamic("#F2F0EB", "#1C1C1A")
    static let surface = dynamic("#FFFFFF", "#1F1F1D")
    static let line = dynamic("#E5E2DA", "#33322E")
    static let line2 = dynamic("#EEEBE4", "#2A2926")
    static let text = dynamic("#1E1D1A", "#F2F0EA")
    static let text2 = dynamic("#5F5B52", "#A8A398")
    static let text3 = dynamic("#75716A", "#8A857B")
    static let accent = dynamic("#3B5BDB", "#8AA0FF")
    static let accentText = dynamic("#FFFFFF", "#12141F")
    static let hover = dynamic("#ECE9E2", "#2A2927")
    static let selection = dynamic("#E3E8FA", "#262C4A")
    static let todayBg = dynamic("#F6F5FF", "#1B1C22")
    static let now = Color(PlatformColor(hex: "#E5484D"))
    /// Soft white catch-light used under hairlines for an etched look.
    static let highlight = adaptive { $0 ? PlatformColor.white.withAlphaComponent(0.06) : PlatformColor.white.withAlphaComponent(0.85) }
    /// Subtle wash over non-working hours in the time grid.
    static let nonWorkingShade = adaptive { $0 ? PlatformColor.black.withAlphaComponent(0.16) : PlatformColor.black.withAlphaComponent(0.035) }

    /// Event title color: the calendar color pulled toward the text color so it stays readable on its own tint.
    static func eventText(_ c: Color) -> Color {
        adaptive { dark in
            let base = PlatformColor(c).srgbComponents ?? (0x3E / 255, 0x63 / 255, 0xDD / 255)
            let t = PlatformColor(hex: dark ? "#F2F0EA" : "#1E1D1A").srgbComponents ?? (0, 0, 0)
            let f: CGFloat = 0.28
            return PlatformColor(srgbRed: base.0 + (t.0 - base.0) * f, green: base.1 + (t.1 - base.1) * f,
                                 blue: base.2 + (t.2 - base.2) * f, alpha: 1)
        }
    }
}

extension PlatformColor {
    /// sRGB components, or nil if the color can't be converted.
    var srgbComponents: (CGFloat, CGFloat, CGFloat)? {
        #if os(macOS)
        guard let c = usingColorSpace(.sRGB) else { return nil }
        return (c.redComponent, c.greenComponent, c.blueComponent)
        #else
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        return getRed(&r, green: &g, blue: &b, alpha: &a) ? (r, g, b) : nil
        #endif
    }

    static func fromCG(_ cg: CGColor) -> PlatformColor? {
        #if os(macOS)
        NSColor(cgColor: cg)
        #else
        UIColor(cgColor: cg)
        #endif
    }

    #if !os(macOS)
    convenience init(srgbRed r: CGFloat, green g: CGFloat, blue b: CGFloat, alpha a: CGFloat) {
        self.init(red: r, green: g, blue: b, alpha: a)
    }
    #endif
}

/// Small rounded keycap used in hints and the cheat sheet.
struct KeyCap: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.text2)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(RoundedRectangle(cornerRadius: 5).fill(Theme.hover))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.line, lineWidth: 1))
    }
}

/// Diagonal stripes for "busy only" blocks.
struct Hatch: View {
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            var x: CGFloat = -size.height
            while x < size.width {
                var p = Path()
                p.move(to: CGPoint(x: x, y: size.height))
                p.addLine(to: CGPoint(x: x + size.height, y: 0))
                ctx.stroke(p, with: .color(color.opacity(0.35)), lineWidth: 3)
                x += 8
            }
        }
        .background(color.opacity(0.08))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.accentText)
            .padding(.horizontal, 12).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accent.opacity(configuration.isPressed ? 0.8 : 1)))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 12).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(configuration.isPressed ? Theme.hover : Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1))
    }
}

/// Same weight as PrimaryButtonStyle but red, for a destructive confirm (e.g. "Delete all events").
struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.now.opacity(configuration.isPressed ? 0.8 : 1)))
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.text2)
            .frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: 7).fill(configuration.isPressed ? Theme.hover : .clear))
            .contentShape(Rectangle())
    }
}
