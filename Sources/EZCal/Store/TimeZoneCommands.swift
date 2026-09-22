import Foundation

extension CalendarStore {
    /// ⌘K "Show time zone": toggles the secondary hour gutter. Sends you to Settings if no zone is chosen yet.
    func toggleSecondaryZone() {
        let d = UserDefaults.standard
        let id = d.string(forKey: "secondaryZoneID") ?? ""
        let showing = d.object(forKey: "showSecondaryZone") as? Bool ?? true
        if id.isEmpty {
            d.set(true, forKey: "showSecondaryZone")
            errorMessage = "Choose a second time zone in Settings → Hours & zones."
            openSettings()
        } else {
            d.set(!showing, forKey: "showSecondaryZone")
        }
    }

    var secondaryZoneShown: Bool { AppSettings.secondaryTimeZone != nil }
}
