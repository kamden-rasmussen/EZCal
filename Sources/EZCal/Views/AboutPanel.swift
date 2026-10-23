import AppKit

/// The standard About panel, with the commit the app was built from next to the version (issue #83) so an installed
/// copy can be traced to its source. `EZCalGitCommit` is stamped into Info.plist by scripts/build_app.sh.
enum AboutPanel {
    static let sourceURL = URL(string: "https://github.com/kamden-rasmussen/EZCal")!

    static func buildLabel(commit: String?) -> String? {
        guard let commit, !commit.isEmpty else { return nil }
        return commit
    }

    static func credits(commit: String?) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let link = commit.flatMap { $0.hasSuffix("-dirty") ? nil : URL(string: "\(sourceURL.absoluteString)/commit/\($0)") } ?? sourceURL
        let text = NSMutableAttributedString(string: "Source: kamden-rasmussen/EZCal", attributes: [.font: font])
        text.addAttribute(.link, value: link, range: NSRange(location: 8, length: text.length - 8))
        let style = NSMutableParagraphStyle(); style.alignment = .center
        text.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: text.length))
        return text
    }

    static func show() {
        let commit = Bundle.main.object(forInfoDictionaryKey: "EZCalGitCommit") as? String
        var options: [NSApplication.AboutPanelOptionKey: Any] = [.credits: credits(commit: commit)]
        if let label = buildLabel(commit: commit) { options[.version] = label }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: options)
    }
}
