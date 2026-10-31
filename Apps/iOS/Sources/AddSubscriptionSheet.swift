import SwiftUI

/// iOS form for subscribing to a read-only .ics feed (the macOS `AddICSSubscriptionView` uses
/// macOS-only styles, so this is the touch counterpart). Accepts webcal:// and https:// links.
struct AddSubscriptionSheet: View {
    @Environment(CalendarStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var urlText: String
    @State private var name = ""
    @State private var colorHex = Palette.people[0]
    @State private var errorText: String?

    init(initialURL: String = "") { _urlText = State(initialValue: initialURL) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("webcal://… or https://…", text: $urlText)
                        .keyboardType(.URL).textContentType(.URL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("subscriptionURLField")
                    TextField("Name (optional)", text: $name)
                        .accessibilityIdentifier("subscriptionNameField")
                } footer: {
                    Text("Read-only .ics feeds: sports schedules, team calendars, holiday lists.")
                }
                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 14) {
                        ForEach(Palette.people, id: \.self) { hex in
                            Button { colorHex = hex } label: {
                                Circle().fill(Color(hex: hex)).frame(width: 34, height: 34)
                                    .overlay { if colorHex == hex { Image(systemName: "checkmark").foregroundStyle(.white) } }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Color \(hex)")
                        }
                    }.padding(.vertical, 4)
                }
                if let errorText {
                    Section { Text(errorText).foregroundStyle(.red).accessibilityIdentifier("subscriptionError") }
                }
            }
            .navigationTitle("Add calendar by URL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("subscriptionCancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { submit() }
                        .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("subscriptionAdd")
                }
            }
        }
    }

    private func submit() {
        do {
            try store.addICSSubscription(urlString: urlText, name: name, colorHex: colorHex)
            dismiss()
        } catch { errorText = error.localizedDescription }
    }
}

/// Presents the add-subscription form when the app is opened with a webcal:// (or webcals://) link.
struct WebcalLinkHandler: ViewModifier {
    @State private var pending: PendingURL?
    struct PendingURL: Identifiable { let id = UUID(); let url: String }

    func body(content: Content) -> some View {
        content
            .onOpenURL { url in
                guard let scheme = url.scheme?.lowercased(), scheme == "webcal" || scheme == "webcals" else { return }
                let s = url.absoluteString
                pending = PendingURL(url: scheme == "webcals" ? "https" + s.dropFirst("webcals".count) : s)
            }
            .sheet(item: $pending) { p in AddSubscriptionSheet(initialURL: p.url) }
    }
}
extension View { func handlesWebcalLinks() -> some View { modifier(WebcalLinkHandler()) } }
