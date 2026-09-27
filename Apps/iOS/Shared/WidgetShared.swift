import Foundation
import SwiftUI

/// Compact, Codable event used by the widget and the shared app-group cache.
/// The app writes these after each refresh; the widget reads EventKit directly and falls back to this cache
/// (also the path Google Calendar events will use, since the widget cannot call the Google API).
struct WidgetEvent: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var location: String
    var colorHex: String
}

struct WidgetCache: Codable {
    var updated: Date
    var isDemo: Bool
    var events: [WidgetEvent]
}

enum WidgetShared {
    static let appGroup = "group.com.ezcal.app"
    static let scheme = "ezcal"
    static let cacheName = "widget-events.json"

    static var cacheURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(cacheName)
    }

    static func write(_ cache: WidgetCache) {
        guard let url = cacheURL, let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func read() -> WidgetCache? {
        guard let url = cacheURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetCache.self, from: data)
    }

    static func eventURL(_ e: WidgetEvent) -> URL {
        var c = URLComponents(); c.scheme = scheme; c.host = "event"
        c.path = "/" + e.id
        return c.url ?? URL(string: "\(scheme)://day/today")!
    }
    static let todayURL = URL(string: "\(scheme)://day/today")!

    static func demoEvents(now: Date = Date()) -> [WidgetEvent] {
        let cal = Calendar.current
        let base = cal.dateInterval(of: .hour, for: now)?.start ?? now
        func ev(_ id: String, _ t: String, _ off: Double, _ dur: Double, _ loc: String, _ hex: String) -> WidgetEvent {
            let s = base.addingTimeInterval(off * 3600)
            return WidgetEvent(id: id, title: t, start: s, end: s.addingTimeInterval(dur * 3600),
                               isAllDay: false, location: loc, colorHex: hex)
        }
        return [
            ev("d1", "Design review", 1, 1, "Room 4B", "#3E63DD"),
            ev("d2", "Lunch with Priya", 2.5, 1, "Cafe Roma", "#2F9E6E"),
            ev("d3", "Team standup", 4, 0.5, "Zoom", "#8E4EC6"),
            ev("d4", "Gym", 6, 1, "", "#E5722A"),
            ev("d5", "Planning", 26, 1, "Room 2A", "#3E63DD"),
        ]
    }
}

extension Color {
    init(widgetHex hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}
