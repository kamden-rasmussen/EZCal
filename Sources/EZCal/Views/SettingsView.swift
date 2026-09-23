import SwiftUI

struct SecretField: View {
    let title: String
    let keychainKey: String
    @State private var text = ""

    var body: some View {
        SecureField(title, text: $text)
            .onAppear { text = Keychain.get(keychainKey) ?? "" }
            .onChange(of: text) { _, new in Keychain.set(new, for: keychainKey) }
    }
}

struct GoogleCredentialsForm: View {
    @AppStorage("googleClientID") private var clientID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Client ID", text: $clientID)
            SecretField(title: "Client secret", keychainKey: "googleClientSecret")
            Text("Create an OAuth client of type “Desktop app” in Google Cloud Console and enable the Google Calendar API and People API. See the README for step-by-step instructions.")
                .font(.caption).foregroundStyle(.secondary)
            Link("Open Google Cloud Console", destination: URL(string: "https://console.cloud.google.com/apis/credentials")!).font(.caption)
        }
    }
}

struct SettingsView: View {
    @Environment(CalendarStore.self) private var store
    @AppStorage("zoomClientID") private var zoomClientID = ""
    @AppStorage("showWeekends") private var showWeekends = true
    @AppStorage("firstWeekday") private var firstWeekday = 0
    @AppStorage("defaultDuration") private var defaultDuration = 60
    @AppStorage("defaultVideo") private var defaultVideo = "none"
    @AppStorage("hourHeight") private var hourHeight = 56.0
    @AppStorage("overlapLayoutMode") private var overlapLayoutModeRaw = OverlapLayoutMode.auto.rawValue
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @AppStorage("notificationLeadMinutes") private var notificationLeadMinutes = 5
    @AppStorage("notificationVideoOnly") private var notificationVideoOnly = false
    @AppStorage(WorkingHours.Keys.days) private var workDaysRaw = WorkingHours.defaultDaysRaw
    @AppStorage(WorkingHours.Keys.start) private var workStart = WorkingHours.standard.startMinute
    @AppStorage(WorkingHours.Keys.end) private var workEnd = WorkingHours.standard.endMinute
    @AppStorage("showSecondaryZone") private var showSecondaryZone = true
    @AppStorage("secondaryZoneID") private var secondaryZoneID = ""
    // Zoom meeting defaults — read into a fresh `ZoomMeetingOptions` wherever a meeting is created
    // without going through the editor (Settings itself doesn't need the struct, just the raw keys).
    @AppStorage("zoomWaitingRoom") private var zoomWaitingRoom = true
    @AppStorage("zoomMuteOnEntry") private var zoomMuteOnEntry = false
    @AppStorage("zoomJoinBeforeHost") private var zoomJoinBeforeHost = false
    @AppStorage("zoomHostVideo") private var zoomHostVideo = true
    @AppStorage("zoomParticipantVideo") private var zoomParticipantVideo = false
    @AppStorage("zoomPasscodeEnabled") private var zoomPasscodeEnabled = true
    /// Which tab opens first; overridden by the "settings" debug snapshot (`EZCAL_SETTINGS_TAB` = accounts|zoom|general|hours)
    /// so a screenshot can land on any tab.
    var initialTab: Tab = .accounts
    @State private var tab: Tab = .accounts

    enum Tab { case accounts, zoom, general, hours }

