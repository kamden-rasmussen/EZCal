import Foundation

/// Heuristics for spotting EventKit calendars that are really Google calendars synced through
/// System Settings → Internet Accounts (issue #52). EventKit has no "this is Google" flag: EKSource
/// exposes only title, sourceType (calDAV for Google, iCloud, Fastmail...), sourceIdentifier and
/// isDelegate. UNVERIFIED against real data; based on docs and third-party reports (see issue #52).
enum GoogleBacking {
    /// Google-generated event UIDs (Google's `iCalUID`, which per RFC 5545 is the CalDAV UID, and so
    /// presumably EventKit's `calendarItemExternalIdentifier`) end in `@google.com`. Events imported
    /// from elsewhere keep their original UID, so `false` is not proof of non-Google.
    static func isGoogleUID(_ uid: String?) -> Bool {
        uid?.lowercased().hasSuffix("@google.com") == true
    }

    /// Does an EventKit account/source title or calendar name equal a directly connected Google
    /// account email (or its local part)? EKSource.title is "usually the account email" but not
    /// guaranteed, so callers should also pass calendar names (a primary calendar is named by email).
    static func matchesConnectedAccount(_ candidates: [String], accounts: [Account]) -> Account? {
        let lowered = candidates.map { $0.lowercased() }
        return accounts.first { a in
            let email = a.email.lowercased()
            let local = email.split(separator: "@").first.map(String.init) ?? email
            return lowered.contains(email) || lowered.contains(local)
        }
    }
}
