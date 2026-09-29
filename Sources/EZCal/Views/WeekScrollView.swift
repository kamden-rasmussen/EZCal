import SwiftUI
import AppKit

// MARK: - Continuously scrolling Week / Work Week grid
//
// Layout (macOS Week and Work Week; Day keeps `TimeGridView`):
//
//   +--------+---------------------------------------------+
//   | gutter |  header strip: day names + all-day chips    |  pinned vertically; its cells are positioned from the
//   +--------+---------------------------------------------+  grid's live horizontal offset (pixel-level tracking)
//   | hours  |  horizontal ScrollView of lazy DayColumns   |  the whole row scrolls vertically; hour gutter stays put
//   +--------+---------------------------------------------+  horizontally because it is outside the inner scroller
//
// The inner horizontal ScrollView uses `.viewAligned` so a gesture glides with inertia and settles on a day
// boundary. Column width = grid width / visible day count. `store.anchor` is the leftmost visible day.

struct WeekScrollView: View {
    @Environment(CalendarStore.self) private var store
    @AppStorage("showWeekends") private var showWeekends = true

    var body: some View {
        // A fresh grid (fresh scroll state, window and column width) whenever the column layout changes.
        WeekScrollGrid(mode: store.mode, showWeekends: showWeekends)
            .id("\(store.mode.rawValue)-\(showWeekends)")
    }
}

/// Scroll bookkeeping kept out of `@State` so the per-frame offset only invalidates the header strip, not the grid.
@MainActor @Observable
final class WeekScrollModel {
    /// Horizontal content offset of the day grid, in points. Only `WeekHeaderStrip` reads this.
    var offset: CGFloat = 0
    /// Leftmost (nearest-snap) day currently shown.
    @ObservationIgnored var leading: Date?
    /// Day a programmatic scroll is heading to; while set, scroll-derived anchor updates are suppressed.
    @ObservationIgnored var target: Date?
    /// Days this grid itself just wrote to `store.anchor`, so the anchor observer can tell them from external
    /// navigation (toolbar, keys, Today) and not scroll back to a stale value.
    @ObservationIgnored var recentPushes: [(day: Date, at: Date)] = []
    @ObservationIgnored var proxy: ScrollViewProxy?
    @ObservationIgnored var targetTask: Task<Void, Never>?
    @ObservationIgnored var extendTask: Task<Void, Never>?
}

struct WeekScrollGrid: View {
    @Environment(CalendarStore.self) private var store
    @AppStorage("hourHeight") private var hourHeight = 56.0
    @AppStorage("showSecondaryZone") private var showSecondaryZone = true
    @AppStorage("secondaryZoneID") private var secondaryZoneID = ""
    let mode: ViewMode
    let showWeekends: Bool

    /// Columns rendered lazily (a few weeks either side of the anchor); extended as the user nears an end.
    @State private var days: [Date] = []
    @State private var model = WeekScrollModel()
    /// Hidden until the initial scroll position has been applied, so the strip never flashes its first day.
    @State private var ready = false
    @State private var hourHeightAtPinchStart: Double?

    private let gutter: CGFloat = 56
    private let trailing: CGFloat = 8
    private let coordinateSpaceName = "weekScroll"
    /// Window size in weeks either side of the anchor; extended by `extendWeeks` when within `edgeWeeks` of an end.
    private let windowWeeks = 26, extendWeeks = 26, edgeWeeks = 4

    private var rule: WeekScrollMath.ColumnRule { mode == .workWeek ? .monFri : (showWeekends ? .all : .localeWeekdays) }
    private var count: Int { (mode == .workWeek || !showWeekends) ? 5 : 7 }
    private var secondaryZone: TimeZone? { AppSettings.effectiveZone(id: secondaryZoneID, show: showSecondaryZone) }
    private var secondaryWidth: CGFloat { secondaryZone == nil ? 0 : 44 }

    var body: some View {
        GeometryReader { geo in
            let gridW = max(geo.size.width - gutter - secondaryWidth - trailing, 1)
            let colW = gridW / CGFloat(count)
            VStack(spacing: 0) {
                WeekHeaderStrip(model: model, days: days, colW: colW, gridW: gridW, gutter: gutter,
                                secondaryZone: secondaryZone, secondaryWidth: secondaryWidth)
                Divider().overlay(Theme.line)
                hourScroller(colW: colW, gridW: gridW)
            }
            .opacity(ready ? 1 : 0)
            .onChange(of: gridW) { _, _ in
                // Window resized: the same offset now means a different day, so pin the current one back to the edge.
                guard ready, let lead = model.leading else { return }
                beginProgrammatic(target: lead)
                Task { @MainActor in scrollTo(lead, animated: false) }
            }
            .onPreferenceChange(WeekScrollOffsetKey.self) { handleOffset($0, colW: colW) }
        }
        .background(Theme.bg)
        .task { await setUp() }
        .onChange(of: store.anchor) { _, a in anchorChangedExternally(a) }
    }

