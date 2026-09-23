// Generates Resources/AppIcon.icns. Run: swift scripts/make_icon.swift
import AppKit

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let inset = s * 0.06
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.22, yRadius: s * 0.22)
    NSGradient(colors: [NSColor(red: 0.16, green: 0.86, blue: 0.46, alpha: 1), NSColor(red: 0.02, green: 0.58, blue: 0.52, alpha: 1)])!
        .draw(in: path, angle: -60)

    // header strip
    NSColor.white.withAlphaComponent(0.18).setFill()
    NSBezierPath(rect: NSRect(x: rect.minX, y: rect.maxY - rect.height * 0.28, width: rect.width, height: rect.height * 0.28)).fill()

    // grid of days
    let cols = 4, rows = 3
    let gx = rect.width * 0.14, gy = rect.height * 0.12
    let cw = (rect.width - gx * 2) / CGFloat(cols), ch = (rect.height * 0.72 - gy * 2) / CGFloat(rows)
    for r in 0..<rows { for c in 0..<cols {
        let d = min(cw, ch) * 0.52
        let x = rect.minX + gx + CGFloat(c) * cw + (cw - d) / 2
        let y = rect.minY + gy + CGFloat(rows - 1 - r) * ch + (ch - d) / 2
        let hl = (r == 1 && c == 2)
        (hl ? NSColor.white : NSColor.white.withAlphaComponent(0.5)).setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: d, height: d), xRadius: d * 0.3, yRadius: d * 0.3).fill()
    } }
    img.unlockFocus()
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = "build/AppIcon.iconset"
try? fm.removeItem(atPath: iconset)
try fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: URL(fileURLWithPath: "\(iconset)/icon_\(base)x\(base).png"))
    try render(base * 2).write(to: URL(fileURLWithPath: "\(iconset)/icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset, "-o", "Resources/AppIcon.icns"]
try p.run(); p.waitUntilExit()
print("Wrote Resources/AppIcon.icns")
