import SwiftUI

/// Invisible button that lets a key trigger an action without a visible control.
struct ShortcutProxy: View {
    let key: KeyEquivalent
    var modifiers: EventModifiers = []
    let action: () -> Void
    var body: some View {
        Button(action: action) { EmptyView() }
            .keyboardShortcut(key, modifiers: modifiers)
            .frame(width: 0, height: 0).opacity(0).allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct EventDetailView: View {
    @Environment(CalendarStore.self) private var store
    let event: CalEvent
    @State private var confirmDelete = false
    @State private var confirmRemoveZoom = false
    @State private var busy = false
    @State private var guestQuery = ""
    @State private var suggestions: [DirectoryPerson] = []
    @State private var addingGuest = false
    @State private var addError: String?
    /// Typing in the guest field must not trigger the panel's single-key shortcuts (E, J, Z, Y/M/N, ⌫, ↩).
    @FocusState private var guestFieldFocused: Bool
    private var shortcutsOn: Bool { !guestFieldFocused }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 18)

            Rectangle().fill(Theme.line).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let url = event.meetingURL {
                        HStack(spacing: 8) {
                            Button { NSWorkspace.shared.open(url) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "video.fill")
                                    Text("Join \(event.meetingProvider?.name ?? "meeting")")
                                    Text("J").font(.system(size: 11)).opacity(0.7)
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .plainShortcut("j", enabled: shortcutsOn)
                            Button("Copy link") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(url.absoluteString, forType: .string)
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            if event.meetingProvider == .zoom && event.canModify {
                                Button("Remove") { confirmRemoveZoom = true }.buttonStyle(SecondaryButtonStyle())
                            }
                        }
                    } else if event.canModify && !event.isAllDay {
                        Button {
                            busy = true
                            Task { await store.attachZoom(to: event); busy = false }
                        } label: {
                            HStack(spacing: 8) { Image(systemName: "video.badge.plus"); Text("Add Zoom meeting"); KeyCap("Z") }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .plainShortcut("z", enabled: shortcutsOn)
                        .disabled(!store.zoomConnected || busy)
                        .help(store.zoomConnected ? "Create a Zoom meeting and attach it (Z)" : "Connect Zoom in Settings first")
                    }

                    if !event.location.isEmpty && event.location != event.meetingURL?.absoluteString {
                        info("mappin.and.ellipse") { Text(event.location).textSelection(.enabled) }
                    }

                    let notes = event.notes.strippingHTML
                    if !notes.isEmpty {
                        info("text.alignleft") {
                            Text(notes).font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                        }
                    }

                    let people = event.attendees.filter { !$0.isResource }
                    if !people.isEmpty || event.canAddGuests {
                        info("person.2") {
                            VStack(alignment: .leading, spacing: 10) {
                                if !people.isEmpty {
                                Text("\(people.count) \(people.count == 1 ? "guest" : "guests")").font(.system(size: 13, weight: .semibold))
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(people, id: \.email) { a in
                                        HStack(spacing: 7) {
                                            Image(systemName: icon(a.response)).foregroundStyle(color(a.response)).font(.system(size: 12))
                                            Text(a.display + (a.isSelf ? " (you)" : ""))
                                            if a.isOrganizer { Text("organizer").font(.system(size: 11)).foregroundStyle(Theme.text3) }
                                        }
                                        .accessibilityElement(children: .combine)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                }
                                if event.canAddGuests { addGuestField }
                            }
                        }
                    }

                    if event.selfAttendee != nil && !event.isOverlay && !event.isEventKit {
                        HStack(spacing: 8) {
                            Text("Going?").foregroundStyle(Theme.text2)
                            rsvp("Yes", "accepted", "y")
                            rsvp("Maybe", "tentative", "m")
                            rsvp("No", "declined", "n")
                        }
                    }
                }
                .padding(20)
            }

            Rectangle().fill(Theme.line).frame(height: 1)
            HStack {
                if let link = event.htmlLink {
                    Link(event.isICS ? "Open link" : "Open in Google Calendar", destination: link).font(.system(size: 12))
                }
                Spacer()
                if event.canEdit {
                    Button {
                        if event.isRecurring { store.requestDelete(event) } else { confirmDelete = true }
                    } label: { HStack(spacing: 6) { Text("Delete"); KeyCap("⌫") } }
                        .buttonStyle(SecondaryButtonStyle()).plainShortcut(.delete, enabled: shortcutsOn)
                    if event.canModify || event.isGuestInviteOnly {
                    Button { store.requestEdit(event) } label: { HStack(spacing: 6) { Text("Edit"); Text("E").font(.system(size: 11)).opacity(0.7) } }
                        .buttonStyle(PrimaryButtonStyle()).plainShortcut("e", enabled: shortcutsOn)
                    }
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.side)
        .background {
            if shortcutsOn {
                ShortcutProxy(key: .return) { if let u = event.meetingURL { NSWorkspace.shared.open(u) } else if event.canEdit { store.requestEdit(event) } }
            }
        }
        // Recurring events go through RecurrenceScopeView (store.requestDelete) instead of this dialog.
        .confirmationDialog("Delete “\(event.title)”?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { Task { await store.delete(event) } }
        } message: {
            Text("This can't be undone.")
        }
        .confirmationDialog("Remove the Zoom meeting?", isPresented: $confirmRemoveZoom) {
            Button("Remove", role: .destructive) { Task { await store.removeZoom(from: event) } }
        } message: {
            Text("This deletes the Zoom meeting and removes its link from the event.")
        }
    }

    // MARK: Quick add guests

    private var addGuestField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Add people…", text: $guestQuery)
                    .textFieldStyle(.plain)
                    .focused($guestFieldFocused)
                    .disabled(addingGuest)
                    .onSubmit { addFromQuery() }
                    .accessibilityLabel("Add people by name or email")
                if addingGuest { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 10).frame(height: 30)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(guestFieldFocused ? Theme.accent : Theme.line, lineWidth: 1))
            ForEach(suggestions.prefix(5)) { p in
                Button { addGuest(email: p.email, name: p.name) } label: {
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
            if let addError { Text(addError).font(.system(size: 12)).foregroundStyle(.red) }
            else if event.isRecurring && guestFieldFocused {
                Text("Adds to this occurrence only. Use Edit to change the whole series.")
                    .font(.system(size: 11)).foregroundStyle(Theme.text3)
            }
        }
        .task(id: guestQuery) {
            addError = nil
            guard guestQuery.count >= 2 else { suggestions = []; return }
            try? await Task.sleep(nanoseconds: 250_000_000)   // debounce; cancelled when the query changes
            guard !Task.isCancelled else { return }
            let have = Set(event.attendees.map { $0.email.lowercased() })
            let found = await store.searchDirectory(guestQuery).filter { !have.contains($0.email.lowercased()) }
            if !Task.isCancelled { suggestions = found }
        }
    }

