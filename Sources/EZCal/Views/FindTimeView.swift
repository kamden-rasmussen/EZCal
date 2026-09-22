import SwiftUI

/// "Find a time" panel (issue #4): given attendees, a duration and a date range, lists the best
/// slots where everyone with known availability is free, plus a compact per-day availability grid.
///
/// Two ways in:
/// - From the editor (`EventEditorView`), presented locally with the current guests + duration;
///   picking a slot fills the open draft's start/end.
/// - From the ⌘K palette (`ActiveSheet.findTime`), presented standalone with no attendees yet;
///   picking a slot opens a new event draft seeded with the chosen people and time.
///
/// Working hours are an injectable parameter (`WorkingHours`, default `AppSettings.workingHours` —
/// see Settings → Hours & zones) so a caller can override the search window without this view changing.
struct FindTimeView: View {
    @Environment(CalendarStore.self) private var store

    private let accountId: String?
    private let editableAttendees: Bool
    private let excludingEventId: String?
    private let workingHours: WorkingHours
    private let onPick: (Date, Date, [Attendee]) -> Void
    private let onClose: () -> Void

    @State private var attendees: [Attendee]
    @State private var attendeeQuery = ""
    @State private var suggestions: [DirectoryPerson] = []
    @State private var durationMinutes: Int
    @State private var startDay: Date
    @State private var dayCount: Int
    @State private var busy: [String: [Range<Date>]?] = [:]
    @State private var loading = false
    @State private var selected = 0
    @FocusState private var slotsFocused: Bool
    @FocusState private var queryFocused: Bool

    private let cal = Calendar.current

    init(initialAttendees: [Attendee],
         initialDuration: TimeInterval,
         accountId: String?,
         editableAttendees: Bool,
         excludingEventId: String? = nil,
         workingHours: WorkingHours = AppSettings.workingHours,
         onPick: @escaping (Date, Date, [Attendee]) -> Void,
         onClose: @escaping () -> Void) {
        self.accountId = accountId
        self.editableAttendees = editableAttendees
        self.excludingEventId = excludingEventId
        self.workingHours = workingHours
        self.onPick = onPick
        self.onClose = onClose
        _attendees = State(initialValue: initialAttendees)
        _durationMinutes = State(initialValue: max(15, Int((initialDuration / 60).rounded())))
        _startDay = State(initialValue: Calendar.current.startOfDay(for: Date()))
        _dayCount = State(initialValue: 5)
    }

    private var days: [Date] {
        (0..<dayCount).map { cal.date(byAdding: .day, value: $0, to: startDay)! }
    }

    private var duration: TimeInterval { TimeInterval(durationMinutes * 60) }

    private var window: Range<Date> {
        let lo = startDay
        let hi = cal.date(byAdding: .day, value: dayCount, to: startDay) ?? startDay.addingTimeInterval(Double(dayCount) * 86400)
        return lo..<hi
    }

    private var slots: [TimeSlot] {
        SlotFinder.findSlots(
            emails: attendees.map(\.email), busy: busy,
            myBusy: store.myBusy(in: window, excluding: excludingEventId),
            duration: duration, days: days, workingHours: workingHours, calendar: cal
        )
    }

    private var slotsByDay: [(day: Date, rows: [(index: Int, slot: TimeSlot)])] {
        let all = Array(slots.enumerated())
        var order: [Date] = []
        var map: [Date: [(Int, TimeSlot)]] = [:]
        for (i, s) in all {
            let d = cal.startOfDay(for: s.start)
            if map[d] == nil { order.append(d) }
            map[d, default: []].append((i, s))
        }
        return order.map { d in (d, map[d]!.map { (index: $0.0, slot: $0.1) }) }
    }

