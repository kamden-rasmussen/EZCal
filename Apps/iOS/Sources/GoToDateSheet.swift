import SwiftUI

/// Month-grid date picker that jumps the shared anchor to the chosen day (#109).
struct GoToDateSheet: View {
    @Environment(CalendarStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var ready = false

    var body: some View {
        NavigationStack {
            VStack {
                DatePicker("Go to date", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .accessibilityIdentifier("goToDatePicker")
                    .padding(.horizontal)
                Spacer()
            }
            .navigationTitle("Go to date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Today") { store.goToday(); dismiss() }.accessibilityIdentifier("goToTodayButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("goToDateDone")
                }
            }
            .onAppear { date = store.anchor; DispatchQueue.main.async { ready = true } }
            // Picking a day jumps straight there, like Apple Calendar's picker.
            .onChange(of: date) { _, d in if ready { store.goTo(d); dismiss() } }
        }
        .presentationDetents([.medium, .large])
    }
}
