import Foundation

// MARK: - Model

/// One VEVENT read from an .ics feed. Times are absolute instants; `timeZone` is the zone the
/// original DTSTART was expressed in (needed so recurrence expansion adds days/weeks/months in the
/// right wall-clock zone instead of drifting across DST). All-day events use midnight-to-midnight
/// boundaries in the exclusive-end convention the rest of the app uses (see `RFC3339.parseDay`).
struct ICSEvent: Hashable {
    var uid: String
    var summary: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var location: String
    var description: String
    var url: URL?
    var timeZone: TimeZone
    var recurrence: ICSRecurrenceRule?
    var exceptionDates: Set<Date> = []
}

/// A parsed RRULE. Supports the frequencies and modifiers the app's iCalendar subscriptions need:
/// FREQ (daily/weekly/monthly/yearly), INTERVAL, COUNT, UNTIL and BYDAY (including ordinals like
/// "2TU" or "-1FR" for monthly rules). Not supported: BYMONTHDAY, BYSETPOS, BYMONTH, RECURRENCE-ID
/// overrides — uncommon in the sports/holiday/team feeds this feature targets.
struct ICSRecurrenceRule: Hashable {
    enum Frequency: String { case daily = "DAILY", weekly = "WEEKLY", monthly = "MONTHLY", yearly = "YEARLY" }

    /// `weekday` uses ISO numbering: 1 = Monday … 7 = Sunday.
    struct Weekday: Hashable { var ordinal: Int?; var weekday: Int }

    var frequency: Frequency
    var interval: Int = 1
    var count: Int?
    var until: Date?
    var byDay: [Weekday] = []
}

// MARK: - Recurrence expansion

extension ICSRecurrenceRule {
    private static let hardCap = 2000   // safety valve against pathological/unbounded feeds

    /// Occurrence start dates that fall within `range`, in chronological order. `seriesStart` is the
    /// event's own DTSTART — expansion always counts from there (so COUNT is correct) even though only
    /// occurrences inside `range` are returned.
    func occurrences(seriesStart: Date, timeZone: TimeZone, range: Range<Date>) -> [Date] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.firstWeekday = 2 // Monday; used only as an internal week-bucketing convention

        var results: [Date] = []
        var index = 0

        /// Applies COUNT/UNTIL/range bounds to one candidate. Returns false when expansion should stop.
        func consider(_ date: Date) -> Bool {
            index += 1
            if let count, index > count { return false }
            if let until, date > until { return false }
            if date >= range.upperBound { return false }
            if date >= range.lowerBound { results.append(date) }
            return index < Self.hardCap
        }