    // MARK: Grid

    private func hourScroller(colW: CGFloat, gridW: CGFloat) -> some View {
        ScrollViewReader { vproxy in
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    WeekHourGutter(hourHeight: hourHeight, gutter: gutter)
                    if let zone = secondaryZone {
                        WeekSecondaryGutter(zone: zone, hourHeight: hourHeight, width: secondaryWidth)
                    }
                    dayScroller(colW: colW)
                        .frame(width: gridW, height: hourHeight * 24)
                    Color.clear.frame(width: trailing, height: 1)
                }
                .background(alignment: .topLeading) { hourLines }
            }
            .scrollIndicators(.hidden)
            // Pinch-to-zoom (trackpad), same as the Day grid: `hourHeight` is @AppStorage-backed and shared.
            .gesture(pinchToZoomGesture)
            .task {
                try? await Task.sleep(nanoseconds: 60_000_000)   // let the grid lay out first
                let start = AppSettings.workingHours.startHour
                let now = Calendar.current.component(.hour, from: Date())
                vproxy.scrollTo("hour-\(min(max(now - 4, start), start + 2))", anchor: .top)
            }
            .onChange(of: store.focusedEventID) { _, _ in
                guard let e = store.focusedEvent, !e.isAllDay else { return }
                vproxy.scrollTo("hour-\(Calendar.current.component(.hour, from: e.start))", anchor: .center)
            }
        }
    }

    private func dayScroller(colW: CGFloat) -> some View {
        ScrollViewReader { hproxy in
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 0) {
                    ForEach(days, id: \.self) { day in
                        DayColumn(day: day, hourHeight: hourHeight)
                            .frame(width: colW, height: hourHeight * 24)
                            .id(day)
                    }
                }
                .scrollTargetLayout()
                .background(ScrollOffsetReader { handleOffset($0, colW: colW) })
                .background {
                    // Fallback path; the AppKit reader above is the reliable per-frame source.
                    GeometryReader { g in
                        Color.clear.preference(key: WeekScrollOffsetKey.self,
                                               value: -g.frame(in: .named(coordinateSpaceName)).minX)
                    }
                }
            }
            .coordinateSpace(name: coordinateSpaceName)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .onAppear { model.proxy = hproxy }
        }
    }

    private var hourLines: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { _ in
                Rectangle().fill(Theme.line2).frame(height: 1).frame(height: hourHeight, alignment: .top)
            }
        }
        .padding(.leading, gutter + secondaryWidth)
        .padding(.trailing, trailing)
        .allowsHitTesting(false)
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

    // MARK: Scroll <-> anchor

    private func setUp() async {
        let cal = store.cal
        // Entering the view (or switching between Week and Work Week) starts on the week containing the anchor.
        let lead = store.alignedLeading(for: store.anchor)
        days = WeekScrollMath.window(around: lead, before: windowWeeks * count, after: windowWeeks * count, rule: rule, cal: cal)
        model.leading = lead
        model.recentPushes.append((lead, Date()))
        if !cal.isDate(store.anchor, inSameDayAs: lead) { store.weekScrollAnchorChanged(to: lead) }
        beginProgrammatic(target: lead)
        try? await Task.sleep(nanoseconds: 80_000_000)   // let the lazy strip lay out before scrolling in it
        scrollTo(lead, animated: false)
        try? await Task.sleep(nanoseconds: 40_000_000)
        ready = true
    }

    /// Called for every content-offset change of the day grid (every frame while scrolling).
    private func handleOffset(_ offset: CGFloat, colW: CGFloat) {
        model.offset = offset
        guard ready, !days.isEmpty else { return }
        let idx = WeekScrollMath.leadingIndex(offset: offset, colWidth: colW, count: days.count)
        let d = days[idx]
        if let t = model.target, d == t { model.target = nil; model.targetTask?.cancel() }   // arrived
        guard model.leading != d else { return }
        model.leading = d
        // Programmatic scroll still in flight: the anchor is already where it should end up.
        if model.target != nil { return }
        model.recentPushes.removeAll { Date().timeIntervalSince($0.at) > 1.5 }
        model.recentPushes.append((d, Date()))
        Task { @MainActor in store.weekScrollAnchorChanged(to: d) }
        scheduleExtend()
    }

    /// `store.anchor` changed. Ours (echo of a scroll) are ignored; anything else (toolbar prev/next, [ ] keys,
    /// Today, jump-to-date) scrolls the grid there.
    private func anchorChangedExternally(_ a: Date) {
        guard ready else { return }
        let cal = store.cal
        let target = WeekScrollMath.firstColumnDay(onOrAfter: a, rule: rule, cal: cal)
        model.recentPushes.removeAll { Date().timeIntervalSince($0.at) > 1.5 }
        if model.recentPushes.contains(where: { $0.day == target }) { return }
        if model.leading == target, model.target == nil { return }

        beginProgrammatic(target: target)
        if let to = days.firstIndex(of: target) {
            let from = model.leading.flatMap { days.firstIndex(of: $0) } ?? to
            scrollTo(target, animated: WeekScrollMath.shouldAnimate(columns: to - from))
        } else {
            // Far outside the loaded window: rebuild it around the target and cut there.
            days = WeekScrollMath.window(around: target, before: windowWeeks * count, after: windowWeeks * count, rule: rule, cal: cal)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 50_000_000)
                scrollTo(target, animated: false)
            }
        }
    }

    private func scrollTo(_ day: Date, animated: Bool) {
        guard let p = model.proxy else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.35)) { p.scrollTo(day, anchor: .leading) }
        } else {
            p.scrollTo(day, anchor: .leading)
        }
    }

    /// Suppresses scroll-derived anchor writes until the grid reaches `target` (or a safety timeout passes).
    private func beginProgrammatic(target: Date) {
        model.target = target
        model.targetTask?.cancel()
        model.targetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            model.target = nil
        }
    }

    /// After the scroll settles (no leading-day change for 350ms), grow the window if the user got near an end.
    private func scheduleExtend() {
        model.extendTask?.cancel()
        model.extendTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, model.target == nil,
                  let lead = model.leading, let idx = days.firstIndex(of: lead),
                  let grown = WeekScrollMath.extended(days, leadingIndex: idx, visibleCount: count,
                                                      thresholdColumns: edgeWeeks * count, chunk: extendWeeks * count,
                                                      rule: rule, cal: store.cal)
            else { return }
            days = grown.days
            if grown.prepended > 0 {
                // Columns were inserted in front: pin the current day back to the leading edge.
                beginProgrammatic(target: lead)
                try? await Task.sleep(nanoseconds: 50_000_000)
                scrollTo(lead, animated: false)
            }
        }
    }
}

