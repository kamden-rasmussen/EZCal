import SwiftUI

struct ContentView: View {
    @Environment(CalendarStore.self) private var store
    // Observed so the grid re-renders when these settings change.
    @AppStorage("showWeekends") private var showWeekends = true
    @AppStorage("firstWeekday") private var firstWeekday = 0
    @State private var lastActivation = Date.distantPast
    @FocusState private var gridFocused: Bool

    var body: some View {
        @Bindable var store = store
        let sidebarShown = store.columnVisibility != .detailOnly
        let detailEvent: CalEvent? = { if case .detail(let e) = store.sheet { return e }; return nil }()

        Group {
            if !store.hasAnyAccount {
                SetupView()
            } else {
                HStack(spacing: 0) {
                    if sidebarShown {
                        SidebarView()
                            .frame(width: 264)
                            .overlay(alignment: .trailing) { Rectangle().fill(Theme.line).frame(width: 1) }
                            .transition(.move(edge: .leading))
                    }
                    VStack(spacing: 0) {
                        TopBar(leadingInset: sidebarShown ? 20 : 84)
                        Divider().overlay(Theme.line)
                        if let msg = store.errorMessage { errorBanner(msg) }
                        // The event panel floats over the calendar (below the toolbar) instead of being docked beside it, so
                        // opening or closing it never resizes or scrolls the grid.
                        ZStack(alignment: .trailing) {
                            Group {
                                switch store.mode {
                                case .day: TimeGridView(days: store.visibleDays)
                                case .workWeek, .week: WeekScrollView()
                                case .month: MonthView()
                                }
                            }
                            .focusable()
                            .focused($gridFocused)
                            .focusEffectDisabled()
                            .onKeyPress(phases: .down) { handle($0) }
                            .background(HorizontalSwipeNavigator(isEnabled: store.mode == .day) { days in
                                guard store.mode != .month, store.sheet == nil, store.deleteRequest == nil, !store.showAddPerson else { return }  // Month scrolls vertically; Week/Work Week pan natively
                                store.stepDay(days)
                            })

                            if let event = detailEvent {
                                EventDetailView(event: event)
                                    .id(event.id)
                                    .frame(width: 420)
                                    .frame(maxHeight: .infinity)
                                    .overlay(alignment: .leading) { Rectangle().fill(Theme.line).frame(width: 1) }
                                    .shadow(color: .black.opacity(0.28), radius: 14, x: -4, y: 0)
                                    .transition(.move(edge: .trailing))
                                    .zIndex(1)   // a view animating out of a ZStack is otherwise drawn under its siblings, so it looks like it just vanishes
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(Theme.bg)
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.18), value: sidebarShown)
        .animation(.easeInOut(duration: 0.2), value: detailEvent?.id)
        .sheet(item: modalSheetBinding) { sheet in
            switch sheet {
            case .detail: EmptyView()   // shown as a docked panel above, not a modal
            case .editor(let d): EventEditorView(draft: d)
            case .palette: PaletteView()
            case .shortcuts: ShortcutsView()
            case .findTime:
                FindTimeView(
                    initialAttendees: [], initialDuration: TimeInterval(AppSettings.defaultDuration * 60),
                    accountId: store.accounts.first?.id, editableAttendees: true,
                    onPick: { start, end, people in
                        store.sheet = nil
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 200_000_000)   // let the sheet finish closing
                            guard let src = store.defaultSource else { return }
                            var d = EventDraft(start: start, end: end, sourceId: src.id)
                            d.attendees = people
                            store.sheet = .editor(d)
                        }
                    },
                    onClose: { store.sheet = nil }
                )
            case .addSubscription: AddICSSubscriptionView()
            case .recurrenceScope(let e, let a): RecurrenceScopeView(event: e, action: a)
            }
        }
        // Recurring events go through RecurrenceScopeView (store.requestDelete) instead of this dialog.
        .overlay {
            if store.showAddPerson {
                AddPersonDialog()
            } else if let e = store.deleteRequest {
                ConfirmDialog(icon: "trash", destructive: true, title: "Delete “\(e.title)”?",
                              message: "This can't be undone.", confirmLabel: "Delete",
                              onConfirm: { store.deleteRequest = nil; Task { await store.delete(e) } },
                              onCancel: { store.deleteRequest = nil })
            } else if let e = store.joinRequest {
                ConfirmDialog(icon: "video", title: "Join “\(e.title)”?",
                              message: "Scheduled for \(e.start.formatted(.dateTime.weekday(.wide).month(.wide).day().hour().minute())).",
                              confirmLabel: "Join",
                              onConfirm: { store.confirmJoin(); store.joinRequest = nil },
                              onCancel: { store.joinRequest = nil })
            }
        }
        .task { await store.bootstrap() }
        .task {
            // Periodic refresh so the calendar stays current while it sits open.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300 * 1_000_000_000)
                await store.refreshAll()
            }
        }
        .onAppear { gridFocused = true }
        .onChange(of: store.sheet?.id) { _, id in if id == nil { gridFocused = true } }
        // The person-picker's search field owns focus while open; hand it back so Esc/P work afterwards.
        .onChange(of: store.showAddPerson) { _, open in if !open { gridFocused = true } }
        .onChange(of: firstWeekday) { _, _ in store.scheduleReload() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard Date().timeIntervalSince(lastActivation) > 60 else { return }
            lastActivation = Date()
            Task { await store.refreshAll() }
        }
    }

    /// `store.sheet` minus `.detail`, which is presented as a docked side panel instead of a modal sheet.
    private var modalSheetBinding: Binding<ActiveSheet?> {
        Binding(
            get: { if case .detail = store.sheet { return nil } else { return store.sheet } },
            set: { store.sheet = $0 }
        )
    }

    // MARK: Keyboard

    /// Single-key shortcuts for the calendar grid. Modified keys are handled by the menu bar.
    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard store.sheet?.blocksGridShortcuts != true, store.deleteRequest == nil else { return .ignored }

        // Esc cancels a drag in progress (mouse still down) before anything else claims it.
        if store.dragPreview != nil, press.key == .escape { store.cancelDrag(); return .handled }

        // ⌥↑/↓ moves the focused event 15 minutes; ⌥⇧↑/↓ resizes it (bottom edge). Keyboard drag equivalent.
        if press.modifiers == [.option] || press.modifiers == [.option, .shift] {
            let resize = press.modifiers.contains(.shift)
            switch press.key {
            case .upArrow: store.nudgeFocused(minutes: -15, resize: resize); return .handled
            case .downArrow: store.nudgeFocused(minutes: 15, resize: resize); return .handled
            default: break
            }
        }

        if !press.modifiers.isDisjoint(with: [.command, .control, .option]) { return .ignored }

        switch press.key {
        case .leftArrow: store.moveFocusDay(-1); return .handled
        case .rightArrow: store.moveFocusDay(1); return .handled
        case .downArrow: store.moveFocus(1); return .handled
        case .upArrow: store.moveFocus(-1); return .handled
        case .return: store.openFocused(); return .handled
        case .escape:
            if store.focusedEventID != nil { store.focusedEventID = nil; return .handled }
            guard store.hasTemporaryPeople else { return .ignored }
            store.clearTemporaryPeople(); return .handled
        case .delete, .deleteForward: store.deleteFocused(); return .handled
        default: break
        }

        switch press.characters.lowercased() {
        case "t": store.goToday()
        case "n", "c": store.newDraft()
        case "d": store.setMode(.day)
        case "5": store.setMode(.workWeek)
        case "w": store.setMode(.week)
        case "m": store.setMode(.month)
        case "[": store.step(-1)
        case "]": store.step(1)
        case "j": store.joinMeeting()
        case "e": store.editFocused()
        case "p": store.requestAddPerson(temporary: !press.modifiers.contains(.shift))
        case "g": store.openPalette("go to ")
        case "/": store.openPalette()
        case "?": store.openShortcuts()
        default: return .ignored
        }
        return .handled
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(msg).font(.system(size: 12)).lineLimit(2).foregroundStyle(Theme.text)
            Spacer()
            if store.zoomNeedsReconnect {
                Button("Reconnect Zoom") { Task { await store.connectZoom() } }.buttonStyle(SecondaryButtonStyle())
            }
            if store.googleNeedsSignIn {
                Button(store.isSigningIn ? "Waiting…" : "Sign in with Google") { Task { await store.signIn() } }
                    .buttonStyle(SecondaryButtonStyle()).disabled(store.isSigningIn)
            }
            Button { store.errorMessage = nil; store.zoomNeedsReconnect = false } label: { Image(systemName: "xmark") }
                .buttonStyle(IconButtonStyle()).accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color.orange.opacity(0.14))
    }
}