        switch frequency {
        case .daily:
            var cur = seriesStart
            while consider(cur) {
                guard let next = cal.date(byAdding: .day, value: interval, to: cur) else { break }
                cur = next
            }

        case .weekly:
            let days = byDay.isEmpty ? [Self.isoWeekday(of: seriesStart, cal: cal)] : byDay.map(\.weekday).sorted()
            guard var weekAnchor = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: seriesStart)) else { break }
            outer: while true {
                for wd in days {
                    guard let day = cal.date(byAdding: .day, value: wd - 1, to: weekAnchor),
                          let candidate = Self.applyTimeOfDay(from: seriesStart, to: day, cal: cal),
                          candidate >= seriesStart else { continue }
                    if !consider(candidate) { break outer }
                }
                guard let next = cal.date(byAdding: .weekOfYear, value: interval, to: weekAnchor) else { break }
                weekAnchor = next
            }

        case .monthly:
            var comps = cal.dateComponents([.year, .month], from: seriesStart)
            let seriesDay = cal.component(.day, from: seriesStart)
            outer2: while true {
                let candidates = byDay.isEmpty
                    ? Self.dateForDayOfMonth(seriesDay, comps: comps, timeOfDay: seriesStart, cal: cal).map { [$0] } ?? []
                    : Self.monthlyByDayCandidates(comps: comps, byDay: byDay, timeOfDay: seriesStart, cal: cal)
                for c in candidates.sorted() where c >= seriesStart {
                    if !consider(c) { break outer2 }
                }
                guard let base = cal.date(from: comps), let advanced = cal.date(byAdding: .month, value: interval, to: base) else { break }
                comps = cal.dateComponents([.year, .month], from: advanced)
                if let y = comps.year, y > 3000 { break }   // unreachable in practice; guards a logic bug turning into a hang
            }

        case .yearly:
            var cur = seriesStart
            while consider(cur) {
                guard let next = cal.date(byAdding: .year, value: interval, to: cur) else { break }
                cur = next
            }
        }
        return results
    }

    private static func isoWeekday(of date: Date, cal: Calendar) -> Int {
        let w = cal.component(.weekday, from: date)   // Apple: 1 = Sunday … 7 = Saturday
        return w == 1 ? 7 : w - 1
    }

    private static func appleWeekday(_ iso: Int) -> Int { iso == 7 ? 1 : iso + 1 }

    /// Combines `day`'s calendar date with `seriesStart`'s time-of-day.
    private static func applyTimeOfDay(from seriesStart: Date, to day: Date, cal: Calendar) -> Date? {
        var c = cal.dateComponents([.year, .month, .day], from: day)
        let t = cal.dateComponents([.hour, .minute, .second], from: seriesStart)
        c.hour = t.hour; c.minute = t.minute; c.second = t.second
        return cal.date(from: c)
    }

    /// `nil` if `day` doesn't exist in that month (e.g. day 31 in a 30-day month) — such months are
    /// skipped entirely, per RFC 5545.
    private static func dateForDayOfMonth(_ day: Int, comps: DateComponents, timeOfDay: Date, cal: Calendar) -> Date? {
        var c = comps
        c.day = day
        let t = cal.dateComponents([.hour, .minute, .second], from: timeOfDay)
        c.hour = t.hour; c.minute = t.minute; c.second = t.second
        guard let date = cal.date(from: c), cal.component(.day, from: date) == day else { return nil }
        return date
    }

    private static func monthlyByDayCandidates(comps: DateComponents, byDay: [Weekday], timeOfDay: Date, cal: Calendar) -> [Date] {
        let t = cal.dateComponents([.hour, .minute, .second], from: timeOfDay)
        return byDay.compactMap { wd -> Date? in
            var c = comps
            c.weekday = appleWeekday(wd.weekday)
            c.weekdayOrdinal = wd.ordinal ?? 1
            c.hour = t.hour; c.minute = t.minute; c.second = t.second
            return cal.date(from: c)
        }
    }
}

// MARK: - Parser

/// A small, dependency-free RFC 5545 (iCalendar) reader. Handles folded lines, quoted/escaped text,
/// VALUE=DATE (all-day) vs. date-time (UTC "Z", TZID, or floating), and RRULE/EXDATE. Anything it
/// doesn't recognize (VALARM, VTIMEZONE component bodies, X- properties, …) is ignored rather than
/// treated as an error, so one malformed property doesn't drop the whole feed.
enum ICSParser {
    private struct Property { var name: String; var params: [String: String]; var value: String }

    static func parse(_ text: String) -> [ICSEvent] {
        var events: [ICSEvent] = []
        var stack: [String] = []
        var current: [Property] = []

        for line in unfold(text) {
            guard let prop = parseLine(line) else { continue }
            switch prop.name {
            case "BEGIN":
                let component = prop.value.uppercased()
                if component == "VEVENT" { current = [] }
                stack.append(component)
            case "END":
                let component = prop.value.uppercased()
                if component == "VEVENT", stack.last == "VEVENT", let ev = buildEvent(current) { events.append(ev) }
                if stack.last == component { stack.removeLast() }
            default:
                if stack.last == "VEVENT" { current.append(prop) }
            }
        }
        return events
    }

    // MARK: Line unfolding (RFC 5545 §3.1: a line starting with a space or tab continues the previous one)

