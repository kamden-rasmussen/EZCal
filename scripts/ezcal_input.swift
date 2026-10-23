// Tiny helper for capture_site_media.sh: `ezcal_input scroll <lines> <x> <y>` / `ezcal_input mouse <x> <y>`.
import CoreGraphics
import Foundation

let a = CommandLine.arguments
func num(_ i: Int) -> Double { Double(a[i]) ?? 0 }
switch a.count > 1 ? a[1] : "" {
case "mouse":
    CGWarpMouseCursorPosition(CGPoint(x: num(2), y: num(3)))
case "scroll":
    CGWarpMouseCursorPosition(CGPoint(x: num(3), y: num(4)))
    usleep(150_000)
    for _ in 0..<Int(abs(num(2))) {
        CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: num(2) > 0 ? 3 : -3, wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap)
        usleep(20_000)
    }
default:
    FileHandle.standardError.write(Data("usage: scroll <lines> <x> <y> | mouse <x> <y>\n".utf8))
    exit(2)
}
