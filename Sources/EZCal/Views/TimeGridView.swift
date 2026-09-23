import SwiftUI
import AppKit

// MARK: - Overlap layout

/// One cell in the grid: either an ordinary event, or a handful of them folded into one block because
/// `EventGrouping` decided they're the same meeting seen on different calendars.
enum TimeGridItem: Identifiable {
    case single(CalEvent)
    case stack([CalEvent])   // 2+ events: same title, same slot (within `EventGrouping.slack`), different calendars

    var id: String {
        switch self {
        case .single(let e): return e.id
        case .stack(let es): return es.map(\.id).sorted().joined(separator: "+")
        }
    }
    var start: Date { switch self { case .single(let e): return e.start; case .stack(let es): return es.map(\.start).min()! } }
    var end: Date { switch self { case .single(let e): return e.end; case .stack(let es): return es.map(\.end).max()! } }
}

/// Folds the same meeting seen on several calendars into one `TimeGridItem.stack`, so the grid can draw it as one
/// readable block instead of N near-identical slivers (feature request: stack same-slot duplicates).
enum EventGrouping {
    /// How far a duplicate's start/end may drift and still count as "the same slot" — absorbs calendars that
    /// round differently, or a copy that was entered a minute or two off.
    static let slack: TimeInterval = 5 * 60

    static func group(_ events: [CalEvent]) -> [TimeGridItem] {
        var remaining = events
        var items: [TimeGridItem] = []
        while let anchor = remaining.first {
            remaining.removeFirst()
            let key = normalizedTitle(anchor.title)
            // Coworker overlays and free/busy blocks stay their own thing — never folded into a stack.
            guard !key.isEmpty, !anchor.isOverlay, !anchor.isBusyOnly else { items.append(.single(anchor)); continue }
            var matched = [anchor]
            remaining.removeAll { candidate in
                guard !candidate.isOverlay, !candidate.isBusyOnly,
                      candidate.sourceId != anchor.sourceId,   // only different calendars count as a duplicate
                      normalizedTitle(candidate.title) == key,
                      abs(candidate.start.timeIntervalSince(anchor.start)) <= slack,
                      abs(candidate.end.timeIntervalSince(anchor.end)) <= slack
                else { return false }
                matched.append(candidate)
                return true
            }
            items.append(matched.count > 1 ? .stack(matched) : .single(anchor))
        }
        return items
    }

