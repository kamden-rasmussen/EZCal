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

    var body: some View {
        TabView {
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
                Section("Google OAuth client") { GoogleCredentialsForm() }
            }
            .formStyle(.grouped)
            .tabItem { Label("Accounts", systemImage: "person.crop.circle") }

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
                            Button("Connect Zoom") { Task { await store.connectZoom() } }
                                .disabled(zoomClientID.isEmpty)
                        }
                    }
                    Text("Create a “General app” (user-managed OAuth) in the Zoom App Marketplace, add the scope meeting:write:meeting (plus meeting:update:meeting and meeting:delete:meeting), and register http://localhost:48291/callback as the redirect URL.")
                        .font(.caption).foregroundStyle(.secondary)
                    Link("Open Zoom App Marketplace", destination: URL(string: "https://marketplace.zoom.us/develop/create")!).font(.caption)
                }
                if let e = store.errorMessage { Text(e).font(.caption).foregroundStyle(.red) }
            }
            .formStyle(.grouped)
            .tabItem { Label("Zoom", systemImage: "video") }

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
                    Slider(value: $hourHeight, in: 36...120).frame(width: 180)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 520, height: 460)
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
