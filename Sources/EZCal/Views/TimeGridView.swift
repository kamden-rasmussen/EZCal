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
    /// Arrival order (by start time) within this event's overlap cluster — drives z-order and the waterfall
    /// offset `DayColumn` uses to keep every overlapping card its own distinct, visible sliver. Not a
    /// side-by-side slot index.
    var column: Int
    /// How many events (after folding same-slot duplicates via `EventGrouping`) overlap in this cluster.
    var columns: Int
    /// Side-by-side slot index from a classic greedy interval-packing pass (Google-Calendar-style columns) —
    /// independent of `column` above. `OverlapCluster` uses this when `.auto` mode decides the column is wide
    /// enough to slice this cluster into real side-by-side cards instead of cascading them.
    var sideSlot: Int
    /// How many side-by-side slots this cluster needs (the packing's width, not `columns`' cluster size —
    /// two events that don't actually overlap in time can share a cluster via a third that overlaps both,
    /// yet still fit in 2 slots).
    var sideSlots: Int
    /// Shared by every `PlacedEvent` produced from the same overlap cluster, so `DayColumn` can regroup a flat
    /// placement list back into per-cluster views.
    var clusterID: String
    var id: String { item.id }
}

/// How a day column resolves a cluster of same-time events into cards. Persisted as a setting (General tab)
/// because side-by-side vs. cascade is a real readability trade-off, not just an implementation detail — see
/// `EventLayout.useSideBySide`. `.sideBySide` is the default: every mainstream calendar (Google, Apple, Outlook,
/// Fantastical) always slices into real columns positioned by true start/end time and just lets them narrow
/// under pressure, rather than switching metaphors. `.cascade` stays available as an explicit style choice for
/// people who'd rather see full-width overlaid cards than thin columns.
enum OverlapLayoutMode: String {
    case sideBySide   // always real side-by-side columns; narrows gracefully, never cascades
    case cascade      // always overlay full-width cards, cascaded — never slice into columns
    case auto         // side-by-side columns when a cluster's slice width would stay readable; cascade otherwise
}

enum EventLayout {
    /// Ideal per-layer reveal width in a cascaded (non-side-by-side) cluster: how much of each earlier-starting
    /// card stays visible along its left edge before the next, later-starting card covers the rest of it. Wide
    /// enough to show a card's color, rounded corner and a few characters of its title.
    static let cascadeStep: CGFloat = 40
    /// Absolute floor on a cascaded card's own width, however many events are piled into the cluster or however
    /// narrow the day column — guarantees every layer stays a distinct, clickable rect and never gets pushed
    /// past the column's right edge. See `EventLayoutCascadeTests`.
    static let cascadeMinCardWidth: CGFloat = 24
    /// Small per-layer vertical nudge, capped after a couple of layers. Its whole job is to keep two cascaded
    /// cards that happen to start at the very same time from putting their title rows on the exact same
    /// line — with only `waterfallOffset`'s horizontal step between them, a later card's title would butt
    /// directly up against the earlier card's exposed title with no separation, reading as one crowded,
    /// half-garbled label instead of two distinct stacked cards. Kept deliberately small (and capped at just 2
    /// layers, down from the original design's 3×7pt) — no other calendar app nudges a card off its true start
    /// time at all, so this only does the minimum needed to keep same-instant titles legible.
    static let cascadeYNudge: CGFloat = 4
    private static let cascadeYNudgeMaxLayers = 2

    /// Horizontal offset for the `index`-th (0 = earliest start, i.e. bottommost/leftmost) of `count` events
    /// cascaded across a `dayWidth`-wide column. Every layer gets the *same* step — unlike the old design (one
    /// full-width "front" card with everything else collapsed onto one identical, nearly-invisible offset), so
    /// each event keeps its own uniformly-sized, always-visible sliver instead of most of the space being
    /// spent on a single card while the rest sit fully hidden behind it. The step shrinks (never grows) so the
    /// last (topmost, fully visible) card's width never drops below `cascadeMinCardWidth` — which also means an
    /// offset can never push a card's frame past the column's own right edge, whatever `count` is.
    static func waterfallOffset(index: Int, count: Int, dayWidth: CGFloat) -> CGFloat {
        guard count > 1 else { return 0 }
        let maxOffset = max(dayWidth - 4 - cascadeMinCardWidth, 0)
        let step = min(cascadeStep, maxOffset / CGFloat(count - 1))
        return CGFloat(index) * step
    }

