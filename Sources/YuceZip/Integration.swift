import AppKit
import FinderSync
import UniformTypeIdentifiers

// MARK: - Default app & Finder extension

@MainActor
enum SystemIntegration {
    static let finderExtensionID = (Bundle.main.bundleIdentifier ?? "com.bariscagriyuce.yucezip") + ".FinderSync"

    /// Archive types YUCE ZIP claims when the user makes it the default app.
    /// (ISO / DMG / JAR are left to their system handlers.)
    static let defaultTypeIDs = [
        "org.7-zip.7-zip-archive", "public.zip-archive", "com.rarlab.rar-archive", "public.tar-archive",
        "org.gnu.gnu-zip-archive", "org.gnu.gnu-zip-tar-archive", "public.bzip2-archive",
        "public.tar-bzip2-archive", "org.tukaani.xz-archive", "org.tukaani.tar-xz-archive",
        "public.z-archive", "com.microsoft.cab", "public.cpio-archive", "com.redhat.rpm-archive",
        "org.debian.deb-archive", "cx.c3.arj-archive", "cx.c3.lha-archive", "org.tukaani.lzma-archive",
        "com.bariscagriyuce.yucezip.zstd-archive", "com.bariscagriyuce.yucezip.wim-archive",
        "com.bariscagriyuce.yucezip.lzip-archive",
    ]

    static var isDefaultForZip: Bool {
        guard let app = NSWorkspace.shared.urlForApplication(toOpen: .zip) else { return false }
        return Bundle(url: app)?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    /// Returns (changed, failed).
    static func makeDefaultForArchives() async -> (Int, Int) {
        var ok = 0, failed = 0
        for id in defaultTypeIDs {
            guard let type = UTType(id), !type.isDynamic else { continue }
            do {
                try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: type)
                ok += 1
            } catch {
                failed += 1
            }
        }
        return (ok, failed)
    }

    static var isFinderExtensionEnabled: Bool { FIFinderSyncController.isExtensionEnabled }

    static func setFinderExtension(enabled: Bool) {
        runPluginKit(["-e", enabled ? "use" : "ignore", "-i", finderExtensionID])
    }

    static func showFinderExtensionSettings() {
        FIFinderSyncController.showExtensionManagementInterface()
    }

    /// Registers and enables the Finder extension the first time the app runs.
    static func registerFinderExtensionOnFirstLaunch() {
        let key = "finderExtensionAutoEnabled"
        let plugin = Bundle.main.builtInPlugInsURL?.appendingPathComponent("YuceZipFinder.appex")
        if let plugin, FileManager.default.fileExists(atPath: plugin.path) {
            runPluginKit(["-a", plugin.path])
        }
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        setFinderExtension(enabled: true)
    }

    private static func runPluginKit(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }
}

// MARK: - Quick actions from the Finder menu (yucezip://run?action=…&p=…)

@MainActor
enum QuickActions {
    static func handle(_ url: URL) {
        guard url.scheme == "yucezip",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let action = comps.queryItems?.first(where: { $0.name == "action" })?.value else { return }
        let files = (comps.queryItems ?? [])
            .filter { $0.name == "p" }
            .compactMap { $0.value }
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !files.isEmpty else { return }

        let trusted = senderIsOurExtension()
        Task {
            if !trusted {
                // A URL coming from somewhere else (e.g. a web page) needs the user's OK.
                let list = files.prefix(8).map(\.path).joined(separator: "\n")
                let answer = await Dialogs.message(window: nil, title: L("qa.confirmTitle"),
                                                   text: LF("qa.confirmMessage", action, list),
                                                   style: .warning,
                                                   buttons: [L("qa.run"), L("common.cancel")])
                guard answer == 0 else { return }
            }
            await run(action, files)
        }
    }

    /// True if the Apple Event that delivered the URL was sent by a process inside this app bundle.
    private static func senderIsOurExtension() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              let pidDesc = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr)) else {
            NSLog("YUCE ZIP quick action: no sender information")
            return false
        }
        let pid = pid_t(pidDesc.int32Value)
        var buffer = [CChar](repeating: 0, count: 4096)
        guard pid > 0, proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else {
            NSLog("YUCE ZIP quick action: sender pid %d not found", pid)
            return false
        }
        let path = String(cString: buffer)
        NSLog("YUCE ZIP quick action sender: %@", path)
        let ours = Bundle.main.bundleURL.resolvingSymlinksInPath().path + "/"
        return path.hasPrefix(ours)
    }

    private static func run(_ action: String, _ files: [URL]) async {
        let app = AppDelegate.shared!
        let archives = files.filter(ArchiveTypes.isArchive)

        switch action {
        case "open":
            archives.forEach { app.openArchive($0) }

        case "extract":
            guard let first = archives.first else { return }
            let wc = app.windowForQuickAction()
            await wc.model.open(first)
            if wc.model.isOpen { wc.model.sheet = .extract(selected: []) }

        case "extractHere", "extractFolder", "test":
            guard !archives.isEmpty else { return }
            let wc = app.windowForQuickAction()
            wc.model.quietSuccess = action != "test"
            for archive in archives {
                await wc.model.open(archive)
                guard wc.model.isOpen else { continue }
                switch action {
                case "extractHere": await wc.model.extractHere(showInFinder: false)
                case "extractFolder": await wc.model.extractHere(forceFolder: true, showInFinder: false)
                default: await wc.model.test()
                }
                wc.model.closeArchive()
            }
            wc.model.quietSuccess = false
            wc.close()

        case "compress":
            let wc = app.windowForQuickAction()
            wc.model.sheet = .compress(files: files)

        case "compress7z", "compressZip":
            let format: ArchiveFormat = action == "compress7z" ? .sevenZ : .zip
            let wc = app.windowForQuickAction()
            wc.model.quietSuccess = true
            await wc.model.compress(quickCompressOptions(files, format: format))
            wc.model.quietSuccess = false
            wc.close()

        default:
            break
        }
    }

    static func quickCompressOptions(_ files: [URL], format: ArchiveFormat) -> CompressOptions {
        let fm = FileManager.default
        let dir = files[0].deletingLastPathComponent()
        var base: String
        if files.count == 1 {
            var isDir: ObjCBool = false
            fm.fileExists(atPath: files[0].path, isDirectory: &isDir)
            base = isDir.boolValue ? files[0].lastPathComponent : files[0].deletingPathExtension().lastPathComponent
        } else {
            base = dir.lastPathComponent
        }
        if base.isEmpty || base == "/" { base = "Archive" }
        var out = dir.appendingPathComponent("\(base).\(format.fileExtension)")
        var i = 2
        while fm.fileExists(atPath: out.path) {
            out = dir.appendingPathComponent("\(base) (\(i)).\(format.fileExtension)")
            i += 1
        }
        return CompressOptions(files: files, output: out, format: format, level: Prefs.defaultLevel,
                               password: "", encryptNames: false, volumeSize: nil, excludeMacFiles: true)
    }
}