    static func unfold(_ text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var out: [String] = []
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            if let first = line.first, first == " " || first == "\t", !out.isEmpty {
                out[out.count - 1] += line.dropFirst()
            } else if !line.isEmpty {
                out.append(String(line))
            }
        }
        return out
    }

    // MARK: Property line ("NAME;PARAM=VALUE;...:value")

    private static func parseLine(_ line: String) -> Property? {
        guard let colon = firstUnquotedIndex(of: ":", in: line) else { return nil }
        let head = line[line.startIndex..<colon]
        let value = String(line[line.index(after: colon)...])
        let parts = splitUnquoted(head, separator: ";")
        guard let name = parts.first, !name.isEmpty else { return nil }

        var params: [String: String] = [:]
        for part in parts.dropFirst() {
            guard let eq = part.firstIndex(of: "=") else { continue }
            let key = String(part[part.startIndex..<eq]).uppercased()
            var v = String(part[part.index(after: eq)...])
            if v.hasPrefix("\""), v.hasSuffix("\""), v.count >= 2 { v = String(v.dropFirst().dropLast()) }
            params[key] = v
        }
        return Property(name: name.uppercased(), params: params, value: value)
    }

    private static func firstUnquotedIndex(of target: Character, in s: String) -> String.Index? {
        var inQuotes = false
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "\"" { inQuotes.toggle() }
            else if c == target, !inQuotes { return i }
            i = s.index(after: i)
        }
        return nil
    }

    private static func splitUnquoted(_ s: Substring, separator: Character) -> [Substring] {
        var parts: [Substring] = []
        var inQuotes = false
        var start = s.startIndex
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "\"" { inQuotes.toggle() }
            else if c == separator, !inQuotes {
                parts.append(s[start..<i])
                start = s.index(after: i)
            }
            i = s.index(after: i)
        }
        parts.append(s[start...])
        return parts
    }

    /// Unescapes iCalendar TEXT values: `\n`/`\N` -> newline, `\,` -> comma, `\;` -> semicolon, `\\` -> backslash.
    static func unescapeText(_ s: String) -> String {
        var result = ""
        result.reserveCapacity(s.count)
        var chars = s[s.startIndex...]
        while let c = chars.first {
            chars.removeFirst()
            if c == "\\", let n = chars.first {
                chars.removeFirst()
                switch n {
                case "n", "N": result.append("\n")
                default: result.append(n)   // covers `,` `;` `\` and anything else per the "or itself" fallback
                }
            } else {
                result.append(c)
            }
        }
        return result
    }

    // MARK: VEVENT assembly

    private static func buildEvent(_ props: [Property]) -> ICSEvent? {
        var uid: String?, summary = "", location = "", description = ""
        var url: URL?
        var start: Date?, end: Date?
        var isAllDay = false
        var timeZone = TimeZone.current
        var duration: Double?
        var rrule: ICSRecurrenceRule?
        var exdates: Set<Date> = []
        var cancelled = false

        for p in props {
            switch p.name {
            case "UID": uid = unescapeText(p.value)
            case "SUMMARY": summary = unescapeText(p.value)
            case "LOCATION": location = unescapeText(p.value)
            case "DESCRIPTION": description = unescapeText(p.value)
            case "URL": url = URL(string: p.value.trimmingCharacters(in: .whitespaces))
            case "STATUS": cancelled = p.value.uppercased() == "CANCELLED"
            case "DTSTART":
                if let r = parseDateTimeProperty(p.value, params: p.params) { start = r.date; isAllDay = r.isAllDay; timeZone = r.timeZone }
            case "DTEND":
                if let r = parseDateTimeProperty(p.value, params: p.params) { end = r.date }
            case "DURATION":
                duration = parseISO8601Duration(p.value)
            case "RRULE":
                rrule = parseRRule(p.value)
            case "EXDATE":
                for token in p.value.split(separator: ",") {
                    if let r = parseDateTimeProperty(String(token), params: p.params) { exdates.insert(r.date) }
                }
            default: break
            }
        }
        guard !cancelled, let uid, let start else { return nil }

        let resolvedEnd: Date
        if let end { resolvedEnd = end }
        else if let duration { resolvedEnd = start.addingTimeInterval(duration) }
        else if isAllDay { resolvedEnd = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400) }
        else { resolvedEnd = start.addingTimeInterval(3600) }   // DTSTART with no end/duration: treat as a 1-hour event

        return ICSEvent(uid: uid, summary: summary, start: start, end: resolvedEnd, isAllDay: isAllDay,
                        location: location, description: description, url: url, timeZone: timeZone,
                        recurrence: rrule, exceptionDates: exdates)
    }

    // MARK: DTSTART/DTEND/EXDATE values

    /// Parses a DATE ("20240115") or DATE-TIME ("20240115T090000", optionally "Z"-suffixed) value,
    /// honoring a `TZID` parameter. All-day dates are anchored to local midnight (`RFC3339.parseDay`),
    /// matching how the rest of the app represents all-day events.
    static func parseDateTimeProperty(_ raw: String, params: [String: String]) -> (date: Date, isAllDay: Bool, timeZone: TimeZone)? {
        let v = raw.trimmingCharacters(in: .whitespaces)
        if params["VALUE"] == "DATE" || (v.count == 8 && !v.contains("T")) {
            guard v.count == 8, let y = Int(v.prefix(4)), let m = Int(v.dropFirst(4).prefix(2)), let d = Int(v.dropFirst(6).prefix(2)) else { return nil }
            guard let date = RFC3339.parseDay(String(format: "%04d-%02d-%02d", y, m, d)) else { return nil }
            return (date, true, .current)
        }

        let isUTC = v.hasSuffix("Z")
        let core = isUTC ? String(v.dropLast()) : v
        let parts = core.split(separator: "T")
        guard parts.count == 2, parts[0].count == 8, parts[1].count >= 6 else { return nil }
        let datePart = parts[0], timePart = parts[1]
        guard let y = Int(datePart.prefix(4)), let mo = Int(datePart.dropFirst(4).prefix(2)), let d = Int(datePart.dropFirst(6).prefix(2)),
              let hh = Int(timePart.prefix(2)), let mm = Int(timePart.dropFirst(2).prefix(2)), let ss = Int(timePart.dropFirst(4).prefix(2))
        else { return nil }

        let tz: TimeZone
        if isUTC { tz = TimeZone(identifier: "UTC")! }
        else if let tzid = params["TZID"], let named = TimeZone(identifier: tzid) { tz = named }
        else { tz = .current }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        var comps = DateComponents()
        comps.year = y; comps.month = mo; comps.day = d; comps.hour = hh; comps.minute = mm; comps.second = ss
        guard let date = cal.date(from: comps) else { return nil }
        return (date, false, tz)
    }

    private static func parseRRule(_ value: String) -> ICSRecurrenceRule? {
        var freq: ICSRecurrenceRule.Frequency?
        var interval = 1, count: Int?
        var until: Date?
        var byDay: [ICSRecurrenceRule.Weekday] = []

        for pair in value.split(separator: ";") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            switch kv[0].uppercased() {
            case "FREQ": freq = ICSRecurrenceRule.Frequency(rawValue: kv[1].uppercased())
            case "INTERVAL": interval = Int(kv[1]) ?? 1
            case "COUNT": count = Int(kv[1])
            case "UNTIL": until = parseDateTimeProperty(String(kv[1]), params: [:])?.date
            case "BYDAY":
                byDay = kv[1].split(separator: ",").compactMap { token in
                    let s = String(token)
                    guard s.count >= 2 else { return nil }
                    let code = String(s.suffix(2))
                    guard let wd = weekdayNumber(code) else { return nil }
                    let ordinalText = s.dropLast(2)
                    return ICSRecurrenceRule.Weekday(ordinal: ordinalText.isEmpty ? nil : Int(ordinalText), weekday: wd)
                }
            default: break
            }
        }
        guard let f = freq else { return nil }
        return ICSRecurrenceRule(frequency: f, interval: max(interval, 1), count: count, until: until, byDay: byDay)
    }

    private static func weekdayNumber(_ code: String) -> Int? {
        switch code {
        case "MO": return 1; case "TU": return 2; case "WE": return 3; case "TH": return 4
        case "FR": return 5; case "SA": return 6; case "SU": return 7
        default: return nil
        }
    }

    /// Minimal ISO 8601 duration parser ("PT1H30M", "P1D", …) for the rare feed that uses DURATION
    /// instead of DTEND.
    private static func parseISO8601Duration(_ s: String) -> Double? {
        var s = Substring(s)
        var negative = false
        if s.hasPrefix("-") { negative = true; s = s.dropFirst() }
        guard s.hasPrefix("P") else { return nil }
        s = s.dropFirst()

        var seconds = 0.0, timePart = false, numberBuf = ""
        for c in s {
            if c == "T" { timePart = true; continue }
            if c.isNumber { numberBuf.append(c); continue }
            let n = Double(numberBuf) ?? 0
            numberBuf = ""
            switch c {
            case "W": seconds += n * 7 * 86400
            case "D": seconds += n * 86400
            case "H": seconds += n * 3600
            case "M": seconds += timePart ? n * 60 : n * 30 * 86400
            case "S": seconds += n
            default: break
            }
        }
        return negative ? -seconds : seconds
    }
}