/// Reports the horizontal content offset of the NSScrollView enclosing it, on every bounds change (i.e. every
/// frame of a drag or inertial glide). Placed in the scroll content's background. SwiftUI's GeometryReader
/// preference does not reliably fire while a ScrollView scrolls on macOS, so this reads AppKit directly.
private struct ScrollOffsetReader: NSViewRepresentable {
    let onChange: (CGFloat) -> Void

    final class Tracker: NSView {
        var onChange: ((CGFloat) -> Void)?
        private var observer: NSObjectProtocol?
        private weak var clip: NSClipView?

        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); attach() }
        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); attach() }

        func attach() {
            guard let clipView = enclosingScrollView?.contentView, clipView !== clip else { return }
            if let o = observer { NotificationCenter.default.removeObserver(o) }
            clip = clipView
            clipView.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clipView, queue: .main) { [weak self, weak clipView] _ in
                guard let clipView else { return }
                self?.onChange?(clipView.bounds.origin.x)
            }
            onChange?(clipView.bounds.origin.x)
        }
        deinit { if let o = observer { NotificationCenter.default.removeObserver(o) } }
    }

    func makeNSView(context: Context) -> Tracker {
        let t = Tracker()
        t.onChange = onChange
        DispatchQueue.main.async { [weak t] in t?.attach() }   // superview chain may not be complete yet
        return t
    }
    func updateNSView(_ nsView: Tracker, context: Context) {
        nsView.onChange = onChange
        nsView.attach()
    }
}

private struct WeekScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Header strip

/// Day names and all-day chips, pinned above the hour grid. It is not itself scrollable: it draws only the
/// columns near the viewport and shifts them by the day grid's live offset, so dates track the pan pixel for pixel.
private struct WeekHeaderStrip: View {
    @Environment(CalendarStore.self) private var store
    let model: WeekScrollModel
    let days: [Date]
    let colW: CGFloat
    let gridW: CGFloat
    let gutter: CGFloat
    let secondaryZone: TimeZone?
    let secondaryWidth: CGFloat

    private let dayRowHeight: CGFloat = 48