    private static func normalizedTitle(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct PlacedEvent: Identifiable {
    let item: TimeGridItem
    let start: Date
    let end: Date
    var column: Int
    var columns: Int
    var id: String { item.id }
}

enum EventLayout {
    /// Packs overlapping events side by side (Google-Calendar style clusters), after first folding same-slot
    /// duplicates across calendars into single stacked items (`EventGrouping`).
    static func place(_ events: [CalEvent], day: Date, cal: Calendar) -> [PlacedEvent] {
        let dayStart = cal.startOfDay(for: day)
        let dayEnd = cal.endOfDay(day)
        var items = EventGrouping.group(events).map { item in
            (item: item, s: max(item.start, dayStart), en: min(max(item.end, item.start.addingTimeInterval(20 * 60)), dayEnd))
        }
        items.sort { $0.s != $1.s ? $0.s < $1.s : $0.en > $1.en }

        var result: [PlacedEvent] = []
        var cluster: [PlacedEvent] = []
        var colEnds: [Date] = []
        var clusterEnd = Date.distantPast

        func flush() {
            let n = max(colEnds.count, 1)
            result += cluster.map { var p = $0; p.columns = n; return p }
            cluster = []; colEnds = []; clusterEnd = .distantPast
        }

        for it in items {
            if it.s >= clusterEnd { flush() }
            let col: Int
            if let free = colEnds.firstIndex(where: { $0 <= it.s }) { col = free; colEnds[free] = it.en }
            else { colEnds.append(it.en); col = colEnds.count - 1 }
            cluster.append(PlacedEvent(item: it.item, start: it.s, end: it.en, column: col, columns: 1))
            clusterEnd = max(clusterEnd, it.en)
        }
        flush()
        return result
    }
}

// MARK: - Time grid (day + week)

struct TimeGridView: View {
    @Environment(CalendarStore.self) private var store
    @AppStorage("hourHeight") private var hourHeight = 56.0
    @AppStorage("showSecondaryZone") private var showSecondaryZone = true
    @AppStorage("secondaryZoneID") private var secondaryZoneID = ""
    let days: [Date]

    /// Hour height captured when a pinch gesture begins, so `MagnificationGesture`'s cumulative scale
    /// factor is applied against a fixed base rather than compounding every frame.
    @State private var hourHeightAtPinchStart: Double?

    private let gutter: CGFloat = 56
    private var secondaryZone: TimeZone? { AppSettings.effectiveZone(id: secondaryZoneID, show: showSecondaryZone) }
    private var secondaryWidth: CGFloat { secondaryZone == nil ? 0 : 44 }

    var body: some View {
        VStack(spacing: 0) {
            header
            allDayRow
            Divider().overlay(Theme.line)
            ScrollViewReader { proxy in
                ScrollView {
                    HStack(alignment: .top, spacing: 0) {
                        hourGutter
                        if let zone = secondaryZone { secondaryGutter(zone) }
                        ForEach(days, id: \.self) { day in
                            DayColumn(day: day, hourHeight: hourHeight)
                        }
                        Color.clear.frame(width: 8, height: 1)
                    }
                    .background(alignment: .topLeading) { hourLines }
                }
                .scrollIndicators(.hidden)
                // Pinch-to-zoom (trackpad) on the time grid: spreading expands the vertical space between
                // hour marks (more detail), pinching in collapses it (more hours visible at once).
                // `hourHeight` is @AppStorage-backed, so the zoom level is sticky across view opens and
                // app restarts for free, and the Settings slider stays in sync with pinch adjustments.
                .gesture(pinchToZoomGesture)
                .task {
                    try? await Task.sleep(nanoseconds: 60_000_000)   // let the grid lay out first
                    let start = AppSettings.workingHours.startHour        // grid opens at the beginning of the working day
                    let now = Calendar.current.component(.hour, from: Date())
                    proxy.scrollTo("hour-\(min(max(now - 4, start), start + 2))", anchor: .top)
                }
                .onChange(of: store.focusedEventID) { _, _ in
                    guard let e = store.focusedEvent, !e.isAllDay else { return }
                    proxy.scrollTo("hour-\(Calendar.current.component(.hour, from: e.start))", anchor: .center)
                }
            }
        }
        .background(Theme.bg)
    }

    private var header: some View {
        // .everyMinute (not just whatever else happens to re-render this view) is what keeps the
        // "today" circle correct across a midnight rollover on a long-running window.
        TimelineView(.everyMinute) { _ in
            HStack(spacing: 0) {
                Color.clear.frame(width: gutter, height: 1)
                if let zone = secondaryZone {
                    Text(ZoneMath.shortName(zone))
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.text3)
                        .frame(width: secondaryWidth, height: 1, alignment: .center)
                        .help("Secondary time zone: \(zone.identifier)")
                }
                ForEach(days, id: \.self) { day in
                    let isToday = Calendar.current.isDateInToday(day)
                    HStack(spacing: 8) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                            .font(.system(size: 12, weight: .medium)).tracking(0.5)
                            .foregroundStyle(isToday ? Theme.accent : Theme.text2)
                        Text(day.formatted(.dateTime.day()))
                            .font(.system(size: 16, weight: .semibold).monospacedDigit())
                            .foregroundStyle(isToday ? Theme.accentText : Theme.text)
                            .frame(minWidth: 28, minHeight: 28)
                            .background(Circle().fill(isToday ? Theme.accent : .clear))
                    }
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { store.anchor = day; store.setMode(.day) }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                }
                Color.clear.frame(width: 8, height: 1)
            }
        }
    }