/// Day / Work week / Week / Month switcher (custom so it matches the design in both appearances).
struct ModePicker: View {
    @Environment(CalendarStore.self) private var store

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ViewMode.allCases) { m in
                let on = store.mode == m
                Button { store.setMode(m) } label: {
                    Text(m.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(on ? Theme.text : Theme.text2)
                        .padding(.horizontal, 10).frame(height: 24)
                        .background(RoundedRectangle(cornerRadius: 7).fill(on ? Theme.surface : Color.clear)
                            .shadow(color: .black.opacity(on ? 0.15 : 0), radius: 1, y: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                .help(help(m))
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.hover))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("View")
    }

    private func help(_ m: ViewMode) -> String {
        switch m {
        case .day: return "Day (D)"
        case .workWeek: return "Work week, Mon–Fri (5)"
        case .week: return "Week (W)"
        case .month: return "Month (M)"
        }
    }
}

/// Lets a plain region of a hidden-title-bar window drag the window.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let w = window else { return }
            TrafficLights.apply(to: w)
            for n in [NSWindow.didResizeNotification, NSWindow.didExitFullScreenNotification, NSWindow.didBecomeKeyNotification] {
                NotificationCenter.default.addObserver(forName: n, object: w, queue: .main) { [weak w] _ in
                    if let w { TrafficLights.apply(to: w) }
                }
            }
        }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Navigation, range title, command search, view switcher and New event, per the design canvas.
