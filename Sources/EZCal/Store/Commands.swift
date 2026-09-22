import Foundation
import SwiftUI
import AppKit

struct PaletteItem: Identifiable {
    let id: String
    var group: String
    var title: String
    var subtitle = ""
    var icon = "•"
    var key = ""
    var tint: Color?
    var run: @MainActor () -> Void
}

/// Keyboard navigation and the command palette.
extension CalendarStore {
    // MARK: - Event focus

    var focusedEvent: CalEvent? { focusedEventID.flatMap { id in displayEvents.first { $0.id == id } } }

    var navigableEvents: [CalEvent] {
        let days = visibleDays
        guard let first = days.first, let last = days.last else { return [] }
        let lo = cal.startOfDay(for: first), hi = cal.endOfDay(last)
        return displayEvents
            .filter { $0.start < hi && $0.end > lo }
            .sorted { $0.start != $1.start ? $0.start < $1.start : $0.title < $1.title }
    }

    /// Up/down: previous/next event in time order.
    func moveFocus(_ delta: Int) {
        let list = navigableEvents
        guard !list.isEmpty else { return }
        if let id = focusedEventID, let i = list.firstIndex(where: { $0.id == id }) {
            focusedEventID = list[min(max(i + delta, 0), list.count - 1)].id
        } else {
            let now = Date()
            focusedEventID = (delta > 0 ? (list.first { $0.end >= now } ?? list.first) : list.last)?.id
        }
    }

    /// Left/right: the event closest to the same time on the neighbouring day.
    func moveFocusDay(_ delta: Int) {
        guard let cur = focusedEvent else { moveFocus(delta); return }
        let c = cal
        let tod = cur.start.timeIntervalSince(c.startOfDay(for: cur.start))
        Task { @MainActor in
            var day = c.date(byAdding: .day, value: delta, to: cur.start)!
            for _ in 0..<7 {
                if !visibleDays.contains(where: { c.isDate($0, inSameDayAs: day) }) {
                    anchor = day
                    await reload()
                }
                let (allDay, timed) = events(on: day)
                let pool = timed + allDay
                if let best = pool.min(by: { abs($0.start.timeIntervalSince(c.startOfDay(for: day)) - tod) < abs($1.start.timeIntervalSince(c.startOfDay(for: day)) - tod) }) {
                    focusedEventID = best.id
                    return
                }
                if mode == .day || !visibleDays.contains(where: { c.isDate($0, inSameDayAs: c.date(byAdding: .day, value: delta, to: day)!) }) { break }
                day = c.date(byAdding: .day, value: delta, to: day)!
            }
        }
    }

    // MARK: - Actions

    /// Focused event's call, else the next upcoming one.
    func joinMeeting() {
        if let url = focusedEvent?.meetingURL ?? nextMeeting?.meetingURL {
            NSWorkspace.shared.open(url)
        } else {
            errorMessage = focusedEvent == nil ? "No upcoming meeting with a video link." : "That event has no video link."
        }
    }

    func openFocused() { if sheet == nil, let e = focusedEvent { sheet = .detail(e) } }
    func editFocused() { if sheet == nil, let e = focusedEvent, e.canEdit { requestEdit(e) } }
    func deleteFocused() { if sheet == nil, let e = focusedEvent, e.canEdit { requestDelete(e) } }

    func toggleSidebar() { columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly }

    func requestAddPerson() {
        guard !accounts.isEmpty else { errorMessage = "Connect Google to overlay coworkers."; return }
        columnVisibility = .all
        showAddPerson = true
    }

    func openPalette(_ query: String = "") { paletteQuery = query; sheet = .palette }
    func openShortcuts() { sheet = .shortcuts }
    func openFindTime() {
        guard !accounts.isEmpty else { errorMessage = "Connect Google to check attendees' availability."; return }
        sheet = .findTime
    }
    func openAddSubscription() { sheet = .addSubscription }

    func toggleWeekends() {
        UserDefaults.standard.set(!AppSettings.showWeekends, forKey: "showWeekends")
        scheduleReload()
    }

    func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    // MARK: - Palette