    var body: some View {
        TabView(selection: $tab) {
            Form {
                Section("Google accounts") {
                    ForEach(store.accounts) { a in
                        HStack {
                            Text(a.email)
                            Spacer()
                            Button("Sign out", role: .destructive) { store.signOut(a) }
                        }
                    }
                    Button {
                        Task { await store.signIn() }
                    } label: { Label(store.isSigningIn ? "Waiting for browser…" : "Add Google account", systemImage: "person.badge.plus") }
                    .disabled(store.isSigningIn || !AppSettings.hasGoogleCredentials)
                }
                Section("Apple Calendar (iCloud & other system accounts)") {
                    if store.eventKitEnabled {
                        HStack {
                            Label("Enabled", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            Spacer()
                            Button("Disable", role: .destructive) { store.disableEventKit() }
                        }
                    } else {
                        Button { Task { await store.enableEventKit() } } label: {
                            Label("Enable Apple Calendar access", systemImage: "apple.logo")
                        }
                    }
                    Text("Shows every calendar macOS already syncs: iCloud, Exchange, Fastmail, CalDAV. Add or remove accounts in System Settings → Internet Accounts.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let e = store.errorMessage, !store.eventKitEnabled { Text(e).font(.caption).foregroundStyle(.red) }
                }
                Section("Calendar subscriptions") {
                    ForEach(store.icsSubscriptions) { sub in
                        HStack {
                            Circle().fill(Color(hex: sub.colorHex)).frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(sub.name)
                                Text(sub.url.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if let error = store.sourceErrors[sub.source.id] {
                                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange).help(error)
                            }
                            Button("Remove", role: .destructive) { store.removeICSSubscription(sub) }
                        }
                    }
                    Button { store.openAddSubscription() } label: { Label("Add calendar by URL…", systemImage: "link.badge.plus") }
                    Text("Read-only .ics feeds — sports schedules, team calendars, holiday lists. Accepts webcal:// and https:// links.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Reminders (tasks)") {
                    if store.tasks.enabled {
                        HStack {
                            Label("Enabled", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            Spacer()
                            Button("Disable", role: .destructive) { store.disableReminders() }
                        }
                    } else {
                        Button { Task { await store.enableReminders() } } label: {
                            Label("Enable Reminders access", systemImage: "checklist")
                        }
                    }
                    Text("Shows tasks with due dates from Apple Reminders in the grid, with a checkbox to complete them, and lets ⌘K quick-add new ones (\u{201c}task: call dentist tomorrow 3pm\u{201d}).")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Google OAuth client") { GoogleCredentialsForm() }
            }
            .formStyle(.grouped)
            .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
            .tag(Tab.accounts)

            Form {
                Section("Zoom") {
                    TextField("Client ID", text: $zoomClientID)
                    SecretField(title: "Client secret", keychainKey: "zoomClientSecret")
                    HStack {
                        if store.zoomConnected {
                            Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            Spacer()
                            Button("Disconnect", role: .destructive) { store.disconnectZoom() }
                        } else {
                            Button(store.zoomNeedsReconnect ? "Reconnect Zoom" : "Connect Zoom") { Task { await store.connectZoom() } }
                                .disabled(zoomClientID.isEmpty)
                        }
                    }
                    if store.zoomNeedsReconnect {
                        Label("Zoom's sign-in expired — reconnect to keep creating meetings.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Text("Create a “General app” (user-managed OAuth) in the Zoom App Marketplace, add the scope meeting:write:meeting (plus meeting:update:meeting and meeting:delete:meeting), and register http://localhost:48291/callback as the redirect URL.")
                        .font(.caption).foregroundStyle(.secondary)
                    Link("Open Zoom App Marketplace", destination: URL(string: "https://marketplace.zoom.us/develop/create")!).font(.caption)
                }
                Section("Meeting defaults") {
                    Toggle("Waiting room", isOn: $zoomWaitingRoom)
                    Toggle("Mute participants on entry", isOn: $zoomMuteOnEntry)
                    Toggle("Join before host", isOn: $zoomJoinBeforeHost)
                    Toggle("Host video on", isOn: $zoomHostVideo)
                    Toggle("Participant video on", isOn: $zoomParticipantVideo)
                    Toggle("Require passcode", isOn: $zoomPasscodeEnabled)
                    Text("Used for new Zoom meetings; each event can override them before creating one.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let e = store.errorMessage { Text(e).font(.caption).foregroundStyle(.red) }
            }
            .formStyle(.grouped)
            .tabItem { Label("Zoom", systemImage: "video") }
            .tag(Tab.zoom)

            Form {
                Toggle("Show weekends", isOn: $showWeekends)
                Picker("Week starts on", selection: $firstWeekday) {
                    Text("System default").tag(0)
                    Text("Sunday").tag(1)
                    Text("Monday").tag(2)
                    Text("Saturday").tag(7)
                }
                Picker("Default event length", selection: $defaultDuration) {
                    ForEach([15, 30, 45, 60, 90], id: \.self) { Text("\($0) min").tag($0) }
                }
                Picker("Add video to new events", selection: $defaultVideo) {
                    Text("Never").tag("none")
                    Text("Zoom").tag("zoom")
                    Text("Google Meet").tag("meet")
                }
                LabeledContent("Hour height") {
                    Slider(value: $hourHeight, in: AppSettings.hourHeightRange).frame(width: 180)
                }
                Picker("Overlapping events", selection: $overlapLayoutModeRaw) {
                    Text("Fit side by side when possible").tag(OverlapLayoutMode.auto.rawValue)
                    Text("Always overlap (cascade)").tag(OverlapLayoutMode.cascade.rawValue)
                }
                Text("When same-time events can't all fit as side-by-side columns, hover the stack to cycle through what's underneath every few seconds.")
                    .font(.caption).foregroundStyle(.secondary)
                Section("Meeting reminders") {
                    Toggle("Notify me before meetings", isOn: $notificationsEnabled)
                        .onChange(of: notificationsEnabled) { _, _ in Task { await store.rescheduleNotifications() } }
                    Picker("Remind me", selection: $notificationLeadMinutes) {
                        Text("1 minute before").tag(1)
                        Text("5 minutes before").tag(5)
                        Text("10 minutes before").tag(10)
                        Text("15 minutes before").tag(15)
                    }
                    .disabled(!notificationsEnabled)
                    .onChange(of: notificationLeadMinutes) { _, _ in Task { await store.rescheduleNotifications() } }
                    Toggle("Only for events with a video link", isOn: $notificationVideoOnly)
                        .disabled(!notificationsEnabled)
                        .onChange(of: notificationVideoOnly) { _, _ in Task { await store.rescheduleNotifications() } }
                    Button("Send test notification") {
                        Task {
                            let ok = await store.sendTestNotification()
                            if !ok { store.errorMessage = "Notifications permission denied. Enable EZCal in System Settings → Notifications." }
                        }
                    }
                    Text("A system notification appears a few minutes before each upcoming meeting, with a Join button when it has a Zoom/Meet/Teams link and Open to jump to it in EZCal. Works while the window is closed, as long as EZCal is running (menu bar item).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gearshape") }
            .tag(Tab.general)

            Form {
                Section("Working hours") {
                    WorkDaysPicker(daysRaw: $workDaysRaw)
                    LabeledContent("Starts") {
                        MinutePicker(minute: $workStart)
                            .onChange(of: workStart) { _, new in if workEnd <= new { workEnd = min(new + WorkingHours.minuteStep, 24 * 60) } }
                    }
                    LabeledContent("Ends") {
                        MinutePicker(minute: $workEnd)
                            .onChange(of: workEnd) { _, new in if new <= workStart { workStart = max(new - WorkingHours.minuteStep, 0) } }
                    }
                    Text("Hours outside this range are shaded in the grid, and the day starts scrolled to the beginning of your working day.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Secondary time zone") {
                    Toggle("Show a second hour column", isOn: $showSecondaryZone)
                    Picker("Time zone", selection: $secondaryZoneID) {
                        Text("None").tag("")
                        ForEach(SecondaryZoneList.all, id: \.self) { id in
                            Text(SecondaryZoneList.label(id)).tag(id)
                        }
                    }
                    .disabled(!showSecondaryZone)
                    Text("Shown as a second gutter next to the hours, and event times hover-tooltip in this zone too. Toggle quickly with “Show time zone” in ⌘K.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Hours & zones", systemImage: "clock") }
            .tag(Tab.hours)
        }
        .frame(width: 520, height: 460)
        .onAppear {
            switch ProcessInfo.processInfo.environment["EZCAL_SETTINGS_TAB"] {
            case "zoom": tab = .zoom
            case "general": tab = .general
            case "hours": tab = .hours
            case "accounts": tab = .accounts
            default: tab = initialTab
            }
        }
    }
}

/// Seven day-of-week toggle chips (Sun…Sat order follows the user's locale start-of-week for familiarity,
/// but the underlying storage always uses Calendar weekday numbers 1...7 so it's locale-independent).
struct WorkDaysPicker: View {
    @Binding var daysRaw: String
    private let symbols = Calendar.current.veryShortWeekdaySymbols   // index 0 = Sunday, matching weekday 1

    var body: some View {
        let days = WorkingHours.decodeDays(daysRaw)
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { weekday in
                let on = days.contains(weekday)
                Button {
                    var d = days
                    if on { d.remove(weekday) } else { d.insert(weekday) }
                    daysRaw = WorkingHours.encodeDays(d)
                } label: {
                    Text(symbols[weekday - 1])
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 26, height: 26)
                        .foregroundStyle(on ? Theme.accentText : Theme.text2)
                        .background(Circle().fill(on ? Theme.accent : Theme.hover))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Calendar.current.weekdaySymbols[weekday - 1])
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

/// Half-hour time-of-day picker bound to minutes-since-midnight, so it stores cleanly in UserDefaults/AppSettings.
struct MinutePicker: View {
    @Binding var minute: Int

    private var asDate: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date() },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                minute = (c.hour ?? 0) * 60 + (((c.minute ?? 0) / WorkingHours.minuteStep) * WorkingHours.minuteStep)
            })
    }

    var body: some View {
        DatePicker("", selection: asDate, displayedComponents: .hourAndMinute)
            .labelsHidden()
            .datePickerStyle(.stepperField)
            .frame(width: 100)
    }
}

/// Common IANA zone identifiers for the secondary-zone picker, grouped loosely by region.
enum SecondaryZoneList {
    static let all: [String] = [
        "America/Los_Angeles", "America/Denver", "America/Chicago", "America/New_York", "America/Halifax",
        "America/Anchorage", "Pacific/Honolulu", "America/Sao_Paulo", "America/Mexico_City",
        "Europe/London", "Europe/Dublin", "Europe/Lisbon", "Europe/Paris", "Europe/Berlin", "Europe/Madrid",
        "Europe/Rome", "Europe/Amsterdam", "Europe/Zurich", "Europe/Stockholm", "Europe/Athens", "Europe/Helsinki",
        "Europe/Istanbul", "Europe/Moscow",
        "Asia/Dubai", "Asia/Kolkata", "Asia/Shanghai", "Asia/Hong_Kong", "Asia/Singapore", "Asia/Tokyo", "Asia/Seoul",
        "Australia/Perth", "Australia/Sydney", "Australia/Melbourne", "Pacific/Auckland", "UTC",
    ]

    static func label(_ id: String) -> String {
        let city = id.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? id
        return "\(city) (\(ZoneMath.shortName(TimeZone(identifier: id) ?? .current)))"
    }
}

/// Shown in the main window until a calendar source is connected.
struct SetupView: View {
    @Environment(CalendarStore.self) private var store
    @AppStorage("googleClientID") private var clientID = ""
    @State private var showGoogleSetup = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: "calendar")
                    .font(.system(size: 26, weight: .medium)).foregroundStyle(Theme.accentText)
                    .frame(width: 56, height: 56)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.accent))
                Text("All your calendars,\none calm place.")
                    .font(.system(size: 30, weight: .bold)).lineSpacing(2)
                Text("See your iCloud and Google calendars together, lay your coworkers' schedules over your own, and drop a Zoom link on any event in one click.")
                    .foregroundStyle(Theme.text2).lineSpacing(3)
                Spacer()
                Text("Free and open source. Your sign-ins stay in your Mac's Keychain; nothing goes through a server.")
                    .font(.system(size: 12)).foregroundStyle(Theme.text3)
            }
            .padding(.horizontal, 34).padding(.vertical, 44)
            .frame(width: 340, alignment: .leading)
            .frame(maxHeight: .infinity)
            .background(Theme.side)

            VStack(alignment: .leading, spacing: 16) {
                SectionLabel("Step 1 · Connect a calendar")

                card(symbol: "icloud", tint: .green, title: "iCloud & Apple Calendar",
                     detail: "Uses the accounts already on this Mac. No setup.") {
                    Button("Connect") { Task { await store.enableEventKit() } }
                        .buttonStyle(PrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }

                card(symbol: "g.circle", tint: Color(hex: "#3E63DD"), title: "Google Calendar",
                     detail: "Adds coworker overlay and Google Meet. Needs a one-time key, about 5 minutes.") {
                    if AppSettings.hasGoogleCredentials {
                        Button(store.isSigningIn ? "Waiting…" : "Sign in") { Task { await store.signIn() } }
                            .buttonStyle(SecondaryButtonStyle()).disabled(store.isSigningIn)
                    } else {
                        Button(showGoogleSetup ? "Hide" : "Set up") { showGoogleSetup.toggle() }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
                if showGoogleSetup && !AppSettings.hasGoogleCredentials {
                    VStack(alignment: .leading, spacing: 10) {
                        GoogleCredentialsForm()
                        Text("Then sign in from Settings → Accounts, or press Return.").font(.system(size: 12)).foregroundStyle(Theme.text3)
                    }
                    .padding(16).background(RoundedRectangle(cornerRadius: 12).fill(Theme.hover))
                }

                SectionLabel("Step 2 · Optional").padding(.top, 10)
                HStack(spacing: 14) {
                    Image(systemName: "video.fill").foregroundStyle(Color(hex: "#3E63DD"))
                        .frame(width: 36, height: 36).background(RoundedRectangle(cornerRadius: 9).fill(Color(hex: "#3E63DD").opacity(0.12)))
                    (Text("Zoom").fontWeight(.semibold).foregroundStyle(Theme.text)
                        + Text(" · create meetings straight from the event editor").foregroundStyle(Theme.text2))
                    Spacer()
                    Button("Settings…") { store.openSettings() }.buttonStyle(SecondaryButtonStyle())
                }
                .padding(.horizontal, 18).padding(.vertical, 14)
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))

                if let e = store.errorMessage { Text(e).font(.system(size: 12)).foregroundStyle(.red) }
                Spacer()
                HStack(spacing: 6) {
                    Text("Press").foregroundStyle(Theme.text3)
                    KeyCap("?")
                    Text("anytime to see every keyboard shortcut.").foregroundStyle(Theme.text3)
                }
                .font(.system(size: 12))
            }
            .padding(.horizontal, 40).padding(.vertical, 44)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Theme.bg)
        .onKeyPress("?") { store.openShortcuts(); return .handled }
    }

    private func card<A: View>(symbol: String, tint: Color, title: String, detail: String, @ViewBuilder action: () -> A) -> some View {
        HStack(spacing: 16) {
            Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(tint)
                .frame(width: 44, height: 44).background(RoundedRectangle(cornerRadius: 11).fill(tint.opacity(0.14)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(detail).foregroundStyle(Theme.text2)
            }
            Spacer(minLength: 8)
            action()
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
    }
}