    private func addFromQuery() {
        let q = guestQuery.trimmingCharacters(in: .whitespaces)
        if q.contains("@") { addGuest(email: q, name: suggestions.first { $0.email.lowercased() == q.lowercased() }?.name) }
        else if let first = suggestions.first { addGuest(email: first.email, name: first.name) }
    }

    private func addGuest(email: String, name: String?) {
        let e = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard e.contains("@"), !addingGuest else { return }
        addingGuest = true; addError = nil
        Task {
            do {
                try await store.addGuests([Attendee(email: e, name: name)], to: event)
                guestQuery = ""; suggestions = []
            } catch { addError = error.localizedDescription }
            addingGuest = false
            guestFieldFocused = true
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 3).fill(event.color).frame(width: 12, height: 12).padding(.top, 7)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(event.isBusyOnly ? "\(event.ownerName ?? "Busy") is busy" : event.title)
                        .font(.system(size: 20, weight: .semibold)).textSelection(.enabled)
                    if event.isPrivate, !event.isBusyOnly {
                        Image(systemName: "lock.fill").font(.system(size: 13)).foregroundStyle(Theme.text3)
                            .accessibilityLabel("Private").help("Private: others see this only as Busy")
                    }
                    if event.isRecurring {
                        Image(systemName: "repeat").font(.system(size: 13)).foregroundStyle(Theme.text3)
                            .accessibilityLabel("Repeats").help("Recurring event")
                    }
                }
                Text(whenText).foregroundStyle(Theme.text2)
                HStack(spacing: 5) {
                    Image(systemName: event.isOverlay ? "person.fill" : "calendar").font(.system(size: 11))
                    Text(event.ownerName.map { "\($0)'s calendar" } ?? event.sourceName)
                }
                .font(.system(size: 12)).foregroundStyle(Theme.text3)
            }
            Spacer()
            Button { store.sheet = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(IconButtonStyle()).keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close").help("Close (esc)")
        }
    }

    private func info<C: View>(_ symbol: String, @ViewBuilder content: () -> C) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(Theme.text3).frame(width: 20).padding(.top, 1)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func rsvp(_ label: String, _ value: String, _ key: KeyEquivalent) -> some View {
        let on = event.selfAttendee?.response == value
        return Button { Task { await store.rsvp(event, value) } } label: {
            HStack(spacing: 6) { Text(label); Text(String(key.character).uppercased()).font(.system(size: 11)).opacity(0.6) }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(on ? Theme.accentText : Theme.text)
                .padding(.horizontal, 12).frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 8).fill(on ? Theme.accent : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? Color.clear : Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .plainShortcut(key, enabled: shortcutsOn)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var whenText: String {
        let c = Calendar.current
        if event.isAllDay {
            let last = c.date(byAdding: .day, value: -1, to: event.end) ?? event.end
            let f = event.start.formatted(.dateTime.weekday(.wide).month().day())
            return c.isDate(event.start, inSameDayAs: last) ? f : "\(f) – \(last.formatted(.dateTime.month().day()))"
        }
        let day = event.start.formatted(.dateTime.weekday(.wide).month().day())
        let t = "\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))"
        return "\(day) · \(t)"
    }

    private func icon(_ r: String) -> String {
        switch r {
        case "accepted": return "checkmark.circle.fill"
        case "declined": return "xmark.circle.fill"
        case "tentative": return "questionmark.circle.fill"
        default: return "circle.dashed"
        }
    }
    private func color(_ r: String) -> Color {
        switch r {
        case "accepted": return .green
        case "declined": return .red
        case "tentative": return .orange
        default: return Theme.text3
        }
    }
}

private extension View {
    /// A bare-key shortcut that can be switched off, e.g. while a text field has focus.
    @ViewBuilder func plainShortcut(_ key: KeyEquivalent, enabled: Bool) -> some View {
        if enabled { keyboardShortcut(key, modifiers: []) } else { self }
    }
}