    /// Vertical companion to `waterfallOffset` — see `cascadeYNudge`. Caps out after a few layers instead of
    /// growing with `count`, since its only job is breaking up same-instant title rows, not fanning out a big
    /// pileup (that's what the horizontal step and each layer's own distinct rect are for).
    static func waterfallYNudge(index: Int) -> CGFloat {
        CGFloat(min(index, cascadeYNudgeMaxLayers)) * cascadeYNudge
    }

    /// Each event spans the full day-column width; overlapping events overlay one another (cascaded/z-ordered
    /// in `DayColumn`) instead of being packed into narrow side-by-side slices. Same-slot duplicates across
    /// calendars are first folded into a single stacked item by `EventGrouping`.
    static func place(_ events: [CalEvent], day: Date, cal: Calendar) -> [PlacedEvent] {
        let dayStart = cal.startOfDay(for: day)
        let dayEnd = cal.endOfDay(day)
        var items = EventGrouping.group(events).map { item in
            (item: item, s: max(item.start, dayStart), en: min(max(item.end, item.start.addingTimeInterval(20 * 60)), dayEnd))
        }
        items.sort { $0.s != $1.s ? $0.s < $1.s : $0.en > $1.en }

        var result: [PlacedEvent] = []
        var cluster: [(item: TimeGridItem, s: Date, en: Date)] = []
        var clusterEnd = Date.distantPast

        func flush() {
            guard !cluster.isEmpty else { return }
            let n = cluster.count
            // Classic greedy interval packing for the side-by-side alternative: each item takes the first
            // column whose previous occupant has already ended, opening a new column otherwise.
            var colEnds: [Date] = []
            var sideSlot: [Int] = []
            for it in cluster {
                if let free = colEnds.firstIndex(where: { $0 <= it.s }) {
                    colEnds[free] = it.en
                    sideSlot.append(free)
                } else {
                    colEnds.append(it.en)
                    sideSlot.append(colEnds.count - 1)
                }
            }
            let sideSlots = colEnds.count
            let clusterID = cluster.map(\.item.id).sorted().joined(separator: "|")
            result += cluster.enumerated().map { i, it in
                PlacedEvent(item: it.item, start: it.s, end: it.en, column: i, columns: n,
                            sideSlot: sideSlot[i], sideSlots: sideSlots, clusterID: clusterID)
            }
            cluster = []; clusterEnd = .distantPast
        }

        for it in items {
            if it.s >= clusterEnd { flush() }
            cluster.append(it)
            clusterEnd = max(clusterEnd, it.en)
        }
        flush()
        return result
    }

    /// Below this per-card width, side-by-side columns stop being worth it — a waterfall cascade (see
    /// `waterfallOffset`) reads better than a sliver too narrow for its own title.
    static let minSideBySideSliceWidth: CGFloat = 100
    /// Below this width a card switches to its compact style (drops the avatar/recurring icon, smaller title).
    static let compactCardWidth: CGFloat = 130

    /// Whether a cluster should be sliced into real side-by-side columns rather than cascaded. `.sideBySide`
    /// always says yes (columns just narrow, down to `EventBlock`'s compact/sliver styling); `.cascade` always
    /// says no; `.auto` says yes only if every resulting slice would stay at least `minSideBySideSliceWidth`
    /// wide — otherwise it falls back to a cascade for that cluster, even if other clusters on the same day are
    /// wide enough to slice.
    static func useSideBySide(sideSlots: Int, availableWidth: CGFloat, mode: OverlapLayoutMode) -> Bool {
        guard sideSlots > 1 else { return false }
        switch mode {
        case .sideBySide: return true
        case .cascade: return false
        case .auto:
            let slice = (availableWidth - 4) / CGFloat(sideSlots)
            return slice >= minSideBySideSliceWidth
        }
    }