struct TopBar: View {
    @Environment(CalendarStore.self) private var store
    let leadingInset: CGFloat

    var body: some View {
        ViewThatFits(in: .horizontal) {
            bar(wideSearch: true)
            bar(wideSearch: false)
        }
        .frame(height: 56)
        .background(WindowDragArea())
    }

    private func bar(wideSearch: Bool) -> some View {
        let parts = store.titleParts
        return HStack(spacing: 12) {
            HStack(spacing: 2) {
                Button { store.step(-1) } label: { Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold)) }
                    .buttonStyle(IconButtonStyle()).accessibilityLabel("Previous").help("Previous ([)")
                Button { store.step(1) } label: { Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)) }
                    .buttonStyle(IconButtonStyle()).accessibilityLabel("Next").help("Next (])")
            }
            Button("Today") { store.goToday() }.buttonStyle(SecondaryButtonStyle()).help("Jump to today (T)")

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(parts.main).font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.text)
                Text(parts.year).font(.system(size: 20)).foregroundStyle(Theme.text3)
            }
            .lineLimit(1).fixedSize()
            .padding(.leading, 4)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(store.title)

            Spacer(minLength: 12)

            if store.isLoading { ProgressView().controlSize(.small) }

            UpdateIndicator()

            Button { store.openPalette() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12))
                    if wideSearch {
                        Text("Search or run a command").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    KeyCap("⌘K")
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.text2)
                .padding(.horizontal, 10).frame(width: wideSearch ? 230 : nil, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Search or run a command (⌘K)")
            .accessibilityLabel("Search or run a command")

            ModePicker()

            Button { store.newDraft() } label: {
                HStack(spacing: 7) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                    Text("New event")
                    Text("N").font(.system(size: 11, weight: .medium)).opacity(0.75)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .help("New event (N or ⌘N)")
        }
        .padding(.leading, leadingInset).padding(.trailing, 20)
    }
}


/// Enlarges the close/minimize/zoom buttons and centers them in the 56pt top bar.
enum TrafficLights {
    static let scale: CGFloat = 1.3
    static let barHeight: CGFloat = 56
    static let leading: CGFloat = 12
    static let gap: CGFloat = 8

    static func apply(to window: NSWindow) {
        let kinds: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        let buttons = kinds.compactMap { window.standardWindowButton($0) }
        guard buttons.count == 3, let bar = buttons[0].superview?.superview ?? buttons[0].superview else { return }
        // Grow the titlebar container to the bar's height, pinned to the top of the window.
        if bar.frame.height != barHeight, let content = window.contentView?.superview {
            bar.frame = NSRect(x: 0, y: content.bounds.height - barHeight, width: bar.frame.width, height: barHeight)
        }
        var x = leading
        for b in buttons {
            // Keep bounds at the native size and grow the frame, so AppKit draws the button scaled up.
            let native = b.bounds.size.width > 0 && b.bounds.size.width < 20 ? b.bounds.size : NSSize(width: 14, height: 14)
            let side = native.width * scale
            b.layer?.setAffineTransform(.identity)
            b.setFrameSize(NSSize(width: side, height: native.height * scale))
            b.bounds = NSRect(origin: .zero, size: native)
            b.setFrameOrigin(NSPoint(x: x, y: (b.superview?.bounds.height ?? barHeight) / 2 - b.frame.height / 2))
            x += side + gap
        }
    }
}
