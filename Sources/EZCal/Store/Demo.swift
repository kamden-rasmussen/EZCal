import Foundation
import SwiftUI
import AppKit

/// Fake data for screenshots and UI development: `EZCAL_DEMO=1 build/EZCal.app/Contents/MacOS/EZCal`.
extension CalendarStore {
    func loadDemo() {
        let me = Source(id: "cal|me@example.com|me", accountId: "me@example.com", calendarId: "me", name: "Me", colorHex: "#3E63DD", kind: .calendar, accessRole: "owner")
        let team = Source(id: "cal|me@example.com|team", accountId: "me@example.com", calendarId: "team", name: "Team", colorHex: "#8E4EC6", kind: .calendar, accessRole: "owner")
        let home = Source(id: "ek|demo-home", accountId: "ek:iCloud", calendarId: "home", name: "Home", colorHex: "#2F9E6E", kind: .calendar, accessRole: "owner")
        let fun = Source(id: "ek|demo-fun", accountId: "ek:iCloud", calendarId: "fun", name: "Family", colorHex: "#E5722A", kind: .calendar, accessRole: "owner")
        func person(_ n: String, _ c: String) -> Source {
            Source(id: "person|me@example.com|\(n)", accountId: "me@example.com", calendarId: "\(n)@example.com", name: n, colorHex: c, kind: .person)
        }
        let priya = person("Priya Shah", "#2F9E6E"), marcus = person("Marcus Lee", "#E5484D"), dana = person("Dana Cole", "#D6409F")
        accounts = [Account(email: "me@example.com", name: "Me")]
        calendars = [me, team, home, fun]
        people = [priya, marcus, dana]
        personAccess = [priya.id: .full, marcus.id: .full, dana.id: .busyOnly]

        let c = Calendar.current
        let monday = mondayStart(Date())
        var out: [String: [CalEvent]] = [:]

        func add(_ s: Source, week: Int, day: Int, _ start: Double, _ dur: Double, _ title: String,
                 video: Bool = false, busy: Bool = false, allDay: Bool = false, owner: String? = nil) {
            let d0 = c.date(byAdding: .day, value: week * 7 + day, to: monday)!
            let st = allDay ? d0 : c.date(byAdding: .minute, value: Int(start * 60), to: d0)!
            let en = allDay ? c.date(byAdding: .day, value: 1, to: d0)! : st.addingTimeInterval(dur * 3600)
            let id = "\(s.id)|\(title)|\(st.timeIntervalSince1970)"
            out[s.id, default: []].append(CalEvent(
                id: id, eventId: id, sourceId: s.id, calendarId: s.calendarId, accountId: s.accountId, uid: id,
                title: busy ? "Busy" : title, start: st, end: en, isAllDay: allDay, location: "", notes: "",
                attendees: [], htmlLink: nil,
                meetingURL: video ? URL(string: "https://acme.zoom.us/j/123456789") : nil,
                colorHex: s.colorHex, sourceName: s.name, ownerName: owner.map { $0.split(separator: " ").first.map(String.init) ?? $0 },
                isOverlay: s.kind == .person, canEdit: s.kind == .calendar, isBusyOnly: busy, isRecurring: false,
                zoomMeetingID: nil, isTentative: false, isDeclined: false))
        }

        for w in -1...1 {
            add(me, week: w, day: 0, 9.5, 0.5, "Standup", video: true)
            add(me, week: w, day: 0, 11, 1, "Design review", video: true)
            add(home, week: w, day: 0, 13, 1, "Lunch with Priya")
            add(marcus, week: w, day: 0, 9, 1.5, "Investor prep", owner: marcus.name)
            add(me, week: w, day: 1, 10, 1.5, "Roadmap planning", video: true)
            add(priya, week: w, day: 1, 10.5, 0.5, "1:1 with Dana", owner: priya.name)
            add(team, week: w, day: 1, 14, 2, "Focus time")
            add(fun, week: w, day: 1, 0, 0, "Product launch", allDay: true)
            add(me, week: w, day: 2, 9, 1, "Acme call", video: true)
            add(me, week: w, day: 2, 15, 1.5, "Sprint demo", video: true)
            add(priya, week: w, day: 2, 15, 1, "Demo prep", owner: priya.name)
            add(team, week: w, day: 3, 11, 0.75, "1:1 with Sam", video: true)
            add(dana, week: w, day: 3, 13, 2, "Busy", busy: true, owner: dana.name)
            add(dana, week: w, day: 3, 0, 0, "Out of office", allDay: true, owner: dana.name)
            add(me, week: w, day: 4, 10, 0.5, "Weekly sync", video: true)
            add(fun, week: w, day: 4, 16, 1.5, "Team social")
            add(home, week: w, day: 5, 10, 2, "Farmers market")
        }
        eventsBySource = out
        rebuildDisplay()
        upcoming = displayEvents.filter { !$0.isOverlay && !$0.isAllDay && $0.end > Date() }.sorted { $0.start < $1.start }
        updateMenuBarText()

        // Sample tasks (Reminders/EventKit), so ⌘K quick-add and the grid's task chips have something to show
        // without needing real Reminders access.
        tasks.enabled = true
        let personal = TaskList(id: "ektl|demo-personal", listId: "demo-personal", name: "Personal", colorHex: "#3E63DD")
        let work = TaskList(id: "ektl|demo-work", listId: "demo-work", name: "Work", colorHex: "#E5722A")
        tasks.lists = [personal, work]
        func task(_ list: TaskList, _ title: String, dayOffset: Int, hour: Double?, completed: Bool = false) -> EZTask {
            let day = c.date(byAdding: .day, value: dayOffset, to: c.startOfDay(for: monday))!
            let due = hour.map { c.date(byAdding: .minute, value: Int($0 * 60), to: day)! } ?? day
            let id = "\(list.id)|\(title)"
            return EZTask(id: id, taskId: id, listId: list.id, title: title, dueDate: due,
                          hasDueTime: hour != nil, isCompleted: completed, colorHex: list.colorHex)
        }
        tasks.byList = [
            personal.id: [
                task(personal, "Call dentist", dayOffset: 1, hour: 15),
                task(personal, "Pack for trip", dayOffset: 3, hour: nil),
            ],
            work.id: [
                task(work, "Send invoice", dayOffset: 0, hour: 11),
                task(work, "Review PR", dayOffset: 2, hour: nil, completed: true),
            ],
        ]
    }
}