    private var allDayRow: some View {
        let perDay = days.map { store.events(on: $0).allDay }
        // Tasks due that day with no specific time ride along in the all-day row too.
        let perDayTasks = days.map { store.tasks.tasks(on: $0, cal: store.cal).allDay }
        let rows = zip(perDay, perDayTasks).map { $0.count + $1.count }.max() ?? 0
        return Group {
            if rows > 0 {
                HStack(alignment: .top, spacing: 0) {
                    Text("all-day").font(.system(size: 11)).foregroundStyle(Theme.text3)
                        .frame(width: gutter - 8, alignment: .trailing).padding(.trailing, 8).padding(.top, 6)
                    Color.clear.frame(width: secondaryWidth, height: 1)
                    ForEach(Array(days.enumerated()), id: \.offset) { i, _ in
                        VStack(spacing: 2) {
                            ForEach(perDay[i]) { e in AllDayChip(event: e) }
                            ForEach(perDayTasks[i]) { t in TaskChip(task: t) }
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                        .padding(.horizontal, 3).padding(.vertical, 4)
                    }
                    Color.clear.frame(width: 8, height: 1)
                }
                .padding(.bottom, 2)
                Divider().overlay(Theme.line)
            }
        }
    }

    private var hourGutter: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { h in
                // Cell top is 8pt above the hour line, so scrolling to a cell keeps its label fully visible.
                Text(h == 0 ? "" : hourLabel(h))
                    .font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.text3)
                    .padding(.top, 1)
                    .frame(width: gutter - 8, height: hourHeight, alignment: .topTrailing)
                    .id("hour-\(h)")
                    .accessibilityHidden(true)
            }
        }
        .padding(.top, -8)
        .frame(width: gutter, alignment: .leading)
    }

    /// Second hour column showing the same instants converted into `zone`'s wall clock (e.g. "9 AM" → "6 PM CET").
    private func secondaryGutter(_ zone: TimeZone) -> some View {
        let refDay = days.first ?? Date()
        let dayStart = Calendar.current.startOfDay(for: refDay)
        return VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { h in
                let instant = Calendar.current.date(byAdding: .hour, value: h, to: dayStart) ?? refDay
                Text(h == 0 ? "" : ZoneMath.hourLabel(instant, in: zone))
                    .font(.system(size: 10).monospacedDigit()).foregroundStyle(Theme.text3.opacity(0.85))
                    .padding(.top, 1)
                    .frame(width: secondaryWidth, height: hourHeight, alignment: .top)
                    .accessibilityHidden(true)
            }
        }
        .padding(.top, -8)
        .frame(width: secondaryWidth, alignment: .leading)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.line2).frame(width: 1) }
    }

    private var hourLines: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { _ in
                Rectangle().fill(Theme.line2).frame(height: 1).frame(height: hourHeight, alignment: .top)
            }
        }
        .padding(.leading, gutter + secondaryWidth)
        .padding(.trailing, 8)
        .allowsHitTesting(false)
    }

    private func hourLabel(_ h: Int) -> String {
        let d = Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date())!
        return d.formatted(.dateTime.hour())
    }

    private var pinchToZoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                let base = hourHeightAtPinchStart ?? hourHeight
                if hourHeightAtPinchStart == nil { hourHeightAtPinchStart = base }
                let range = AppSettings.hourHeightRange
                hourHeight = min(max(base * scale, range.lowerBound), range.upperBound)
            }
            .onEnded { _ in hourHeightAtPinchStart = nil }
    }
}

// MARK: - One day column

struct DayColumn: View {
    @Environment(CalendarStore.self) private var store
    let day: Date
    let hourHeight: Double

    @State private var dragRange: (Double, Double)?

