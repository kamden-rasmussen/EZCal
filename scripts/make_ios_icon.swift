// Generates the iOS 1024 app icon (full-bleed, opaque; iOS applies the rounded mask).
// Run: swift scripts/make_ios_icon.swift
import AppKit

let s: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                           samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let rect = NSRect(x: 0, y: 0, width: s, height: s)
NSGradient(colors: [NSColor(red: 0.16, green: 0.86, blue: 0.46, alpha: 1), NSColor(red: 0.02, green: 0.58, blue: 0.52, alpha: 1)])!
    .draw(in: NSBezierPath(rect: rect), angle: -60)
NSColor.white.withAlphaComponent(0.18).setFill()
NSBezierPath(rect: NSRect(x: 0, y: s * 0.72, width: s, height: s * 0.28)).fill()
let cols = 4, rows = 3
let gx = s * 0.14, gy = s * 0.12
let cw = (s - gx * 2) / CGFloat(cols), ch = (s * 0.72 - gy * 2) / CGFloat(rows)
for r in 0..<rows { for c in 0..<cols {
    let d = min(cw, ch) * 0.52
    let x = gx + CGFloat(c) * cw + (cw - d) / 2
    let y = gy + CGFloat(rows - 1 - r) * ch + (ch - d) / 2
    ((r == 1 && c == 2) ? NSColor.white : NSColor.white.withAlphaComponent(0.5)).setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: d, height: d), xRadius: d * 0.3, yRadius: d * 0.3).fill()
} }
NSGraphicsContext.restoreGraphicsState()
let out = "Apps/iOS/Sources/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")
