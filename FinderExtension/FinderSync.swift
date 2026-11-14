import Cocoa
import FinderSync

/// Finder Sync extension: adds a "YUCE ZIP ▸" submenu to Finder's right-click menu,
/// similar to the 7-Zip shell menu on Windows and Linux.
/// The extension is sandboxed, so it only builds the menu and hands the work to the
/// main app through the yucezip:// URL scheme.
@objc(YZFinderSync)
final class YZFinderSync: FIFinderSync {

    override init() {
        super.init()
        // Watch the whole file system so the menu shows up everywhere.
        var dirs: Set<URL> = [URL(fileURLWithPath: "/")]
        if let vols = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) {
            dirs.formUnion(vols)
        }
        FIFinderSyncController.default().directoryURLs = dirs
    }

    private static let appIcon: NSImage? = {
        // .../YUCE ZIP.app/Contents/PlugIns/YuceZipFinder.appex -> .../Contents/Resources/AppIcon.icns
        let contents = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        let img = NSImage(contentsOf: contents.appendingPathComponent("Resources/AppIcon.icns"))
        img?.size = NSSize(width: 16, height: 16)
        return img
    }()

    private var selection: [URL] {
        let c = FIFinderSyncController.default()
        if let items = c.selectedItemURLs(), !items.isEmpty { return items }
        if let target = c.targetedURL() { return [target] }
        return []
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems else { return nil }
        let items = selection
        guard !items.isEmpty else { return nil }

        let archives = items.filter(FinderArchiveTypes.isArchive)
        let allArchives = archives.count == items.count

        let sub = NSMenu(title: "YUCE ZIP")
        func add(_ title: String, _ action: Selector, _ symbol: String) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            sub.addItem(item)
        }

        if allArchives {
            if archives.count == 1 { add(L("finder.open"), #selector(openArchive(_:)), "archivebox") }
            add(L("finder.extract"), #selector(extractDialog(_:)), "arrow.down.doc")
            add(L("finder.extractHere"), #selector(extractHere(_:)), "arrow.down.to.line")
            let folderName = archives.count == 1 ? FinderArchiveTypes.baseName(of: archives[0]) : "*"
            add(LF("finder.extractTo", folderName), #selector(extractToFolder(_:)), "folder.badge.plus")
            add(L("finder.test"), #selector(test(_:)), "checkmark.shield")
            sub.addItem(.separator())
        }

        let base: String
        if items.count == 1 {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: items[0].path, isDirectory: &isDir)
            base = (isDir.boolValue || items[0].hasDirectoryPath) ? items[0].lastPathComponent : items[0].deletingPathExtension().lastPathComponent
        } else {
            base = items[0].deletingLastPathComponent().lastPathComponent
        }
        add(L("finder.addTo"), #selector(compressDialog(_:)), "doc.badge.plus")
        add(LF("finder.compressTo", base + ".7z"), #selector(compress7z(_:)), "doc.zipper")
        add(LF("finder.compressTo", base + ".zip"), #selector(compressZip(_:)), "doc.zipper")

        let menu = NSMenu(title: "")
        let root = NSMenuItem(title: "YUCE ZIP", action: nil, keyEquivalent: "")
        root.image = Self.appIcon
        root.submenu = sub
        menu.addItem(root)
        return menu
    }

    // MARK: Actions

    @objc private func openArchive(_ sender: Any?) { send("open") }
    @objc private func extractDialog(_ sender: Any?) { send("extract") }
    @objc private func extractHere(_ sender: Any?) { send("extractHere") }
    @objc private func extractToFolder(_ sender: Any?) { send("extractFolder") }
    @objc private func test(_ sender: Any?) { send("test") }
    @objc private func compressDialog(_ sender: Any?) { send("compress") }
    @objc private func compress7z(_ sender: Any?) { send("compress7z") }
    @objc private func compressZip(_ sender: Any?) { send("compressZip") }

    private func send(_ action: String) {
        let items = selection
        guard !items.isEmpty else { return }
        var c = URLComponents()
        c.scheme = "yucezip"
        c.host = "run"
        c.queryItems = [URLQueryItem(name: "action", value: action)]
            + items.map { URLQueryItem(name: "p", value: $0.path) }
        guard let url = c.url else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Small copy of the archive detection used by the app.
enum FinderArchiveTypes {
    static let extensions: Set<String> = [
        "7z", "zip", "zipx", "rar", "tar", "gz", "tgz", "bz2", "tbz", "tbz2", "xz", "txz", "lzma",
        "tlz", "lz", "zst", "tzst", "z", "taz", "iso", "cab", "wim", "swm", "esd", "arj", "lzh", "lha",
        "cpio", "rpm", "deb", "xar", "jar", "war", "apk", "xpi", "msi", "chm", "vhd", "vhdx", "vmdk",
        "qcow2", "squashfs", "001",
    ]

    static func isArchive(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        if name.range(of: #"\.(7z|zip|rar)\.\d{3}$"#, options: .regularExpression) != nil { return true }
        return extensions.contains(url.pathExtension.lowercased())
    }

    static func baseName(of url: URL) -> String {
        let name = url.lastPathComponent
        let lower = name.lowercased()
        for suffix in [".tar.gz", ".tar.bz2", ".tar.xz", ".tar.zst"] where lower.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return url.deletingPathExtension().lastPathComponent
    }
}
