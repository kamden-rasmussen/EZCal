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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

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
                    .keyboardShortcut("j", modifiers: [])
                    Button("Copy link") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    if event.meetingProvider == .zoom && event.canEdit {
                        Button("Remove") { confirmRemoveZoom = true }.buttonStyle(SecondaryButtonStyle())
                    }
                }
            } else if event.canEdit && !event.isAllDay {
                Button {
                    busy = true
                    Task { await store.attachZoom(to: event); busy = false }
                } label: {
                    HStack(spacing: 8) { Image(systemName: "video.badge.plus"); Text("Add Zoom meeting"); KeyCap("Z") }
                }
                .buttonStyle(SecondaryButtonStyle())
                .keyboardShortcut("z", modifiers: [])
                .disabled(!store.zoomConnected || busy)
                .help(store.zoomConnected ? "Create a Zoom meeting and attach it (Z)" : "Connect Zoom in Settings first")
            }

            if !event.location.isEmpty && event.location != event.meetingURL?.absoluteString {
                info("mappin.and.ellipse") { Text(event.location).textSelection(.enabled) }
            }

            let notes = event.notes.strippingHTML
            if !notes.isEmpty {
                info("text.alignleft") {
                    ScrollView { Text(notes).font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                        .frame(maxHeight: 130)
                }
            }

            let people = event.attendees.filter { !$0.isResource }
            if !people.isEmpty {
                info("person.2") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(people.count) \(people.count == 1 ? "guest" : "guests")").font(.system(size: 13, weight: .semibold))
                        ScrollView {
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
                        .frame(maxHeight: 100)
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

            Rectangle().fill(Theme.line).frame(height: 1)
            HStack {
                if let link = event.htmlLink { Link("Open in Google Calendar", destination: link).font(.system(size: 12)) }
                Spacer()
                if event.canEdit {
                    Button { confirmDelete = true } label: { HStack(spacing: 6) { Text("Delete"); KeyCap("⌫") } }
                        .buttonStyle(SecondaryButtonStyle()).keyboardShortcut(.delete, modifiers: [])
                    Button { store.editDraft(event) } label: { HStack(spacing: 6) { Text("Edit"); Text("E").font(.system(size: 11)).opacity(0.7) } }
                        .buttonStyle(PrimaryButtonStyle()).keyboardShortcut("e", modifiers: [])
                }
            }
        }
        .padding(22)
        .frame(width: 460)
        .background(Theme.surface)
        .background { ShortcutProxy(key: .return) { if let u = event.meetingURL { NSWorkspace.shared.open(u) } else if event.canEdit { store.editDraft(event) } } }
        .confirmationDialog("Delete “\(event.title)”?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { Task { await store.delete(event) } }
        } message: {
            Text(event.isRecurring ? "Only this occurrence will be deleted." : "This can't be undone.")
        }
        .confirmationDialog("Remove the Zoom meeting?", isPresented: $confirmRemoveZoom) {
            Button("Remove", role: .destructive) { Task { await store.removeZoom(from: event) } }
        } message: {
            Text("This deletes the Zoom meeting and removes its link from the event.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 3).fill(event.color).frame(width: 12, height: 12).padding(.top, 7)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.isBusyOnly ? "\(event.ownerName ?? "Busy") is busy" : event.title)
                    .font(.system(size: 20, weight: .semibold)).textSelection(.enabled)
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
        .keyboardShortcut(key, modifiers: [])
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
