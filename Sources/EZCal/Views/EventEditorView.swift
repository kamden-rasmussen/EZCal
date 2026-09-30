import SwiftUI

struct EventEditorView: View {
    @Environment(CalendarStore.self) private var store
    @State var draft: EventDraft
    @State private var saving = false
    @State private var error: String?
    @State private var attendeeQuery = ""
    @State private var suggestions: [DirectoryPerson] = []
    @State private var busy: [String: [Range<Date>]?] = [:]
    @State private var showFindTime = false
    @State private var confirmRemoveZoom = false
    @FocusState private var titleFocused: Bool

    init(draft: EventDraft) { _draft = State(initialValue: draft) }

    private var isNew: Bool { draft.existing == nil }
    private var accountId: String? {
        draft.existing?.accountId ?? store.calendars.first { $0.id == draft.sourceId }?.accountId
    }
    private var source: Source? { store.calendars.first { $0.id == (draft.existing?.sourceId ?? draft.sourceId) } }
    private var isEK: Bool { draft.existing?.isEventKit ?? (source?.isEventKit ?? false) }
    /// Editing someone else's event: only the guest list can change, so the rest is hidden.
    private var guestsOnly: Bool { draft.existing?.isGuestInviteOnly == true }
    private var hasMeeting: Bool { draft.existing?.meetingURL != nil }
    private var guests: [Attendee] { draft.attendees.filter { !$0.isSelf && !$0.isResource } }
    private var cal: Calendar { Calendar.current }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    titleBlock
                    divider
                    if guestsOnly {
                        peopleBlock
                    } else {
                        whenBlock
                        if isNew { divider; recurrenceBlock }
                        if !isEK { peopleBlock }
                        divider
                        videoBlock
                        divider
                        detailsBlock
                    }
                }
            }
            .scrollIndicators(.hidden)

            if let error {
                Text(error).font(.system(size: 12)).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.bottom, 6)
            }
            divider
            footer
        }
        .frame(width: 560, height: 680)
        .background(Theme.surface)
        .onAppear { titleFocused = true }
        .onChange(of: draft.sourceId) { _, _ in
            if isEK && draft.video == .meet { draft.video = .none }
        }
        .onChange(of: draft.start) { old, new in
            draft.end = draft.end.addingTimeInterval(new.timeIntervalSince(old))
        }
        .task(id: attendeeQuery) {
            guard attendeeQuery.count >= 2 else { suggestions = []; return }
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            let have = Set(draft.attendees.map { $0.email.lowercased() })
            suggestions = await store.searchDirectory(attendeeQuery).filter { !have.contains($0.email.lowercased()) }
        }
        .task(id: availabilityKey) {
            let emails = guests.map(\.email)
            guard !emails.isEmpty, !draft.isAllDay else { busy = [:]; return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            busy = await store.busyRanges(emails: emails, window: window, accountId: accountId)
        }
        .sheet(isPresented: $showFindTime) {
            FindTimeView(
                initialAttendees: guests, initialDuration: draft.end.timeIntervalSince(draft.start),
                accountId: accountId, editableAttendees: false, excludingEventId: draft.existing?.eventId,
                onPick: { start, end, _ in draft.start = start; draft.end = end; showFindTime = false },
                onClose: { showFindTime = false }
            )
        }
        .confirmationDialog("Remove the Zoom meeting?", isPresented: $confirmRemoveZoom) {
            Button("Remove", role: .destructive) { if let e = draft.existing { Task { await store.removeZoom(from: e) } } }
        } message: {
            Text("This deletes the Zoom meeting and removes its link from the event.")
        }
    }

    private var divider: some View { Rectangle().fill(Theme.line).frame(height: 1) }

    // MARK: Sections

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            if guestsOnly {
                Text(draft.title).font(.system(size: 22, weight: .semibold))
                Text("You're a guest on this event, so you can add people but not change its details.")
                    .font(.system(size: 12)).foregroundStyle(Theme.text3)
            } else {
                TextField("New event", text: $draft.title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .semibold))
                    .focused($titleFocused)
                    .onSubmit { submit() }
            }
            calendarChip
        }
        .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 14)
    }

    @ViewBuilder private var calendarChip: some View {
        if isNew {
            Menu {
                ForEach(store.calendars.filter(\.canWrite)) { s in
                    Button { draft.sourceId = s.id } label: {
                        Text(s.isEventKit ? "\(s.name) — \(s.groupTitle)" : s.name)
                    }
                }
            } label: { chip(source) }
            .buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("Calendar: \(source?.name ?? "none")")
        } else {
            chip(source)
        }
    }

    private func chip(_ s: Source?) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3).fill(s?.color ?? Theme.text3).frame(width: 10, height: 10)
            Text(s.map { $0.isEventKit ? "\($0.name) · \($0.groupTitle)" : $0.name } ?? draft.existing?.sourceName ?? "Calendar")
                .font(.system(size: 13, weight: .medium))
            if isNew { Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.text3) }
        }
        .padding(.horizontal, 10).frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.hover))
    }

    private var whenBlock: some View {
        row("clock") {
            HStack(spacing: 8) {
                DatePicker("Start date", selection: $draft.start, displayedComponents: .date)
                    .labelsHidden().datePickerStyle(.compact)
                if draft.isAllDay {
                    Text("→").foregroundStyle(Theme.text3)
                    DatePicker("End date", selection: $draft.end, in: draft.start..., displayedComponents: .date)
                        .labelsHidden().datePickerStyle(.compact)
                } else {
                    DatePicker("Start time", selection: $draft.start, displayedComponents: .hourAndMinute)
                        .labelsHidden().datePickerStyle(.compact)
                    Text("→").foregroundStyle(Theme.text3)
                    if cal.isDate(draft.start, inSameDayAs: draft.end) {
                        DatePicker("End time", selection: endTime, displayedComponents: .hourAndMinute)
                            .labelsHidden().datePickerStyle(.compact)
                    } else {
                        DatePicker("End", selection: $draft.end, in: draft.start..., displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden().datePickerStyle(.compact)
                    }
                    Text(durationText).font(.system(size: 12)).foregroundStyle(Theme.text3)
                }
                Spacer(minLength: 0)
                allDayToggle
            }
        }
        .padding(.vertical, 14)
    }

    /// "Nice to have" from issue #3: set a recurrence when creating an event. Editing an existing
    /// recurring event's own pattern is out of scope; that's handled via RecurrenceScopeView instead.
    private var recurrenceBlock: some View {
        row("repeat") {
            Picker("Repeat", selection: $draft.recurrence) {
                ForEach(RecurrenceOption.allCases) { opt in Text(opt.label).tag(opt) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 170)
            .accessibilityLabel("Repeat")
        }
        .padding(.vertical, 14)
    }

    private var allDayToggle: some View {
        Button { draft.isAllDay.toggle() } label: {
            HStack(spacing: 8) {
                Text("All-day").foregroundStyle(Theme.text2)
                Capsule().fill(draft.isAllDay ? Theme.accent : Theme.line)
                    .frame(width: 30, height: 18)
                    .overlay(alignment: draft.isAllDay ? .trailing : .leading) {
                        Circle().fill(Theme.surface).frame(width: 14, height: 14).padding(2).shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                    }
            }
        }
        .buttonStyle(.plain)
        .keyboardShortcut("a", modifiers: .control)
        .help("All-day (⌃A)")
        .accessibilityLabel("All-day")
        .accessibilityValue(draft.isAllDay ? "on" : "off")
    }

    /// End time-of-day on the start's day; rolls to the next day if it would end before it starts.
    private var endTime: Binding<Date> {
        Binding(get: { draft.end }, set: { new in
            let t = cal.dateComponents([.hour, .minute], from: new)
            var d = cal.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0, second: 0, of: draft.start) ?? new
            if d <= draft.start { d = cal.date(byAdding: .day, value: 1, to: d) ?? d }
            draft.end = d
        })
    }

    private var durationText: String {
        let m = Int(draft.end.timeIntervalSince(draft.start) / 60)
        if m < 60 { return "\(max(m, 0)) min" }
        let h = m / 60, r = m % 60
        return r == 0 ? "\(h) hr" : "\(h) hr \(r) min"
    }

    // MARK: People + availability

    private var peopleBlock: some View {
        row("person.2", top: true) {
            VStack(alignment: .leading, spacing: 10) {
                FlowLayout(spacing: 6) {
                    ForEach(guests, id: \.email) { a in guestChip(a) }
                }
                TextField("Add people…", text: $attendeeQuery)
                    .textFieldStyle(.plain)
                    .onSubmit { addFromQuery() }
                    .accessibilityLabel("Add people by name or email")
                ForEach(suggestions.prefix(5)) { p in
                    Button { add(email: p.email, name: p.name) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(p.name)
                                Text(p.email).font(.system(size: 11)).foregroundStyle(Theme.text3)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                if !draft.isAllDay && !guestsOnly {
                    Button { showFindTime = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar.badge.clock")
                            Text("Find a time")
                            Text("⌘F").font(.system(size: 11)).opacity(0.6)
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut("f", modifiers: .command)
                    .accessibilityLabel("Find a time everyone is free")
                }

                if !guests.isEmpty && !draft.isAllDay {
                    conflictBanner
                    availabilityStrip
                }
            }
        }
        .padding(.bottom, 14)
    }

    private func guestChip(_ a: Attendee) -> some View {
        let known = busy[a.email] != nil
        let isBusy = conflicts.contains { $0.email == a.email }
        let dot: Color = !known ? Theme.text3.opacity(0.5) : (isBusy ? Color.orange : Color.green)
        return HStack(spacing: 7) {
            Text(String(a.display.prefix(1)).uppercased())
                .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                .frame(width: 20, height: 20).background(Circle().fill(color(for: a)))
            Text(a.display).font(.system(size: 13))
            Circle().fill(dot).frame(width: 8, height: 8)
                .help(!known ? "Availability unknown" : (isBusy ? "Busy at this time" : "Free"))
            if !a.isOrganizer && !(guestsOnly && isExistingGuest(a)) {
                Button { draft.attendees.removeAll { $0.email == a.email } } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.text3)
                }
                .buttonStyle(.plain).accessibilityLabel("Remove \(a.display)")
            }
        }
        .padding(.leading, 4).padding(.trailing, 8).frame(height: 28)
        .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
    }

    /// Guests already on the event can't be removed by another guest; ones added in this session can.
    private func isExistingGuest(_ a: Attendee) -> Bool {
        draft.existing?.attendees.contains { $0.email.lowercased() == a.email.lowercased() } == true
    }

    private func color(for a: Attendee) -> Color {
        // Stable across launches (String.hashValue is randomized per process).
        let sum = a.email.lowercased().unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return Color(hex: Palette.people[sum % Palette.people.count])
    }

    private var window: Range<Date> {
        let start = cal.dateInterval(of: .hour, for: draft.start)?.start ?? draft.start
        let lo = cal.date(byAdding: .hour, value: -1, to: start) ?? start
        let hours = max(6, Int(ceil(draft.end.timeIntervalSince(draft.start) / 3600)) + 3)
        return lo..<(cal.date(byAdding: .hour, value: hours, to: lo) ?? lo.addingTimeInterval(6 * 3600))
    }

    private var availabilityKey: String {
        guests.map(\.email).joined(separator: ",") + "\(window.lowerBound.timeIntervalSince1970)\(window.upperBound.timeIntervalSince1970)\(draft.isAllDay)"
    }

    private var conflicts: [Attendee] {
        guests.filter { a in
            guard let ranges = busy[a.email] ?? nil else { return false }
            return ranges.contains { $0.overlaps(draft.start..<draft.end) }
        }
    }

    /// First slot after the current start where everyone we can see is free.
    private var suggestion: Date? {
        guard !conflicts.isEmpty else { return nil }
        let dur = draft.end.timeIntervalSince(draft.start)
        var t = draft.start.addingTimeInterval(15 * 60)
        while t.addingTimeInterval(dur) <= window.upperBound {
            let slot = t..<t.addingTimeInterval(dur)
            let clash = guests.contains { a in ((busy[a.email] ?? nil) ?? []).contains { $0.overlaps(slot) } }
            if !clash { return t }
            t = t.addingTimeInterval(15 * 60)
        }
        return nil
    }

    @ViewBuilder private var conflictBanner: some View {
        if !conflicts.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(conflicts.map(\.display).joined(separator: ", ")) \(conflicts.count == 1 ? "is" : "are") busy at this time.")
                    if let s = suggestion {
                        Button("Move to \(s.formatted(date: .omitted, time: .shortened)), when everyone is free") {
                            let d = draft.end.timeIntervalSince(draft.start)
                            draft.start = s; draft.end = s.addingTimeInterval(d)
                        }
                        .buttonStyle(.plain).underline().fontWeight(.semibold)
                    }
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 12))
            .foregroundStyle(Color.orange.mix(with: Theme.text, 0.35))
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.orange.opacity(0.13)))
        }
    }

    private var availabilityStrip: some View {
        let w = window
        let total = w.upperBound.timeIntervalSince(w.lowerBound)
        let hourCount = Int(total / 3600)
        func frac(_ d: Date) -> CGFloat { CGFloat(d.timeIntervalSince(w.lowerBound) / total) }

        var rows: [(String, Color, [Range<Date>])] = [("You", source?.color ?? Theme.accent, store.myBusy(in: w, excluding: draft.existing?.eventId))]
        for a in guests {
            let ranges = ((busy[a.email] ?? nil) ?? []).compactMap { r -> Range<Date>? in
                let lo = max(r.lowerBound, w.lowerBound), hi = min(r.upperBound, w.upperBound)
                return lo < hi ? lo..<hi : nil
            }
            rows.append((a.display.split(separator: " ").first.map(String.init) ?? a.display, color(for: a), ranges))
        }

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 0) {
                Color.clear.frame(width: 62, height: 1)
                ForEach(0..<hourCount, id: \.self) { i in
                    let d = w.lowerBound.addingTimeInterval(Double(i) * 3600)
                    Text(d.formatted(.dateTime.hour()).replacingOccurrences(of: " ", with: ""))
                        .font(.system(size: 10).monospacedDigit()).foregroundStyle(Theme.text3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                HStack(spacing: 6) {
                    Text(r.0).font(.system(size: 11)).foregroundStyle(Theme.text2).lineLimit(1).frame(width: 56, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 4).fill(Theme.hover)
                            ForEach(Array(r.2.enumerated()), id: \.offset) { _, range in
                                Hatch(color: r.1)
                                    .frame(width: max(2, geo.size.width * (frac(range.upperBound) - frac(range.lowerBound))), height: 16)
                                    .offset(x: geo.size.width * frac(range.lowerBound))
                            }
                            let s = max(draft.start, w.lowerBound), e = min(draft.end, w.upperBound)
                            if s < e {
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(Theme.accent, lineWidth: 2)
                                    .background(RoundedRectangle(cornerRadius: 4).fill(Theme.accent.opacity(0.12)))
                                    .frame(width: max(4, geo.size.width * (frac(e) - frac(s))), height: 16)
                                    .offset(x: geo.size.width * frac(s))
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .frame(height: 16)
                }
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Video + details

    private var videoBlock: some View {
        row("video", top: true) {
            VStack(alignment: .leading, spacing: 8) {
                if hasMeeting, let url = draft.existing?.meetingURL {
                    HStack {
                        Label(draft.existing?.meetingProvider?.name ?? "Meeting", systemImage: "video.fill")
                        Spacer()
                        Button("Copy link") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(url.absoluteString, forType: .string)
                        }.buttonStyle(SecondaryButtonStyle())
                        if draft.existing?.meetingProvider == .zoom {
                            Button("Remove") { confirmRemoveZoom = true }.buttonStyle(SecondaryButtonStyle())
                        }
                    }
                } else {
                    HStack(spacing: 6) {
                        videoButton(.zoom, "Zoom", key: "1")
                        if !isEK { videoButton(.meet, "Google Meet", key: "2") }
                        videoButton(.none, "None", key: "3")
                    }
                    if draft.video == .zoom {
                        if store.zoomConnected {
                            Text("A Zoom meeting is created when you save, and the link is added to the event.")
                                .font(.system(size: 12)).foregroundStyle(Theme.text2)
                            zoomOptionsGrid
                        } else {
                            HStack {
                                Text("Zoom isn't connected yet.").font(.system(size: 12)).foregroundStyle(Theme.text2)
                                Button("Connect Zoom") { Task { await store.connectZoom() } }.buttonStyle(SecondaryButtonStyle())
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 14)
    }

    /// Zoom's Create Meeting `settings` fields; passed through to `ZoomAPI.createMeeting` on save.
    private var zoomOptionsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 4) {
            GridRow {
                zoomToggle("Waiting room", $draft.zoomOptions.waitingRoom)
                zoomToggle("Mute on entry", $draft.zoomOptions.muteOnEntry)
            }
            GridRow {
                zoomToggle("Join before host", $draft.zoomOptions.joinBeforeHost)
                zoomToggle("Require passcode", $draft.zoomOptions.passcodeEnabled)
            }
            GridRow {
                zoomToggle("Host video on", $draft.zoomOptions.hostVideoOn)
                zoomToggle("Participant video on", $draft.zoomOptions.participantVideoOn)
            }
        }
        .padding(.top, 2)
    }

    private func zoomToggle(_ label: String, _ isOn: Binding<Bool>) -> some View {
        Toggle(label, isOn: isOn)
            .toggleStyle(.checkbox)
            .font(.system(size: 12))
            .foregroundStyle(Theme.text2)
    }

    private func videoButton(_ v: EventDraft.Video, _ label: String, key: KeyEquivalent) -> some View {
        let on = draft.video == v
        return Button { draft.video = v } label: {
            HStack(spacing: 7) {
                Text(label)
                Text("⌃\(String(key.character))").font(.system(size: 11)).opacity(0.6)
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(on ? Theme.accentText : Theme.text)
            .padding(.horizontal, 14).frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8).fill(on ? Theme.accent : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? Color.clear : Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key, modifiers: .control)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Google's per-event visibility. EventKit exposes no privacy setting, so the row is hidden for Apple calendars.
    private var visibilityRow: some View {
        row(draft.visibility == .private ? "lock.fill" : "lock.open") {
            Picker("Visibility", selection: $draft.visibility) {
                ForEach(EventVisibility.allCases) { v in Text(v.label).tag(v) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 170)
            .accessibilityLabel("Visibility")
            .help("Private events show only as Busy to people who can see your calendar")
        }
    }

    private var detailsBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !isEK { visibilityRow }
            row("mappin.and.ellipse") {
                TextField("Add location", text: $draft.location).textFieldStyle(.plain)
            }
            row("text.alignleft", top: true) {
                TextField("Add notes", text: $draft.notes, axis: .vertical).textFieldStyle(.plain).lineLimit(3...8)
            }
        }
        .padding(.vertical, 14)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("Tab moves between fields").font(.system(size: 12)).foregroundStyle(Theme.text3)
            Spacer()
            if saving { ProgressView().controlSize(.small) }
            Button { store.sheet = nil } label: {
                HStack(spacing: 8) { Text("Cancel"); KeyCap("esc") }
            }
            .buttonStyle(SecondaryButtonStyle()).keyboardShortcut(.cancelAction)
            Button { submit() } label: {
                HStack(spacing: 8) { Text(isNew ? "Create event" : "Save"); Text("⌘↩").font(.system(size: 11)).opacity(0.75) }
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(saving)
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
    }

    // MARK: Helpers

    private func row<C: View>(_ symbol: String, top: Bool = false, @ViewBuilder content: () -> C) -> some View {
        HStack(alignment: top ? .top : .center, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(Theme.text3)
                .frame(width: 20).padding(.top, top ? 2 : 0).accessibilityHidden(true)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24)
    }

    private func addFromQuery() {
        if let first = suggestions.first { add(email: first.email, name: first.name) }
        else if attendeeQuery.contains("@") { add(email: attendeeQuery.trimmingCharacters(in: .whitespaces), name: nil) }
    }

    private func add(email: String, name: String?) {
        let e = email.lowercased()
        guard !draft.attendees.contains(where: { $0.email.lowercased() == e }) else { return }
        draft.attendees.append(Attendee(email: e, name: name))
        attendeeQuery = ""
        suggestions = []
    }

    private func submit() {
        guard !saving else { return }
        saving = true; error = nil
        Task {
            do { try await store.save(draft) }
            catch {
                self.error = error.localizedDescription
                // Flip the shared flag so this view's (and every other) "Connect Zoom" button becomes reconnect.
                if case APIError.zoomReconnectNeeded = error { store.zoomConnected = false; store.zoomNeedsReconnect = true }
            }
            saving = false
        }
    }
}

// MARK: - Wrapping layout for guest chips

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? 400, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let r = arrange(bounds.width, subviews)
        for (i, f) in r.frames.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), proposal: .unspecified)
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            frames.append(CGRect(x: x, y: y, width: sz.width, height: sz.height))
            x += sz.width + spacing; rowH = max(rowH, sz.height); maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowH), frames)
    }
}

private extension Color {
    /// Blend toward another color (used to keep warning text readable on its tint).
    func mix(with other: Color, _ amount: Double) -> Color {
        Color(nsColor: NSColor(name: nil) { _ in
            let a = NSColor(self).usingColorSpace(.sRGB) ?? .orange
            let b = NSColor(other).usingColorSpace(.sRGB) ?? .black
            return a.blended(withFraction: amount, of: b) ?? a
        })
    }
}
