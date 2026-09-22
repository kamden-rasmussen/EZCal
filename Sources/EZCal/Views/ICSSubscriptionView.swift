import SwiftUI

/// "Add calendar by URL" — reachable from Settings → Accounts and the ⌘K palette. Read-only .ics feeds
/// (sports schedules, team calendars, holiday lists) show up in the sidebar like any other calendar.
struct AddICSSubscriptionView: View {
    @Environment(CalendarStore.self) private var store
    @State private var urlText = ""
    @State private var name = ""
    @State private var colorHex = Palette.people[0]
    @State private var errorText: String?
    @FocusState private var urlFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Add calendar by URL").font(.system(size: 16, weight: .semibold))
                Spacer()
                Button { store.sheet = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(IconButtonStyle()).keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Close").help("Close (esc)")
            }
            Text("Subscribe to a read-only .ics feed — a sports schedule, a shared team calendar, a holiday list.")
                .font(.system(size: 12)).foregroundStyle(Theme.text2)

            VStack(alignment: .leading, spacing: 6) {
                Text("Calendar URL").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text2)
                TextField("webcal://… or https://…", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .focused($urlFocused)
                    .onSubmit(submit)
                    .accessibilityLabel("Calendar URL")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Name").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text2)
                TextField("Calendar name", text: $name).textFieldStyle(.roundedBorder).onSubmit(submit)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Color").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text2)
                HStack(spacing: 6) {
                    ForEach(Palette.people, id: \.self) { hex in
                        Circle().fill(Color(hex: hex)).frame(width: 20, height: 20)
                            .overlay(Circle().strokeBorder(Theme.text, lineWidth: colorHex == hex ? 2 : 0))
                            .onTapGesture { colorHex = hex }
                            .accessibilityLabel("Color \(hex)")
                            .accessibilityAddTraits(colorHex == hex ? .isSelected : [])
                    }
                }
            }

            if let errorText { Text(errorText).font(.system(size: 12)).foregroundStyle(.red) }

            HStack {
                Spacer()
                Button("Cancel") { store.sheet = nil }.buttonStyle(SecondaryButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Add") { submit() }.buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction).disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 420)
        .background(Theme.surface)
        .onAppear { urlFocused = true }
    }

    private func submit() {
        do {
            try store.addICSSubscription(urlString: urlText, name: name, colorHex: colorHex)
            store.sheet = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}
