import Foundation
import Observation

/// A dotted numeric version ("1.10.0"). Compared component by component as integers, so 1.10.0 > 1.9.0.
struct SemVer: Comparable, Equatable, CustomStringConvertible {
    let parts: [Int]

    /// Accepts "1", "1.2" or "1.2.3" (digits only, at most three components); anything else is nil.
    init?(_ string: String) {
        let pieces = string.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(pieces.count) else { return nil }
        var out: [Int] = []
        for p in pieces {
            guard !p.isEmpty, p.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(p) else { return nil }
            out.append(n)
        }
        parts = out
    }

    var description: String { parts.map(String.init).joined(separator: ".") }

    static func < (a: SemVer, b: SemVer) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0
            let y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    static func == (a: SemVer, b: SemVer) -> Bool { !(a < b) && !(b < a) }
}

/// One entry of GitHub's releases list; only the fields we use.
struct GitHubRelease: Decodable, Equatable {
    let tagName: String
    let draft: Bool
    let prerelease: Bool

    enum CodingKeys: String, CodingKey { case tagName = "tag_name", draft, prerelease }
}

/// Looks for a newer EZCal on the Homebrew tap's GitHub Releases. The tap may host other apps, so this reads
/// the full releases list and keeps only `ezcal-vX.Y.Z` tags (not `/latest`, which could be another app).
@MainActor @Observable
final class UpdateChecker {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(SemVer)
        case failed
    }

    nonisolated static let tagPrefix = "ezcal-v"
    nonisolated static let releasesURL = URL(string: "https://api.github.com/repos/kamden-rasmussen/homebrew-tap/releases")!
    static let upgradeCommand = "brew update && brew upgrade --cask ezcal"
    static let interval: TimeInterval = 6 * 60 * 60

    private(set) var status: Status = .idle
    /// Set once a check finds a newer version; a later failed check doesn't clear it.
    private(set) var availableVersion: SemVer?
    let currentVersion: SemVer?

    @ObservationIgnored private let fetch: () async throws -> Data
    @ObservationIgnored private var timer: Task<Void, Never>?

    init(currentVersion: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
         fetch: @escaping () async throws -> Data = UpdateChecker.fetchReleases) {
        self.currentVersion = currentVersion.flatMap(SemVer.init)
        self.fetch = fetch
    }

    deinit { timer?.cancel() }

    nonisolated static func fetchReleases() async throws -> Data {
        var req = URLRequest(url: releasesURL, timeoutInterval: 20)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    /// The highest non-draft, non-prerelease `ezcal-vX.Y.Z` release, or nil if there is none.
    nonisolated static func latestVersion(in releases: [GitHubRelease]) -> SemVer? {
        releases
            .filter { !$0.draft && !$0.prerelease && $0.tagName.hasPrefix(tagPrefix) }
            .compactMap { SemVer(String($0.tagName.dropFirst(tagPrefix.count))) }
            .max()
    }

    /// Checks now and then every ~6 hours. Failures are silent.
    func start() {
        guard timer == nil else { return }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(nanoseconds: UInt64(Self.interval * 1_000_000_000))
            }
        }
    }

    /// `manual`: the user asked, so the outcome (including failure) is reflected in `status`.
    /// Automatic checks never surface errors and leave the last known result in place.
    func check(manual: Bool = false) async {
        if manual { status = .checking }
        do {
            let releases = try JSONDecoder().decode([GitHubRelease].self, from: try await fetch())
            let latest = Self.latestVersion(in: releases)
            if let latest, let current = currentVersion, latest > current {
                availableVersion = latest
                status = .available(latest)
            } else {
                availableVersion = nil
                status = .upToDate
            }
        } catch {
            if manual { status = .failed }
        }
    }
}