    var body: some View {
        let placed = EventLayout.place(store.events(on: day).timed, day: day, cal: store.cal)
        let dayStart = store.cal.startOfDay(for: day)
        let isToday = Calendar.current.isDateInToday(day)
        let dueTasks = store.tasks.tasks(on: day, cal: store.cal).timed

        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                (isToday ? Theme.todayBg : Color.clear)
                    .contentShape(Rectangle())
                    .gesture(createGesture)
                    .accessibilityHidden(true)

                // Subtle wash over hours outside the working day (Settings → General → Working hours).
                ForEach(Array(AppSettings.workingHours.nonWorkingRanges(on: day, cal: store.cal).enumerated()), id: \.offset) { _, r in
                    Theme.nonWorkingShade
                        .frame(height: CGFloat(r.upperBound - r.lowerBound) / 60 * hourHeight)
                        .offset(y: CGFloat(r.lowerBound) / 60 * hourHeight)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                ForEach(placed) { p in
                    let top = p.start.timeIntervalSince(dayStart) / 3600 * hourHeight + 1
                    let h = max(p.end.timeIntervalSince(p.start) / 3600 * hourHeight - 2, 18)
                    let colW = geo.size.width / CGFloat(p.columns)
                    Group {
                        switch p.item {
                        case .single(let event):
                            EventBlock(event: event, height: h, narrow: p.columns > 1,
                                       hourHeight: hourHeight, dayWidth: geo.size.width)
                        case .stack(let events):
                            StackedEventBlock(events: events, height: h)
                        }
                    }
                    .frame(width: max(colW - 4, 4), height: h)
                    .offset(x: colW * CGFloat(p.column) + 2, y: top)
                }

                ForEach(dueTasks) { t in
                    let top = (t.dueDate ?? dayStart).timeIntervalSince(dayStart) / 3600 * hourHeight
                    TimedTaskMarker(task: t).offset(x: 2, y: top)
                }

                if let (a, b) = dragRange {
                    let top = min(a, b), h = max(abs(b - a), hourHeight / 4)
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Theme.accent.opacity(0.16))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.accent, lineWidth: 1.5))
                        .overlay(alignment: .topLeading) {
                            Text(timeLabel(top, h)).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent).padding(5)
                        }
                        .frame(width: geo.size.width - 4, height: h)
                        .offset(x: 2, y: top)
                        .allowsHitTesting(false)
                }

                // Ghost preview while an event is being dragged (moved or resized) into this day.
                if let dp = store.dragPreview, store.cal.isDate(dp.day, inSameDayAs: day) {
                    let top = dp.start.timeIntervalSince(dayStart) / 3600 * hourHeight + 1
                    let h = max(dp.end.timeIntervalSince(dp.start) / 3600 * hourHeight - 2, 18)
                    DragGhost(event: dp.event, start: dp.start, end: dp.end)
                        .frame(width: geo.size.width - 4, height: h)
                        .offset(x: 2, y: top)
                        .allowsHitTesting(false)
                }

                if isToday {
                    TimelineView(.everyMinute) { ctx in
                        let y = ctx.date.timeIntervalSince(dayStart) / 3600 * hourHeight
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Theme.now).frame(height: 2)
                            Circle().fill(Theme.now).frame(width: 10, height: 10).offset(x: -5)
                        }
                        .offset(y: y - 1)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
        }
        .frame(height: hourHeight * 24)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.line2).frame(width: 1) }
    }

    private func snap(_ y: CGFloat) -> Double {
        let minutes = Double(y) / hourHeight * 60
        let snapped = (minutes / 15).rounded() * 15
        return min(max(snapped, 0), 24 * 60) / 60 * hourHeight
    }

    private func date(atY y: Double) -> Date {
        let minutes = Int((y / hourHeight * 60).rounded())
        return store.cal.date(byAdding: .minute, value: minutes, to: store.cal.startOfDay(for: day))!
    }

    private func timeLabel(_ top: Double, _ h: Double) -> String {
        let s = date(atY: top), e = date(atY: top + h)
        return "\(s.formatted(date: .omitted, time: .shortened)) – \(e.formatted(date: .omitted, time: .shortened))"
    }

    private var createGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if abs(v.translation.height) > 4 { dragRange = (snap(v.startLocation.y), snap(v.location.y)) }
            }
            .onEnded { v in
                defer { dragRange = nil }
                if abs(v.translation.height) > 4 {
                    var a = snap(v.startLocation.y), b = snap(v.location.y)
                    if a > b { swap(&a, &b) }
                    if b - a < hourHeight / 4 { b = a + hourHeight / 4 }
                    store.newDraft(start: date(atY: a), end: date(atY: b))
                } else {
                    // Plain click: floor to the half hour under the cursor.
                    let mins = Double(v.startLocation.y) / hourHeight * 60
                    let y = (mins / 30).rounded(.down) * 30 / 60 * hourHeight
                    store.newDraft(start: date(atY: y))
                }
            }
    }
}

// MARK: - Event visuals