    /// Regroups a flat placement list back into contiguous per-cluster arrays. Relies on `place` appending one
    /// cluster at a time, so `DayColumn` can render each cluster as its own `OverlapCluster` view, instead of
    /// one flat `ForEach` that can't tell where one cluster ends and the next begins.
    static func clusters(of placed: [PlacedEvent]) -> [[PlacedEvent]] {
        var result: [[PlacedEvent]] = []
        for p in placed {
            if !result.isEmpty, result[result.count - 1][0].clusterID == p.clusterID {
                result[result.count - 1].append(p)
            } else {
                result.append([p])
            }
        }
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
    @AppStorage("overlapLayoutMode") private var overlapLayoutModeRaw = OverlapLayoutMode.sideBySide.rawValue
    let day: Date
    let hourHeight: Double

    @State private var dragRange: (Double, Double)?
    /// Set for the rest of a gesture once it's been repurposed to close the open event-detail panel (see
    /// `createGesture`), so a click-and-drag that started while it was open never also falls through to
    /// creating an event.
    @State private var closingDetail = false

    private var overlapMode: OverlapLayoutMode { OverlapLayoutMode(rawValue: overlapLayoutModeRaw) ?? .sideBySide }

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

                ForEach(EventLayout.clusters(of: placed), id: \.[0].clusterID) { cluster in
                    OverlapCluster(cluster: cluster, dayStart: dayStart, hourHeight: hourHeight,
                                   dayWidth: geo.size.width, mode: overlapMode)
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

    /// A click (or click-and-drag) on empty grid space normally starts creating an event. But if the
    /// event-detail panel is currently docked open, that same click just closes it instead — clicking into
    /// the main page reads as "I'm done looking at that event," not "make me a new one underneath it."
    private var createGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if dragRange == nil, !closingDetail, store.isShowingDetail {
                    closingDetail = true
                    store.sheet = nil
                    return
                }
                guard !closingDetail else { return }
                if abs(v.translation.height) > 4 { dragRange = (snap(v.startLocation.y), snap(v.location.y)) }
            }
            .onEnded { v in
                defer { dragRange = nil; closingDetail = false }
                guard !closingDetail else { return }
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

/// Renders one overlap cluster (1+ same-time events, post `EventGrouping` folding), either sliced into
/// side-by-side columns (the default — see `OverlapLayoutMode`) or, in `.cascade` mode (always) or `.auto`
/// mode (only when the column's too narrow for columns to stay readable), cascaded: every card gets its own
/// uniformly-sized visible sliver (`EventLayout.waterfallOffset`) along its left edge, later-starting events
/// layered on top. Nothing is ever fully hidden — however big the pileup, each event stays its own distinct,
/// clickable rect, so there's no need to hover-and-wait to bring a buried card to the front.
struct OverlapCluster: View {
    let cluster: [PlacedEvent]   // sorted ascending by `column` (arrival order); all share one `clusterID`
    let dayStart: Date
    let hourHeight: Double
    let dayWidth: CGFloat
    let mode: OverlapLayoutMode

    private var n: Int { cluster.count }
    private var sideBySide: Bool {
        guard let first = cluster.first else { return false }
        return EventLayout.useSideBySide(sideSlots: first.sideSlots, availableWidth: dayWidth, mode: mode)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(cluster.enumerated()), id: \.element.id) { i, p in
                let top = p.start.timeIntervalSince(dayStart) / 3600 * hourHeight + 1
                let h = max(p.end.timeIntervalSince(p.start) / 3600 * hourHeight - 2, 18)

                if sideBySide {
                    let slotW = max((dayWidth - 4) / CGFloat(p.sideSlots), 24)
                    let w = max(slotW - 3, 24)
                    card(p, height: h, compact: w < EventLayout.compactCardWidth, cascaded: false)
                        .frame(width: w, height: h)
                        .offset(x: 2 + slotW * CGFloat(p.sideSlot), y: top)
                        .zIndex(Double(i))
                } else {
                    let offsetX = EventLayout.waterfallOffset(index: i, count: n, dayWidth: dayWidth)
                    let offsetY = EventLayout.waterfallYNudge(index: i)
                    let w = max(dayWidth - 4 - offsetX, 24)
                    card(p, height: h, compact: w < EventLayout.compactCardWidth, cascaded: true)
                        .frame(width: w, height: h)
                        .offset(x: 2 + offsetX, y: top + offsetY)
                        .zIndex(Double(i))
                }
            }
        }
    }

    @ViewBuilder
    private func card(_ p: PlacedEvent, height: Double, compact: Bool, cascaded: Bool) -> some View {
        switch p.item {
        case .single(let event):
            EventBlock(event: event, height: height, overlapping: n > 1, cascaded: cascaded, compact: compact,
                       hourHeight: hourHeight, dayWidth: dayWidth)
        case .stack(let events):
            StackedEventBlock(events: events, height: height, compact: compact)
        }
    }
}

// MARK: - Event visuals

struct EventBlock: View {
    @Environment(CalendarStore.self) private var store
    let event: CalEvent
    let height: Double
    /// True when this event overlaps at least one other in the same day column. Full width is used either way
    /// (issue #20) — this only dials back fill opacity and adds a border so overlaid cards stay legible.
    var overlapping = false
    /// True when `OverlapCluster` is rendering this in cascade style (genuinely stacked in z-order) rather than
    /// as a side-by-side column. Side-by-side cards sit edge-to-edge, not on top of one another, so they keep
    /// `overlapping`'s existing border/shadow; a cascaded card gets a visibly softer border and shadow instead
    /// — it's already doing more visual work by overlaying its neighbors, so it doesn't need as much of either.
    var cascaded = false
    /// True when `OverlapCluster` sliced this into a side-by-side column too narrow for the full layout —
    /// drops the avatar/recurring icon and the video-join button, and shrinks the title, so the card still
    /// reads at a glance instead of truncating everything to fit.
    var compact = false
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
                if let o = event.ownerName, !compact {
                    Text(String(o.prefix(1)).uppercased())
                        .font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 14, height: 14).background(Circle().fill(c))
                        .padding(.top, 0.5)
                }
                if event.isRecurring, !compact {
                    Image(systemName: "repeat").font(.system(size: 9)).opacity(0.75).padding(.top, 1)
                        .accessibilityHidden(true)
                }
                Text(titleText)
                    .font(.system(size: compact ? 11 : 12, weight: .semibold))
                    .strikethrough(event.isDeclined)
                    .lineLimit(height > 40 ? 2 : 1)
                    .minimumScaleFactor(compact ? 0.9 : 1)
                Spacer(minLength: 0)
                if let url = event.meetingURL, height >= 28, !compact {
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
        .padding(.horizontal, compact ? 5 : 7).padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            if event.isBusyOnly { Hatch(color: c).clipShape(shape) }
            else if event.isOverlay { shape.fill(hovering ? c.opacity(0.08) : Color.clear) }
            // Overlapping same-calendar events now overlay each other at full width (issue #20), so their
            // fill is a touch lighter than a lone event's — that plus the border below keeps a card's own
            // edges (and the edges of whatever it's cascaded over) readable.
            else { ZStack { shape.fill(Theme.surface); shape.fill(c.opacity(hovering ? 0.28 : (overlapping ? 0.14 : 0.17))) } }
        }
        .overlay {
            if event.isOverlay { shape.strokeBorder(c.opacity(0.6), lineWidth: event.isBusyOnly ? 1 : 1.5) }
            else if cascaded { shape.strokeBorder(c.opacity(0.35), lineWidth: 1) }
            else if overlapping { shape.strokeBorder(c.opacity(0.45), lineWidth: 1) }
        }
        .shadow(color: cascaded ? .black.opacity(0.12) : (overlapping ? .black.opacity(0.18) : .clear),
                radius: cascaded ? 2 : 3, y: 1)
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
    var compact = false
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
                .font(.system(size: compact ? 11 : 12, weight: .semibold))
                .lineLimit(height > 40 ? 2 : 1)
                .minimumScaleFactor(0.9)
            HStack(spacing: 6) {
                if height >= 40 && !compact {
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
        .padding(.horizontal, compact ? 5 : 7).padding(.vertical, 4)
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