    var body: some View {
        let offset = model.offset
        let range = WeekScrollMath.visibleIndices(offset: offset, colWidth: colW, viewport: gridW, count: days.count, overscan: 1)
        // Row height follows the columns actually near the viewport.
        let rows = range.map { r in days[r].map { allDayCount($0) }.max() ?? 0 } ?? 0
        let chipsHeight: CGFloat = rows > 0 ? CGFloat(rows) * 22 + 6 : 0

        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                Color.clear.frame(width: gutter, height: dayRowHeight)
                if rows > 0 {
                    Text("all-day").font(.system(size: 11)).foregroundStyle(Theme.text3)
                        .frame(width: gutter - 8, alignment: .trailing).padding(.trailing, 8).padding(.top, 6)
                        .frame(width: gutter, height: chipsHeight, alignment: .topLeading)
                }
            }
            if let zone = secondaryZone {
                Text(ZoneMath.shortName(zone))
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.text3)
                    .frame(width: secondaryWidth, height: dayRowHeight, alignment: .center)
                    .frame(width: secondaryWidth, height: dayRowHeight + chipsHeight, alignment: .top)
                    .help("Secondary time zone: \(zone.identifier)")
            }
            ZStack(alignment: .topLeading) {
                if let r = range {
                    WeekHeaderCells(days: Array(days[r]), colW: colW, dayRowHeight: dayRowHeight, chipsHeight: chipsHeight)
                        .offset(x: WeekScrollMath.columnX(index: r.lowerBound, colWidth: colW, offset: offset))
                }
            }
            .frame(width: gridW, height: dayRowHeight + chipsHeight, alignment: .topLeading)
            .clipped()
            Color.clear.frame(width: 8, height: 1)
        }
        .padding(.bottom, rows > 0 ? 2 : 0)
    }

    private func allDayCount(_ day: Date) -> Int {
        // Tasks due that day with no specific time ride along in the all-day row too.
        store.events(on: day).allDay.count + store.tasks.tasks(on: day, cal: store.cal).allDay.count
    }
}

/// The header cells for a slice of days, laid out left to right at `colW` each. Inputs are plain values so SwiftUI
/// skips re-evaluating it while only the parent's offset changes.
private struct WeekHeaderCells: View {
    @Environment(CalendarStore.self) private var store
    let days: [Date]
    let colW: CGFloat
    let dayRowHeight: CGFloat
    let chipsHeight: CGFloat

    var body: some View {
        // .everyMinute keeps the "today" circle correct across a midnight rollover on a long-running window.
        TimelineView(.everyMinute) { _ in
            HStack(alignment: .top, spacing: 0) {
                ForEach(days, id: \.self) { day in
                    let isToday = Calendar.current.isDateInToday(day)
                    VStack(spacing: 0) {
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
                        .frame(maxWidth: .infinity).frame(height: dayRowHeight)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { store.anchor = day; store.setMode(.day) }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))

                        if chipsHeight > 0 {
                            let events = store.events(on: day).allDay
                            let tasks = store.tasks.tasks(on: day, cal: store.cal).allDay
                            VStack(spacing: 2) {
                                ForEach(events) { e in AllDayChip(event: e) }
                                ForEach(tasks) { t in TaskChip(task: t) }
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                            .padding(.horizontal, 3).padding(.vertical, 4)
                            .frame(height: chipsHeight, alignment: .top)
                        }
                    }
                    .frame(width: colW)
                }
            }
        }
    }
}

// MARK: - Gutters

struct WeekHourGutter: View {
    let hourHeight: Double
    let gutter: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { h in
                // Cell top is 8pt above the hour line, so scrolling to a cell keeps its label fully visible.
                Text(h == 0 ? "" : label(h))
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

    private func label(_ h: Int) -> String {
        let d = Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date())!
        return d.formatted(.dateTime.hour())
    }
}

/// Second hour column showing the same instants converted into `zone`'s wall clock (e.g. "9 AM" -> "6 PM CET").
struct WeekSecondaryGutter: View {
    @Environment(CalendarStore.self) private var store
    let zone: TimeZone
    let hourHeight: Double
    let width: CGFloat

    var body: some View {
        let refDay = store.anchor
        let dayStart = Calendar.current.startOfDay(for: refDay)
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { h in
                let instant = Calendar.current.date(byAdding: .hour, value: h, to: dayStart) ?? refDay
                Text(h == 0 ? "" : ZoneMath.hourLabel(instant, in: zone))
                    .font(.system(size: 10).monospacedDigit()).foregroundStyle(Theme.text3.opacity(0.85))
                    .padding(.top, 1)
                    .frame(width: width, height: hourHeight, alignment: .top)
                    .accessibilityHidden(true)
            }
        }
        .padding(.top, -8)
        .frame(width: width, alignment: .leading)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.line2).frame(width: 1) }
    }
}
