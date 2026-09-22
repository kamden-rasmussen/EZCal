import Foundation

/// Pure parser for the "task:" quick-add prefix in the command palette, e.g. "task: call dentist tomorrow 3pm".
/// No EventKit, no store — this only turns text into a title + optional due date, which is what makes it
/// straightforward to unit test. It reuses `NSDataDetector` the same way `CalendarStore.parseDate` does, so it
/// understands the same phrases ("tomorrow", "next friday", "sep 30 3pm", …).
enum TaskQuickAdd {
    struct Parsed: Equatable {
        var title: String
        var due: Date?
        /// Whether the matched date phrase included a specific time ("3pm", "15:00") rather than just a day.
        var hasTime: Bool
    }

    /// Returns nil when `raw` doesn't start with "task:" (case-insensitive), so callers can tell
    /// "not a quick-add" apart from "a quick-add with no due date".
    static func parse(_ raw: String) -> Parsed? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard let prefixRange = trimmed.range(of: "^task:\\s*", options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let rest = String(trimmed[prefixRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return Parsed(title: "", due: nil, hasTime: false) }

        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return Parsed(title: rest, due: nil, hasTime: false)
        }
        let ns = rest as NSString
        guard let match = detector.firstMatch(in: rest, range: NSRange(location: 0, length: ns.length)),
              let due = match.date else {
            return Parsed(title: rest, due: nil, hasTime: false)
        }

        // Title is whatever's left after removing the matched date phrase, whitespace collapsed.
        var title = ns.replacingCharacters(in: match.range, with: " ")
        title = title.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else {
            // The whole text was a date phrase ("task: tomorrow 3pm") — keep it as the title rather than lose it.
            return Parsed(title: rest, due: nil, hasTime: false)
        }

        let matchedText = ns.substring(with: match.range).lowercased()
        let hasTime = matchedText.range(of: #"\d\s*(am|pm)|\d{1,2}:\d{2}|noon|midnight"#, options: .regularExpression) != nil
        return Parsed(title: title, due: due, hasTime: hasTime)
    }
}