    /// The day the grid preview shows: the day of the highlighted slot, else the search start day.
    private var gridDay: Date {
        slots.indices.contains(selected) ? cal.startOfDay(for: slots[selected].start) : startDay
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            divider
            controls
            divider
            if slots.isEmpty {
                emptyState
            } else {
                HSplitView {
                    slotList.frame(minWidth: 260, idealWidth: 280)
                    dayPreview.frame(minWidth: 360)
                }
            }
            divider
            footer
        }
        .frame(width: 780, height: 560)
        .background(Theme.surface)
        .onAppear { slotsFocused = true }
        .task(id: attendeeQuery) {
            guard editableAttendees, attendeeQuery.count >= 2 else { suggestions = []; return }
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            let have = Set(attendees.map { $0.email.lowercased() })
            suggestions = await store.searchDirectory(attendeeQuery).filter { !have.contains($0.email.lowercased()) }
        }
        .task(id: fetchKey) {
            let emails = attendees.map(\.email)
            guard !emails.isEmpty else { busy = [:]; return }
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            loading = true
            busy = await store.busyRanges(emails: emails, window: window, accountId: accountId)
            loading = false
        }
        .onChange(of: slots.count) { _, _ in selected = 0 }
    }

    private var fetchKey: String {
        attendees.map(\.email).joined(separator: ",") + "\(startDay.timeIntervalSince1970)\(dayCount)"
    }

    private var divider: some View { Rectangle().fill(Theme.line).frame(height: 1) }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Find a time").font(.system(size: 18, weight: .semibold))
                Text("Everyone's calendar overlaid — pick a slot where the people you can see are free.")
                    .font(.system(size: 12)).foregroundStyle(Theme.text2)
            }
            Spacer()
            Button { onClose() } label: { HStack(spacing: 6) { Text("Close"); KeyCap("esc") } }
                .buttonStyle(SecondaryButtonStyle()).keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 14)
    }

    // MARK: Controls (attendees, duration, date range)

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                FlowLayout(spacing: 6) {
                    ForEach(attendees, id: \.email) { a in attendeeChip(a) }
                }
                if editableAttendees {
                    TextField("Add people…", text: $attendeeQuery)
                        .textFieldStyle(.plain).frame(minWidth: 140)
                        .focused($queryFocused)
                        .onSubmit { addFromQuery() }
                        .accessibilityLabel("Add people by name or email")
                }
            }
            if editableAttendees, !suggestions.isEmpty {
                HStack(spacing: 6) {
                    ForEach(suggestions.prefix(4)) { p in
                        Button { add(email: p.email, name: p.name) } label: { Text(p.name) }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
            HStack(spacing: 18) {
                HStack(spacing: 6) {
                    Text("Duration").foregroundStyle(Theme.text2)
                    Stepper(value: $durationMinutes, in: 15...240, step: 15) { Text(durationText) }
                        .fixedSize()
                }
                HStack(spacing: 6) {
                    Text("From").foregroundStyle(Theme.text2)
                    DatePicker("", selection: $startDay, displayedComponents: .date)
                        .labelsHidden().datePickerStyle(.compact)
                        .onChange(of: startDay) { _, new in startDay = cal.startOfDay(for: new) }
                }
                HStack(spacing: 6) {
                    Stepper(value: $dayCount, in: 1...14) { Text("\(dayCount) day\(dayCount == 1 ? "" : "s")") }
                        .fixedSize()
                }
                if loading { ProgressView().controlSize(.small) }
                Spacer()
            }
            .font(.system(size: 13))
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private var durationText: String {
        if durationMinutes < 60 { return "\(durationMinutes) min" }
        let h = durationMinutes / 60, r = durationMinutes % 60
        return r == 0 ? "\(h) hr" : "\(h) hr \(r) min"
    }

    private func attendeeChip(_ a: Attendee) -> some View {
        HStack(spacing: 6) {
            Text(String(a.display.prefix(1)).uppercased())
                .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                .frame(width: 18, height: 18).background(Circle().fill(color(for: a)))
            Text(a.display).font(.system(size: 12))
            if editableAttendees {
                Button { attendees.removeAll { $0.email == a.email } } label: {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.text3)
                }
                .buttonStyle(.plain).accessibilityLabel("Remove \(a.display)")
            }
        }
        .padding(.leading, 3).padding(.trailing, 7).frame(height: 24)
        .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
    }

    private func color(for a: Attendee) -> Color {
        let sum = a.email.lowercased().unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return Color(hex: Palette.people[sum % Palette.people.count])
    }

    private func addFromQuery() {
        if let first = suggestions.first { add(email: first.email, name: first.name) }
        else if attendeeQuery.contains("@") { add(email: attendeeQuery.trimmingCharacters(in: .whitespaces), name: nil) }
    }

    private func add(email: String, name: String?) {
        let e = email.lowercased()
        guard !attendees.contains(where: { $0.email.lowercased() == e }) else { return }
        attendees.append(Attendee(email: e, name: name))
        attendeeQuery = ""; suggestions = []
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Text(attendees.isEmpty ? "Add people to check their availability." : "No shared free slot in this range.")
                .font(.system(size: 13)).foregroundStyle(Theme.text2)
            if !attendees.isEmpty { Text("Try a longer date range or a shorter duration.").font(.system(size: 12)).foregroundStyle(Theme.text3) }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Slot list (keyboard: ↑/↓ move, ↩ pick)

    private var slotList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(slotsByDay, id: \.day) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            SectionLabel(group.day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                                .padding(.horizontal, 12).padding(.top, 4)
                            ForEach(group.rows, id: \.index) { row in
                                slotRow(row.slot, isSelected: row.index == selected)
                                    .id(row.index)
                                    .onTapGesture { pick(row.index) }
                            }
                        }
                    }
                }
                .padding(.vertical, 10)
            }
            .onChange(of: selected) { _, new in proxy.scrollTo(new) }
        }
        .focusable()
        .focused($slotsFocused)
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.return) { pick(selected); return .handled }
        .background(Theme.bg)
    }

    private func slotRow(_ slot: TimeSlot, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Text("\(slot.start.formatted(date: .omitted, time: .shortened)) – \(slot.end.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 13, weight: .medium))
            Spacer()
            if slot.unknownCount > 0 {
                Text("\(slot.unknownCount) unknown").font(.system(size: 11)).foregroundStyle(Theme.text3)
            }
        }
        .padding(.horizontal, 12).frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 7).fill(isSelected ? Theme.selection : .clear))
        .contentShape(Rectangle())
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func move(_ delta: Int) {
        guard !slots.isEmpty else { return }
        selected = min(max(selected + delta, 0), slots.count - 1)
    }

    private func pick(_ index: Int) {
        guard slots.indices.contains(index) else { return }
        let s = slots[index]
        onPick(s.start, s.end, attendees)
    }

    // MARK: Day preview grid

    private var dayPreview: some View {
        let hours = Array(workingHours.startHour..<workingHours.endHour)
        let dayStart = cal.date(bySettingHour: workingHours.startHour, minute: 0, second: 0, of: gridDay) ?? gridDay
        let dayEnd = cal.date(bySettingHour: workingHours.endHour, minute: 0, second: 0, of: gridDay) ?? gridDay
        let total = dayEnd.timeIntervalSince(dayStart)
        func frac(_ d: Date) -> CGFloat { total > 0 ? CGFloat(d.timeIntervalSince(dayStart) / total) : 0 }

        var rows: [(String, Color, [Range<Date>])] = [
            ("You", Theme.accent, store.myBusy(in: dayStart..<dayEnd, excluding: excludingEventId)),
        ]
        var unknownRows: Set<String> = []
        for a in attendees {
            guard let entry = busy[a.email] else { unknownRows.insert(a.email); rows.append((a.display, color(for: a), [])); continue }
            guard let ranges = entry else { unknownRows.insert(a.email); rows.append((a.display, color(for: a), [])); continue }
            let clipped = ranges.compactMap { r -> Range<Date>? in
                let lo = max(r.lowerBound, dayStart), hi = min(r.upperBound, dayEnd)
                return lo < hi ? lo..<hi : nil
            }
            rows.append((a.display, color(for: a), clipped))
        }

        return VStack(alignment: .leading, spacing: 8) {
            Text(gridDay.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text2)
                .padding(.horizontal, 16).padding(.top, 12)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 0) {
                    Color.clear.frame(width: 84, height: 1)
                    ForEach(hours, id: \.self) { h in
                        Text(cal.date(bySettingHour: h, minute: 0, second: 0, of: gridDay)!.formatted(.dateTime.hour()).replacingOccurrences(of: " ", with: ""))
                            .font(.system(size: 10).monospacedDigit()).foregroundStyle(Theme.text3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                    HStack(spacing: 6) {
                        Text(r.0).font(.system(size: 11)).foregroundStyle(Theme.text2).lineLimit(1)
                            .frame(width: 78, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .topLeading) {
                                RoundedRectangle(cornerRadius: 4).fill(Theme.hover)
                                if unknownRows.contains(attendees.first { $0.display == r.0 }?.email ?? "") {
                                    Text("unknown").font(.system(size: 9)).foregroundStyle(Theme.text3)
                                        .frame(maxWidth: .infinity, alignment: .center).frame(height: 16)
                                } else {
                                    ForEach(Array(r.2.enumerated()), id: \.offset) { _, range in
                                        Hatch(color: r.1)
                                            .frame(width: max(2, geo.size.width * (frac(range.upperBound) - frac(range.lowerBound))), height: 16)
                                            .offset(x: geo.size.width * frac(range.lowerBound))
                                    }
                                }
                                if slots.indices.contains(selected) {
                                    let s = max(slots[selected].start, dayStart), e = min(slots[selected].end, dayEnd)
                                    if s < e, cal.isDate(s, inSameDayAs: gridDay) {
                                        RoundedRectangle(cornerRadius: 4)
                                            .strokeBorder(Theme.accent, lineWidth: 2)
                                            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.accent.opacity(0.12)))
                                            .frame(width: max(4, geo.size.width * (frac(e) - frac(s))), height: 16)
                                            .offset(x: geo.size.width * frac(s))
                                    }
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .frame(height: 16)
                    }
                }
            }
            .padding(.horizontal, 16)
            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
        .background(Theme.surface)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Text("↑↓ move · ↩ pick a slot").font(.system(size: 12)).foregroundStyle(Theme.text3)
            Spacer()
            Button {
                pick(selected)
            } label: {
                HStack(spacing: 8) { Text("Use this time"); Text("⏎").font(.system(size: 11)).opacity(0.75) }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(slots.isEmpty)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }
}
