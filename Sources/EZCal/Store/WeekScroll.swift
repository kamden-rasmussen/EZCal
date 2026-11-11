import Foundation

/// Store side of the continuously scrolling Week / Work Week grid (`Views/WeekScrollView.swift`).
/// In those two modes `anchor` is the leftmost visible day.
///
/// macOS always does this. iOS keeps a paged, week-aligned Week grid unless the "Swipe by day" setting
/// (`weekSwipeByDayKey`, on by default) is on; then `visibleDays`/`fetchRange` follow `anchor` like macOS.
extension CalendarStore {
    static let weekSwipeByDayKey = "weekSwipeByDay"

    static var continuousWeekScroll: Bool {
        #if os(macOS)
        true
        #else
        UserDefaults.standard.object(forKey: weekSwipeByDayKey) as? Bool ?? true
        #endif
    }

    /// How many columns the current week-style mode shows, and which days get one.
    var weekColumns: (count: Int, rule: WeekScrollMath.ColumnRule) {
        if mode == .workWeek { return (5, .monFri) }
        return AppSettings.showWeekends ? (7, .all) : (5, .localeWeekdays)
    }

    /// What `anchor` should become to "go to" `d`: in Week / Work Week the containing week's first column
    /// (matching the old paged behaviour for Today and jump-to-date); other modes keep `d` unchanged.
    func alignedLeading(for d: Date) -> Date {
        guard Self.continuousWeekScroll, alignsLeadingToWeek else { return d }
        switch mode {
        case .workWeek:
            return WeekScrollMath.firstColumnDay(onOrAfter: mondayStart(d), rule: .monFri, cal: cal)
        case .week:
            return WeekScrollMath.firstColumnDay(onOrAfter: weekStart(d), rule: weekColumns.rule, cal: cal)
        case .day, .threeDay, .month:
            return d
        }
    }

    /// Mini-calendar click: in Week / Work Week the clicked day itself becomes the leading column (the next column
    /// day if it's hidden), so the click always visibly moves the grid; other modes behave like `goTo`.
    func goToDay(_ d: Date) {
        guard Self.continuousWeekScroll, mode == .week || mode == .workWeek else { goTo(d); return }
        anchor = WeekScrollMath.firstColumnDay(onOrAfter: d, rule: weekColumns.rule, cal: cal)
        scheduleReload()
    }

    /// The scrolling grid reports a new leftmost day. Updates the anchor (and so the title) immediately, and
    /// refetches events (debounced) only once the visible range nears the edge of what is already loaded.
    func weekScrollAnchorChanged(to day: Date) {
        anchor = day
        let days = visibleDays
        guard let f = days.first, let l = days.last else { return }
        let visible = f..<cal.endOfDay(l)
        if WeekScrollMath.needsReload(visible: visible, loaded: loadedRange, margin: 7 * 24 * 3600) {
            scheduleReload()   // already debounced (120ms)
        }
    }
}