struct EventBlock: View {
    @Environment(CalendarStore.self) private var store
    let event: CalEvent
    let height: Double
    var narrow = false
    /// Needed to convert drag translation into minutes/days; 0 when a caller (e.g. previews) doesn't drag.
    var hourHeight: Double = 56
    var dayWidth: CGFloat = 0
    @State private var hovering = false
    /// The event's own time when the current drag gesture began, captured on the first `onChanged`.
    @State private var dragOrigin: (start: Date, end: Date)?

    /// Read-only events, coworker overlays and busy blocks can't be dragged (issue #1 scope).
    private var canDrag: Bool { event.canEdit && !event.isOverlay && !event.isBusyOnly && !event.isAllDay }
    private var isBeingDragged: Bool { store.dragPreview?.event.id == event.id }

    var body: some View {
        let c = event.color
        let shape = RoundedRectangle(cornerRadius: 7)
        let focused = store.focusedEventID == event.id

        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .top, spacing: 4) {
                if let o = event.ownerName, !narrow {
                    Text(String(o.prefix(1)).uppercased())
                        .font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 14, height: 14).background(Circle().fill(c))
                        .padding(.top, 0.5)
                }
                if event.isRecurring {
                    Image(systemName: "repeat").font(.system(size: 9)).opacity(0.75).padding(.top, 1)
                        .accessibilityHidden(true)
                }
                Text(titleText)
                    .font(.system(size: narrow ? 11 : 12, weight: .semibold))
                    .strikethrough(event.isDeclined)
                    .lineLimit(height > 40 ? 2 : 1)
                    .minimumScaleFactor(narrow ? 0.85 : 1)
                Spacer(minLength: 0)
                if let url = event.meetingURL, height >= 28, !narrow {
                    Button { NSWorkspace.shared.open(url) } label: {
                        Image(systemName: "video.fill").font(.system(size: 10)).padding(.top, 2)
                    }
                    .buttonStyle(.plain)
                    .help("Join \(event.meetingProvider?.name ?? "meeting") (J)")
                    .accessibilityLabel("Join \(event.meetingProvider?.name ?? "meeting")")
                }
            }
            if height >= 40 && !event.isOverlay {
                Text(event.start.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 11).monospacedDigit()).opacity(0.75).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(event.isOverlay ? Theme.text2 : Theme.eventText(c))
        .padding(.horizontal, narrow ? 5 : 7).padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            if event.isBusyOnly { Hatch(color: c).clipShape(shape) }
            else if event.isOverlay { shape.fill(hovering ? c.opacity(0.08) : Color.clear) }
            else { ZStack { shape.fill(Theme.surface); shape.fill(c.opacity(hovering ? 0.26 : 0.17)) } }
        }
        .overlay {
            if event.isOverlay { shape.strokeBorder(c.opacity(0.6), lineWidth: event.isBusyOnly ? 1 : 1.5) }
        }
        .overlay { if focused { shape.inset(by: -1.5).strokeBorder(Theme.accent, lineWidth: 2) } }
        .overlay(alignment: .bottom) { if canDrag { resizeHandle } }
        .opacity(event.isDeclined ? 0.5 : (isBeingDragged ? 0.35 : 1))
        .contentShape(shape)
        .onHover { hovering = $0 }
        .help(helpText)
        .gesture(moveGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    /// A thin strip along the bottom edge that resizes the event instead of moving it; layered on top so it
    /// wins hit-testing over `moveGesture` in that sliver.
    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 7)
            .contentShape(Rectangle())
            .gesture(resizeGesture)
            .onHover { hovering in
                if hovering { NSCursor.resizeUpDown.set() } else { NSCursor.arrow.set() }
            }
            .accessibilityHidden(true)
    }

    /// Drag the block to move it (snap to 15 minutes, including across day columns); a plain click (no
    /// meaningful movement) opens the event instead, matching the previous `onTapGesture` behavior.
    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                guard canDrag, abs(v.translation.height) > 3 || abs(v.translation.width) > 3 else { return }
                if dragOrigin == nil { dragOrigin = (event.start, event.end); store.dragCancelled = false }
                guard !store.dragCancelled, let origin = dragOrigin else { return }
                let minutesDelta = EventDragMath.snap(minutes: Double(v.translation.height) / hourHeight * 60)
                let dayDelta = dayWidth > 1 ? Int((Double(v.translation.width) / Double(dayWidth)).rounded()) : 0
                let (s, e) = EventDragMath.moved(start: origin.start, end: origin.end,
                                                 minutesDelta: minutesDelta, dayDelta: dayDelta, cal: store.cal)
                store.dragPreview = EventDragPreview(kind: .move, event: event, day: store.cal.startOfDay(for: s), start: s, end: e)
            }
            .onEnded { v in
                defer { dragOrigin = nil }
                if canDrag, let preview = store.dragPreview, preview.event.id == event.id, preview.kind == .move {
                    store.dragPreview = nil
                    Task { await store.applyTimeChange(to: event, start: preview.start, end: preview.end) }
                    return
                }
                store.dragPreview = nil
                if abs(v.translation.width) < 3, abs(v.translation.height) < 3 {
                    store.focusedEventID = event.id; store.sheet = .detail(event)
                }
            }
    }

    /// Drag the bottom edge to resize (snap to 15 minutes, 15-minute minimum). Esc (handled in
    /// `ContentView`) clears `dragPreview` and sets `dragCancelled`, which this checks before every update.
    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { v in
                guard canDrag else { return }
                if dragOrigin == nil { dragOrigin = (event.start, event.end); store.dragCancelled = false }
                guard !store.dragCancelled, let origin = dragOrigin else { return }
                let minutesDelta = EventDragMath.snap(minutes: Double(v.translation.height) / hourHeight * 60)
                let (s, e) = EventDragMath.resized(start: origin.start, end: origin.end, minutesDelta: minutesDelta, cal: store.cal)
                store.dragPreview = EventDragPreview(kind: .resize, event: event, day: store.cal.startOfDay(for: s), start: s, end: e)
            }
            .onEnded { _ in
                defer { dragOrigin = nil }
                guard canDrag, let preview = store.dragPreview, preview.event.id == event.id, preview.kind == .resize else {
                    store.dragPreview = nil
                    return
                }
                store.dragPreview = nil
                Task { await store.applyTimeChange(to: event, start: preview.start, end: preview.end) }
            }
    }

    private var titleText: String {
        if event.ownerName != nil, event.isBusyOnly { return "Busy" }
        return event.title
    }

    /// Base hover tooltip, plus the event's time in the secondary time zone (if one is configured) so you don't
    /// have to do the math when scheduling across zones.
    private var helpText: String {
        let base = event.ownerName.map { "\($0) · \(titleText)" } ?? titleText
        guard !event.isAllDay, let zone = AppSettings.secondaryTimeZone else { return base }
        return "\(base) · \(ZoneMath.rangeLabel(start: event.start, end: event.end, in: zone))"
    }

    private var accessibilityText: String {
        let who = event.ownerName.map { "\($0): " } ?? ""
        let time = event.start.formatted(date: .omitted, time: .shortened)
        return "\(who)\(event.isBusyOnly ? "Busy" : event.title), \(time)" + (event.meetingURL != nil ? ", has video call" : "") + (event.isRecurring ? ", repeats" : "")
    }
}