/// `EZCAL_SNAPSHOT=/path/out.png` renders a screen to a PNG (no screen-recording permission needed) and quits.
/// `EZCAL_SNAPSHOT_VIEW` = window (default) | sidebar | editor | detail | palette | shortcuts | setup,  `EZCAL_APPEARANCE` = light | dark.
enum DebugSnapshot {
    @MainActor static func scheduleIfRequested(store: CalendarStore) {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["EZCAL_SNAPSHOT"] else { return }
        let delay = Double(env["EZCAL_SNAPSHOT_DELAY"] ?? "") ?? 3.0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if let a = env["EZCAL_APPEARANCE"] { NSApp.appearance = NSAppearance(named: a == "light" ? .aqua : .darkAqua) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let kind = env["EZCAL_SNAPSHOT_VIEW"] ?? "window"
            let target: NSView?
            if kind == "window" {
                let win = NSApp.windows.filter { $0.isVisible && $0.frame.width > 400 }.max { $0.frame.width < $1.frame.width }
                target = win?.contentView?.superview
            } else {
                store.loadDemo()
                let e = store.displayEvents.first { $0.title == "Design review" } ?? store.displayEvents[0]
                let root: AnyView
                switch kind {
                case "sidebar": root = AnyView(SidebarView().frame(width: 264, height: 820))
                case "editor":
                    var d = EventDraft(start: e.start, end: e.end, sourceId: store.calendars[0].id)
                    d.title = "Design review with Priya"; d.video = .zoom
                    d.attendees = [Attendee(email: "priya@example.com", name: "Priya Shah"), Attendee(email: "marcus@example.com", name: "Marcus Lee")]
                    root = AnyView(EventEditorView(draft: d))
                case "detail": root = AnyView(EventDetailView(event: e))
                case "palette": store.paletteQuery = "we"; root = AnyView(PaletteView())
                case "shortcuts": root = AnyView(ShortcutsView())
                default: root = AnyView(SetupView().frame(width: 960, height: 640))
                }
                let host = NSHostingView(rootView: root.environment(store).background(Theme.surface))
                let size = host.fittingSize
                host.frame = NSRect(origin: .zero, size: NSSize(width: max(size.width, 100), height: max(size.height, 100)))
                let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                win.contentView = host
                win.appearance = NSApp.appearance
                win.orderBack(nil)
                host.layoutSubtreeIfNeeded()
                target = host
            }
            guard let view = target else { print("snapshot: no view"); exit(2) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { print("snapshot: no bitmap"); exit(3) }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                print("snapshot: wrote \(path) \(Int(view.bounds.width))x\(Int(view.bounds.height))")
                exit(0)
            }
        }
    }
}