    func paletteItems(for raw: String) -> [PaletteItem] {
        let q = raw.trimmingCharacters(in: .whitespaces).lowercased()
        var items: [PaletteItem] = []

        func add(_ id: String, _ group: String, _ title: String, icon: String, key: String = "", sub: String = "",
                 tint: Color? = nil, run: @escaping @MainActor () -> Void) {
            items.append(PaletteItem(id: id, group: group, title: title, subtitle: sub, icon: icon, key: key, tint: tint, run: run))
        }

        add("new", "Actions", "New event", icon: "+", key: "N") { self.newDraft() }
        add("join", "Actions", "Join next meeting", icon: "▶", key: "J") { self.joinMeeting() }
        add("findtime", "Actions", "Find a time for coworkers", icon: "⏱", sub: "Best slot across everyone's calendar") { self.openFindTime() }
        add("today", "Go to", "Today", icon: "T", key: "T") { self.goToday() }
        add("next", "Go to", "Next \(mode.title.lowercased())", icon: "→", key: "]") { self.step(1) }
        add("prev", "Go to", "Previous \(mode.title.lowercased())", icon: "←", key: "[") { self.step(-1) }
        add("workweek", "Views", "Work week view (Mon–Fri)", icon: "5", key: "5") { self.setMode(.workWeek) }
        add("week", "Views", "Week view", icon: "W", key: "W") { self.setMode(.week) }
        add("day", "Views", "Day view", icon: "D", key: "D") { self.setMode(.day) }
        add("month", "Views", "Month view", icon: "M", key: "M") { self.setMode(.month) }
        add("weekends", "Views", AppSettings.showWeekends ? "Hide weekends" : "Show weekends", icon: "◫", key: "⌘⇧W") { self.toggleWeekends() }
        add("tz", "Views", secondaryZoneShown ? "Hide time zone" : "Show time zone", icon: "◔") { self.toggleSecondaryZone() }
        add("sidebar", "Views", "Toggle sidebar", icon: "▤", key: "⌘\\") { self.toggleSidebar() }
        add("refresh", "Actions", "Refresh calendars", icon: "↻", key: "⌘R") { Task { await self.refreshAll() } }
        add("addperson", "Coworkers", "Add coworker…", icon: "+", key: "P") { self.requestAddPerson() }
        add("addsubscription", "Calendars", "Add calendar by URL…", icon: "+") { self.openAddSubscription() }
        add("shortcuts", "Help", "Keyboard shortcuts", icon: "?", key: "?") { self.openShortcuts() }
        add("settings", "Help", "Settings", icon: "⚙", key: "⌘,") { self.openSettings() }

        for p in people {
            let on = isVisible(p)
            add("person-\(p.id)", "Coworkers", "\(on ? "Hide" : "Show") \(p.name)", icon: p.initials, tint: p.color) { self.toggle(p) }
        }
        for s in calendars {
            let on = isVisible(s)
            let sub = s.isEventKit ? s.groupTitle : (s.isICS ? "Subscribed" : s.accountId)
            add("cal-\(s.id)", "Calendars", "\(on ? "Hide" : "Show") \(s.name)", icon: "●", sub: sub, tint: s.color) { self.toggle(s) }
        }

        guard !q.isEmpty else {
            let order = ["Actions", "Go to", "Views", "Coworkers", "Calendars", "Help"]
            return items.filter { ["new", "join", "findtime", "today", "workweek", "week", "day", "month", "addperson", "addsubscription", "shortcuts", "tz"].contains($0.id) || $0.id.hasPrefix("person-") }
                .sorted { (order.firstIndex(of: $0.group) ?? 9) < (order.firstIndex(of: $1.group) ?? 9) }
        }

        let words = q.split(separator: " ").map(String.init)
        var out = items.filter { it in
            let hay = (it.title + " " + it.subtitle + " " + it.group).lowercased()
            return words.allSatisfy { hay.contains($0) }
        }

        // Natural-language date, e.g. "next friday", "sep 30", "go to tomorrow".
        let dateText = q.replacingOccurrences(of: "^(go to|goto|jump to)\\s+", with: "", options: .regularExpression)
        if dateText.count >= 3, let d = Self.parseDate(dateText) {
            out.insert(PaletteItem(id: "date", group: "Go to", title: "Go to \(d.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))",
                                   icon: "→", run: { self.goTo(d) }), at: 0)
        }

        // Add Zoom to the focused event.
        if "add zoom".hasPrefix(q) || q.contains("zoom") {
            if let e = focusedEvent, e.canEdit, e.meetingURL == nil, zoomConnected {
                out.append(PaletteItem(id: "zoom", group: "Actions", title: "Add Zoom to “\(e.title)”", icon: "Z",
                                       run: { Task { await self.attachZoom(to: e) } }))
            }
        }

        let hits = displayEvents.filter { !$0.isBusyOnly && $0.title.lowercased().contains(q) }
            .sorted { $0.start < $1.start }.prefix(6)
        for e in hits {
            out.append(PaletteItem(id: "event-\(e.id)", group: "Events", title: e.title,
                                   subtitle: e.start.formatted(.dateTime.weekday(.abbreviated).hour().minute()),
                                   icon: "●", tint: e.color, run: { self.focusedEventID = e.id; self.sheet = .detail(e) }))
        }
        return out
    }

    static func parseDate(_ s: String) -> Date? {
        guard let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        return det.firstMatch(in: s, range: NSRange(s.startIndex..., in: s))?.date
    }
}
