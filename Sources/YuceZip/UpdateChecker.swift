import AppKit

/// Checks GitHub Releases for a newer version of YUCE ZIP.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    static let repository = "bariscagriyuce/yuce-zip"
    static var repositoryURL: URL { URL(string: "https://github.com/\(repository)")! }
    private static var latestReleaseAPI: URL { URL(string: "https://api.github.com/repos/\(repository)/releases/latest")! }

    @Published private(set) var isChecking = false
    @Published private(set) var lastCheck: Date? = Prefs.lastUpdateCheck

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    struct Release {
        var version: String
        var pageURL: URL
        var downloadURL: URL?
        var notes: String
    }

    enum CheckError: LocalizedError {
        case badResponse(Int)
        var errorDescription: String? {
            switch self { case .badResponse(let code): return "HTTP \(code)" }
        }
    }

    /// Checks automatically at launch, if enabled.
    func checkAtLaunchIfNeeded() {
        guard Prefs.autoCheckUpdates else { return }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await check(userInitiated: false)
        }
    }

    func check(userInitiated: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        do {
            let release = try await fetchLatest()
            Prefs.lastUpdateCheck = Date()
            lastCheck = Prefs.lastUpdateCheck
            if let release, Self.isVersion(release.version, newerThan: Self.currentVersion) {
                showUpdateAvailable(release)
            } else if userInitiated {
                await Dialogs.message(window: nil, title: L("update.uptodate.title"),
                                      text: LF("update.uptodate.message", Self.currentVersion),
                                      style: .informational)
            }
        } catch {
            if userInitiated {
                await Dialogs.message(window: nil, title: L("update.failed.title"),
                                      text: LF("update.failed.message", error.localizedDescription),
                                      style: .warning)
            }
        }
    }

    private func fetchLatest() async throws -> Release? {
        var request = URLRequest(url: Self.latestReleaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("YuceZip/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }              // no release published yet
        guard status == 200 else { throw CheckError.badResponse(status) }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { return nil }
        let page = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? Self.repositoryURL
        var download: URL? = nil
        if let assets = json["assets"] as? [[String: Any]] {
            for asset in assets {
                if let name = asset["name"] as? String, name.lowercased().hasSuffix(".dmg"),
                   let s = asset["browser_download_url"] as? String, let u = URL(string: s) {
                    download = u
                    break
                }
            }
        }
        return Release(version: Self.clean(tag), pageURL: page, downloadURL: download,
                       notes: (json["body"] as? String) ?? "")
    }

    private func showUpdateAvailable(_ release: Release) {
        let alert = NSAlert()
        alert.messageText = L("update.available.title")
        alert.informativeText = LF("update.available.message", release.version, Self.currentVersion)
        alert.alertStyle = .informational
        alert.addButton(withTitle: L("update.download"))
        alert.addButton(withTitle: L("update.later"))
        let notes = release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            alert.accessoryView = Dialogs.scrollingText(L("update.notes") + "\n\n" + notes)
        }
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.downloadURL ?? release.pageURL)
        }
    }

    // MARK: Version comparison

    static func clean(_ tag: String) -> String {
        var t = tag.trimmingCharacters(in: .whitespaces)
        if t.lowercased().hasPrefix("v") { t.removeFirst() }
        return t
    }

    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            clean(s).split(whereSeparator: { $0 == "." || $0 == "-" }).map { Int($0.filter(\.isNumber)) ?? 0 }
        }
        let pa = parts(a), pb = parts(b)
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