/// The same meeting seen on several calendars at once (`EventGrouping`), drawn as one card with faint peeking
/// edges behind it — a stack of copies, not N unreadable slivers. Tapping it lists which calendars it's on;
/// picking one opens that calendar's own event in the usual docked detail panel.
struct StackedEventBlock: View {
    @Environment(CalendarStore.self) private var store
    let events: [CalEvent]   // 2+, same title/slot, different sourceIds
    let height: Double
    @State private var hovering = false
    @State private var showList = false

    private var front: CalEvent { events[0] }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 7) }
    private var focused: Bool { events.contains { $0.id == store.focusedEventID } }
    /// Peeking edges only read as "a stack" once there's room for them; below that just show the front card.
    private var showsPeek: Bool { height >= 30 }
    private var peekLayers: [CalEvent] { Array(events.dropFirst().prefix(2)) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if showsPeek {
                ForEach(Array(peekLayers.enumerated().reversed()), id: \.offset) { i, e in
                    let inset = CGFloat(i + 1) * 3
                    shape
                        .fill(Theme.surface)
                        .overlay(shape.strokeBorder(e.color.opacity(0.55), lineWidth: 1.5))
                        .padding(EdgeInsets(top: inset, leading: inset, bottom: -inset, trailing: -inset))
                }
            }
            frontCard
                .padding(.trailing, showsPeek ? 6 : 0)
                .padding(.bottom, showsPeek ? 6 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .opacity(events.allSatisfy(\.isDeclined) ? 0.5 : 1)
        .help(helpText)
        .popover(isPresented: $showList, arrowEdge: .trailing) { calendarList }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    private var frontCard: some View {
        let c = front.color
        return VStack(alignment: .leading, spacing: 2) {
            Text(front.title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(height > 40 ? 2 : 1)
                .minimumScaleFactor(0.9)
            HStack(spacing: 6) {
                if height >= 40 {
                    Text(front.start.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 11).monospacedDigit()).opacity(0.75).lineLimit(1)
                }
                HStack(spacing: 3) {
                    ForEach(events.prefix(4)) { e in
                        Circle().fill(e.color).frame(width: 6, height: 6)
                    }
                    if events.count > 4 {
                        Text("+\(events.count - 4)").font(.system(size: 9, weight: .semibold)).opacity(0.7)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.eventText(c))
        .padding(.horizontal, 7).padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { ZStack { shape.fill(Theme.surface); shape.fill(c.opacity(hovering ? 0.26 : 0.17)) } }
        .overlay { shape.strokeBorder(c.opacity(0.55), lineWidth: 1.5) }
        .overlay { if focused { shape.inset(by: -1.5).strokeBorder(Theme.accent, lineWidth: 2) } }
        .contentShape(shape)
        .onHover { hovering = $0 }
        .onTapGesture { showList = true }
    }

    private var calendarList: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("On \(events.count) calendars")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text3)
                .padding(.bottom, 4)
            ForEach(events) { e in
                Button {
                    showList = false
                    store.focusedEventID = e.id
                    store.sheet = .detail(e)
                } label: {
                    HStack(spacing: 8) {
                        Circle().fill(e.color).frame(width: 8, height: 8)
                        Text(e.sourceName).font(.system(size: 12)).foregroundStyle(Theme.text).lineLimit(1)
                        Spacer(minLength: 8)
                        Text("\(e.start.formatted(date: .omitted, time: .shortened)) – \(e.end.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 11)).foregroundStyle(Theme.text3)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 5).padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.hover.opacity(0)))
                .contentShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(10)
        .frame(minWidth: 220)
    }

    private var helpText: String {
        let names = events.map(\.sourceName).joined(separator: ", ")
        return "\(front.title) · on \(names)"
    }

    private var accessibilityText: String {
        let time = front.start.formatted(date: .omitted, time: .shortened)
        return "\(front.title), \(time), on \(events.count) calendars"
    }
}

/// Live "new time range" preview shown in place of the real block while an event is dragged (move or resize).
struct DragGhost: View {
    let event: CalEvent
    let start: Date
    let end: Date

    var body: some View {
        let c = event.color
        RoundedRectangle(cornerRadius: 7)
            .fill(c.opacity(0.24))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(c, lineWidth: 1.5))
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text("\(start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 11).monospacedDigit()).opacity(0.8)
                }
                .foregroundStyle(Theme.eventText(c))
                .padding(.horizontal, 7).padding(.vertical, 4)
            }
    }
}

struct AllDayChip: View {
    @Environment(CalendarStore.self) private var store
    let event: CalEvent

    var body: some View {
        let c = event.color
        let shape = RoundedRectangle(cornerRadius: 5)
        let focused = store.focusedEventID == event.id
        Text(event.title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(event.isOverlay ? Theme.text2 : Theme.eventText(c))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
            .background {
                if event.isOverlay { Color.clear } else { ZStack { shape.fill(Theme.surface); shape.fill(c.opacity(0.17)) } }
            }
            .overlay { if event.isOverlay { shape.strokeBorder(c.opacity(0.6), lineWidth: 1.5) } }
            .overlay { if focused { shape.inset(by: -1.5).strokeBorder(Theme.accent, lineWidth: 2) } }
            .contentShape(shape)
            .onTapGesture { store.focusedEventID = event.id; store.sheet = .detail(event) }
            .accessibilityLabel("All-day: \(event.title)")
            .accessibilityAddTraits(.isButton)
    }
}
