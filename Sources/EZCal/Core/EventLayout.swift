import Foundation
import CoreGraphics

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
