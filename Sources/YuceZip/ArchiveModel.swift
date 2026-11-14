import AppKit
import SwiftUI

// MARK: - Preferences

enum Prefs {
    private static let d = UserDefaults.standard

    static var defaultFormat: ArchiveFormat {
        get { ArchiveFormat(rawValue: d.string(forKey: "defaultFormat") ?? "") ?? .sevenZ }
        set { d.set(newValue.rawValue, forKey: "defaultFormat") }
    }
    static var defaultLevel: Int {
        get { d.object(forKey: "defaultLevel") as? Int ?? 5 }
        set { d.set(newValue, forKey: "defaultLevel") }
    }
    static var showAfterExtract: Bool {
        get { d.object(forKey: "showAfterExtract") as? Bool ?? true }
        set { d.set(newValue, forKey: "showAfterExtract") }
    }
    static var autoCheckUpdates: Bool {
        get { d.object(forKey: "autoCheckUpdates") as? Bool ?? true }
        set { d.set(newValue, forKey: "autoCheckUpdates") }
    }
    static var lastUpdateCheck: Date? {
        get { d.object(forKey: "lastUpdateCheck") as? Date }
        set { d.set(newValue, forKey: "lastUpdateCheck") }
    }
}

// MARK: - Tree node

final class ArchiveNode: Identifiable {
    let id: String          // full path inside the archive
    let name: String
    var isDirectory: Bool
    var size: Int64 = 0
    var packedSize: Int64 = 0
    var modified: Date?
    var method: String = ""
    var encrypted = false
    var explicitEntry = false   // true if the archive contains an entry for it
    weak var parent: ArchiveNode?
    var children: [String: ArchiveNode] = [:]

    init(path: String, name: String, isDirectory: Bool) {
        self.id = path
        self.name = name
        self.isDirectory = isDirectory
    }

    var path: String { id }

    // Sort keys (folders first)
    var sortName: String { (isDirectory ? "0" : "1") + name.lowercased() }
    var sortSize: Int64 { size }
    var sortPacked: Int64 { packedSize }
    var sortDate: Date { modified ?? .distantPast }

    var childList: [ArchiveNode] { Array(children.values) }

    /// Path components from the root to this node.
    var ancestry: [ArchiveNode] {
        var list: [ArchiveNode] = []
        var n: ArchiveNode? = self
        while let cur = n { list.insert(cur, at: 0); n = cur.parent }
        return list
    }

    func countAll() -> (files: Int, folders: Int, size: Int64) {
        var files = 0, folders = 0
        var size: Int64 = 0
        for c in children.values {
            if c.isDirectory {
                folders += 1
                let r = c.countAll()
                files += r.files; folders += r.folders; size += r.size
            } else {
                files += 1; size += c.size
            }
        }
        return (files, folders, size)
    }

    @discardableResult
    func computeFolderSizes() -> (Int64, Int64) {
        guard isDirectory else { return (size, packedSize) }
        var s: Int64 = 0, p: Int64 = 0
        for c in children.values {
            let (cs, cp) = c.computeFolderSizes()
            s += cs; p += cp
        }
        size = s; packedSize = p
        return (s, p)
    }

    static func buildTree(from entries: [ArchiveEntry], archiveName: String) -> ArchiveNode {
        let root = ArchiveNode(path: "", name: archiveName, isDirectory: true)
        for e in entries {
            let comps = e.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard !comps.isEmpty else { continue }
            var node = root
            var accumulated = ""
            for (i, comp) in comps.enumerated() {
                accumulated = accumulated.isEmpty ? comp : accumulated + "/" + comp
                let isLast = i == comps.count - 1
                if let existing = node.children[comp] {
                    node = existing
                } else {
                    let n = ArchiveNode(path: accumulated, name: comp, isDirectory: isLast ? e.isDirectory : true)
                    n.parent = node
                    node.children[comp] = n
                    node = n
                }
                if isLast {
                    node.isDirectory = e.isDirectory || !node.children.isEmpty
                    node.explicitEntry = true
                    node.modified = e.modified
                    node.method = e.method
                    node.encrypted = e.encrypted
                    if !e.isDirectory { node.size = e.size; node.packedSize = e.packedSize }
                }
            }
        }
        root.computeFolderSizes()
        return root
    }
}

// MARK: - Operation overlay state

struct OperationState {
    var title: String
    var progress: Double?      // nil = indeterminate
    var detail: String = ""
}

struct ExtractOptions {
    var destination: URL
    var paths: [String]        // empty = everything
    var overwrite: String      // -aoa, -aos, -aou, -aot
    var showInFinder: Bool
}

struct CompressOptions {
    var files: [URL]
    var output: URL
    var format: ArchiveFormat
    var level: Int
    var password: String
    var encryptNames: Bool
    var volumeSize: String?    // e.g. "100m"
    var excludeMacFiles: Bool
}

enum ActiveSheet: Identifiable {
    case extract(selected: [String])
    case compress(files: [URL])
    case info

    var id: String {
        switch self {
        case .extract: return "extract"
        case .compress: return "compress"
        case .info: return "info"
        }
    }
}

// MARK: - View model for one window

@MainActor
final class ArchiveViewModel: ObservableObject {
    @Published var archiveURL: URL?
    @Published var root: ArchiveNode?
    @Published var currentFolder: ArchiveNode?
    @Published var info = ArchiveInfo()
    @Published var selection = Set<String>()
    @Published var sortOrder: [KeyPathComparator<ArchiveNode>] = [KeyPathComparator(\ArchiveNode.sortName)]
    @Published var operation: OperationState?
    @Published var sheet: ActiveSheet?
    @Published var hasEncryptedEntries = false

    var password: String?
    weak var window: NSWindow?
    /// When true, successful operations don't show a "Done" alert (used by Finder quick actions).
    var quietSuccess = false
    private var runningProcess: SevenZipProcess?
    private var stats: (files: Int, folders: Int, size: Int64) = (0, 0, 0)

    var isOpen: Bool { root != nil }
    var isBusy: Bool { operation != nil }
    var archiveName: String { archiveURL?.lastPathComponent ?? "" }

    var isWritable: Bool {
        guard let url = archiveURL else { return false }
        let t = info.type.lowercased()
        guard ArchiveTypes.writableTypes.contains(t) else { return false }
        // Multi-volume archives can't be updated.
        if url.lastPathComponent.range(of: #"\.\d{3}$"#, options: .regularExpression) != nil { return false }
        return FileManager.default.isWritableFile(atPath: url.path)
    }

    var rows: [ArchiveNode] {
        guard let folder = currentFolder else { return [] }
        var list = folder.childList
        list.sort { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            for c in sortOrder {
                switch c.compare(a, b) {
                case .orderedAscending: return true
                case .orderedDescending: return false
                case .orderedSame: continue
                }
            }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        return list
    }

    var statusText: String {
        let count = currentFolder?.children.count ?? 0
        if selection.isEmpty { return LF("status.items", count) }
        return LF("status.selected", selection.count, count)
    }

    var summaryText: String {
        LF("status.summary", info.type.isEmpty ? "?" : info.type, stats.files, stats.folders, Format.bytes(stats.size))
    }

    var totalUnpacked: Int64 { stats.size }
    var fileCount: Int { stats.files }
    var folderCount: Int { stats.folders }

    // MARK: Navigation

    func enter(_ node: ArchiveNode) {
        guard node.isDirectory else { return }
        currentFolder = node
        selection = []
    }

    func goUp() {
        if let parent = currentFolder?.parent {
            let previous = currentFolder?.id
            currentFolder = parent
            selection = previous.map { [$0] } ?? []
        }
    }

    func node(for id: String) -> ArchiveNode? {
        guard let root else { return nil }
        if id.isEmpty { return root }
        var node = root
        for comp in id.split(separator: "/").map(String.init) {
            guard let next = node.children[comp] else { return nil }
            node = next
        }
        return node
    }

    func closeArchive() {
        archiveURL = nil
        root = nil
        currentFolder = nil
        selection = []
        password = nil
        info = ArchiveInfo()
        window?.title = "YUCE ZIP"
        window?.representedURL = nil
    }

    // MARK: Running 7-Zip

    private func run(_ title: String, _ args: [String], cwd: URL? = nil,
                     progressRange: ClosedRange<Double> = 0...1) async -> SevenZipResult {
        let proc = SevenZipProcess()
        runningProcess = proc
        if operation == nil { operation = OperationState(title: title, progress: nil) }
        operation?.title = title
        let result = await proc.run(args, currentDirectory: cwd) { [weak self] value in
            Task { @MainActor in
                guard let self, self.operation != nil else { return }
                let v = progressRange.lowerBound + value * (progressRange.upperBound - progressRange.lowerBound)
                self.operation?.progress = v
            }
        }
        runningProcess = nil
        return result
    }

    func cancelOperation() {
        runningProcess?.cancel()
    }

    private var passwordArgs: [String] {
        if let pw = password, !pw.isEmpty { return ["-p" + pw] }
        return []
    }

    /// Asks for the password. Returns false if the user cancelled.
    private func askPassword(wrong: Bool) async -> Bool {
        let saved = operation
        operation = nil
        guard let pw = await Dialogs.askPassword(window: window, archiveName: archiveName, wrong: wrong) else {
            operation = saved
            return false
        }
        password = pw
        operation = saved
        return true
    }

    // MARK: Open

    func open(_ url: URL) async {
        guard SevenZipProcess.isAvailable else {
            await Dialogs.message(window: window, title: L("result.title.error"), text: L("error.engine"), style: .critical)
            return
        }
        let previousPassword = archiveURL == url ? password : nil
        password = previousPassword
        operation = OperationState(title: L("progress.opening"), progress: nil, detail: url.lastPathComponent)
        defer { operation = nil }

        var wrong = false
        while true {
            let result = await run(L("progress.opening"), ["l", "-slt", "-sccUTF-8"] + passwordArgs + ["--", url.path])
            if result.cancelled { return }
            if result.needsPassword {
                if !(await askPassword(wrong: wrong || password != nil)) { return }
                wrong = true
                continue
            }
            let (info, entries) = ArchiveListing.parse(result.output)
            if result.exitCode >= 2 || (info.type.isEmpty && entries.isEmpty) {
                let detail = result.notArchive ? L("error.notArchive") : result.errorSummary
                await Dialogs.message(window: window, title: LF("error.open", url.lastPathComponent),
                                      text: detail.isEmpty ? L("error.notArchive") : detail, style: .warning)
                return
            }
            apply(url: url, info: info, entries: entries)
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            return
        }
    }

    private func apply(url: URL, info: ArchiveInfo, entries: [ArchiveEntry]) {
        let previousPath = archiveURL == url ? currentFolder?.id : nil
        archiveURL = url
        self.info = info
        let tree = ArchiveNode.buildTree(from: entries, archiveName: url.lastPathComponent)
        root = tree
        stats = tree.countAll()
        hasEncryptedEntries = entries.contains { $0.encrypted }
        selection = []
        if let p = previousPath, let n = node(for: p), n.isDirectory {
            currentFolder = n
        } else {
            // Skip a lone wrapper folder? No — show the real root like 7-Zip does.
            currentFolder = tree
        }
        window?.title = url.lastPathComponent
        window?.representedURL = url
    }

    func reload() async {
        guard let url = archiveURL else { return }
        await open(url)
    }

    // MARK: Extract

    func defaultExtractDestination() -> URL {
        guard let url = archiveURL else { return FileManager.default.homeDirectoryForCurrentUser }
        let parent = url.deletingLastPathComponent()
        if FileManager.default.isWritableFile(atPath: parent.path) { return parent }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? parent
    }

    func extract(_ options: ExtractOptions) async {
        guard let url = archiveURL else { return }
        if hasEncryptedEntries && (password ?? "").isEmpty {
            if !(await askPassword(wrong: false)) { return }
        }
        try? FileManager.default.createDirectory(at: options.destination, withIntermediateDirectories: true)
        operation = OperationState(title: L("progress.extracting"), progress: 0, detail: url.lastPathComponent)
        defer { operation = nil }

        var wrong = false
        while true {
            let args = ["x", "-bsp1", "-bso0", "-y", options.overwrite, "-o" + options.destination.path]
                + passwordArgs + ["--", url.path] + options.paths
            let result = await run(L("progress.extracting"), args)
            if result.cancelled {
                await Dialogs.message(window: window, title: L("result.title.warning"), text: L("result.cancelled"), style: .informational)
                return
            }
            if result.needsPassword && !result.succeeded {
                if !(await askPassword(wrong: wrong || password != nil)) { return }
                wrong = true
                // Overwrite broken partial files on retry.
                return await extract(ExtractOptions(destination: options.destination, paths: options.paths,
                                                    overwrite: "-aoa", showInFinder: options.showInFinder))
            }
            await report(result, success: LF("result.extracted", options.destination.path))
            if result.exitCode <= 1 && options.showInFinder {
                NSWorkspace.shared.activateFileViewerSelecting([options.destination])
            }
            return
        }
    }

    /// "Extract Here": into the archive's folder; a new folder is created unless the archive has a single top-level item.
    func extractHere(forceFolder: Bool = false, showInFinder: Bool? = nil) async {
        guard let url = archiveURL, let root else { return }
        let parent = defaultExtractDestination()
        var dest = parent
        if forceFolder || root.children.count != 1 {
            dest = parent.appendingPathComponent(ArchiveTypes.baseName(of: url), isDirectory: true)
        }
        await extract(ExtractOptions(destination: dest, paths: [], overwrite: "-aou", showInFinder: showInFinder ?? Prefs.showAfterExtract))
    }

    // MARK: Test

    func test() async {
        guard let url = archiveURL else { return }
        if hasEncryptedEntries && (password ?? "").isEmpty {
            if !(await askPassword(wrong: false)) { return }
        }
        operation = OperationState(title: L("progress.testing"), progress: 0, detail: url.lastPathComponent)
        defer { operation = nil }
        var wrong = false
        while true {
            let result = await run(L("progress.testing"), ["t", "-bsp1", "-bso1"] + passwordArgs + ["--", url.path])
            if result.cancelled { return }
            if result.needsPassword && !result.succeeded {
                if !(await askPassword(wrong: wrong || password != nil)) { return }
                wrong = true
                continue
            }
            await report(result, success: L("result.testOK"))
            return
        }
    }

    // MARK: Delete

    func deleteSelected() async {
        guard let url = archiveURL, isWritable else { return }
        let paths = Array(selection)
        guard !paths.isEmpty else { return }
        let answer = await Dialogs.message(window: window, title: L("delete.title"),
                                           text: LF("delete.message", paths.count), style: .warning,
                                           buttons: [L("delete.button"), L("common.cancel")])
        guard answer == 0 else { return }
        operation = OperationState(title: L("progress.deleting"), progress: 0)
        let result = await run(L("progress.deleting"), ["d", "-bsp1", "-bso0"] + passwordArgs + ["--", url.path] + paths)
        operation = nil
        if !result.succeeded {
            await report(result, success: L("result.deleted"))
        }
        await reload()
    }

    // MARK: Add files to the open archive

    func addFiles(_ files: [URL], confirm: Bool = true) async {
        guard let url = archiveURL, isWritable, !files.isEmpty else { return }
        if confirm {
            let answer = await Dialogs.message(window: window, title: L("add.title"),
                                               text: LF("add.message", files.count, url.lastPathComponent),
                                               style: .informational,
                                               buttons: [L("add.button"), L("common.cancel")])
            guard answer == 0 else { return }
        }
        let (cwd, names) = Self.relativeArguments(for: files)
        var args = ["a", "-bsp1", "-bso0"] + passwordArgs
        if info.type == "7z", password != nil, !(password ?? "").isEmpty, hasEncryptedEntries { args.append("-mhe=on") }
        if info.type.lowercased() == "zip" { args += ["-mcu=on"] }
        args += ["-xr!.DS_Store", "-xr!._*", "-xr!__MACOSX", "--", url.path] + names
        operation = OperationState(title: L("progress.adding"), progress: 0)
        let result = await run(L("progress.adding"), args, cwd: cwd)
        operation = nil
        if !result.succeeded {
            await report(result, success: L("result.added"))
        }
        await reload()
    }

    // MARK: Compress new archive

    static func relativeArguments(for files: [URL]) -> (URL?, [String]) {
        let parents = Set(files.map { $0.deletingLastPathComponent().standardizedFileURL.path })
        if parents.count == 1, let first = files.first {
            return (first.deletingLastPathComponent(), files.map { $0.lastPathComponent })
        }
        return (nil, files.map { $0.path })
    }

    func compress(_ o: CompressOptions) async {
        operation = OperationState(title: L("progress.compressing"), progress: 0, detail: o.output.lastPathComponent)
        defer { operation = nil }

        let (cwd, names) = Self.relativeArguments(for: o.files)
        let excludes = o.excludeMacFiles ? ["-xr!.DS_Store", "-xr!._*", "-xr!__MACOSX"] : []
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let singlePlainFile = o.files.count == 1 && fm.fileExists(atPath: o.files[0].path, isDirectory: &isDir) && !isDir.boolValue

        var result: SevenZipResult
        if o.format.isStreamCompressor && !singlePlainFile {
            // Two steps: tar, then compress the tar.
            let tmpDir = fm.temporaryDirectory.appendingPathComponent("YuceZip-\(UUID().uuidString)", isDirectory: true)
            try? fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: tmpDir) }
            var tarName = o.output.lastPathComponent
            for s in [".gz", ".bz2", ".xz", ".tgz", ".tbz2", ".txz"] where tarName.lowercased().hasSuffix(s) {
                tarName = String(tarName.dropLast(s.count))
            }
            if !tarName.lowercased().hasSuffix(".tar") { tarName += ".tar" }
            let tarURL = tmpDir.appendingPathComponent(tarName)
            result = await run(L("progress.compressing"), ["a", "-ttar", "-bsp1", "-bso0"] + excludes + ["--", tarURL.path] + names,
                               cwd: cwd, progressRange: 0...0.3)
            if result.succeeded {
                var args = ["a", "-t" + o.format.typeSwitch, "-mx=\(o.level)", "-bsp1", "-bso0"]
                if let v = o.volumeSize { args.append("-v" + v) }
                result = await run(L("progress.compressing"), args + ["--", o.output.path, tarURL.path],
                                   progressRange: 0.3...1)
            }
        } else {
            var args = ["a", "-t" + o.format.typeSwitch, "-bsp1", "-bso0"]
            if o.format.supportsLevel { args.append("-mx=\(o.level)") }
            if o.format.supportsEncryption && !o.password.isEmpty {
                args.append("-p" + o.password)
                if o.format == .zip { args.append("-mem=AES256") }
                if o.format == .sevenZ && o.encryptNames { args.append("-mhe=on") }
            }
            if o.format == .zip { args.append("-mcu=on") }
            if let v = o.volumeSize { args.append("-v" + v) }
            args += excludes
            result = await run(L("progress.compressing"), args + ["--", o.output.path] + names, cwd: cwd)
        }

        if result.cancelled {
            // Remove partial output.
            try? fm.removeItem(at: o.output)
            await Dialogs.message(window: window, title: L("result.title.warning"), text: L("result.cancelled"), style: .informational)
            return
        }
        let ok = result.exitCode <= 1
        let choice = await report(result, success: LF("result.created", o.output.path),
                                  extraButton: ok ? L("common.showInFinder") : nil)
        if ok && choice == 1 {
            var target = o.output
            if !fm.fileExists(atPath: target.path) {
                target = URL(fileURLWithPath: o.output.path + ".001")
            }
            NSWorkspace.shared.activateFileViewerSelecting([target])
        }
    }

    // MARK: Open a file inside the archive

    func openEntry(_ node: ArchiveNode) async {
        if node.isDirectory { enter(node); return }
        guard let url = archiveURL else { return }
        if node.encrypted && (password ?? "").isEmpty {
            if !(await askPassword(wrong: false)) { return }
        }
        let tmp = TempFiles.newDirectory()
        operation = OperationState(title: L("progress.extracting"), progress: 0, detail: node.name)
        var wrong = false
        while true {
            let result = await run(L("progress.extracting"),
                                   ["e", "-bsp1", "-bso0", "-y", "-aoa", "-o" + tmp.path] + passwordArgs + ["--", url.path, node.path])
            if result.cancelled { operation = nil; return }
            if result.needsPassword && !result.succeeded {
                if !(await askPassword(wrong: wrong || password != nil)) { operation = nil; return }
                wrong = true
                continue
            }
            operation = nil
            let file = tmp.appendingPathComponent(node.name)
            guard result.exitCode <= 1, FileManager.default.fileExists(atPath: file.path) else {
                await report(result, success: "")
                return
            }
            if ArchiveTypes.isArchive(file) {
                AppDelegate.shared.openArchive(file, forceNewWindow: true)
            } else {
                NSWorkspace.shared.open(file)
            }
            return
        }
    }

    // MARK: Reporting

    @discardableResult
    private func report(_ result: SevenZipResult, success: String, extraButton: String? = nil) async -> Int {
        if result.succeeded && quietSuccess {
            return 0
        }
        if result.succeeded {
            var buttons = [L("common.ok")]
            if let extraButton { buttons.append(extraButton) }
            return await Dialogs.message(window: window, title: L("result.title.ok"), text: success,
                                         style: .informational, buttons: buttons)
        } else if result.hasWarnings {
            var buttons = [L("common.ok")]
            if let extraButton { buttons.append(extraButton) }
            return await Dialogs.message(window: window, title: L("result.title.warning"),
                                         text: success, style: .warning, buttons: buttons,
                                         details: result.errorSummary)
        } else {
            let summary = result.errorSummary
            return await Dialogs.message(window: window, title: L("result.title.error"),
                                         text: summary.isEmpty ? L("error.notArchive") : summary,
                                         style: .critical)
        }
    }
}

// MARK: - Temporary files

enum TempFiles {
    static let base: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("YuceZip-open-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)

    static func newDirectory() -> URL {
        let dir = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func cleanUp() {
        try? FileManager.default.removeItem(at: base)
    }
}

// MARK: - Dialogs (NSAlert based, shown as sheets)

@MainActor
enum Dialogs {
    @discardableResult
    static func message(window: NSWindow?, title: String, text: String, style: NSAlert.Style,
                        buttons: [String] = [], details: String? = nil) async -> Int {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.alertStyle = style
        let titles = buttons.isEmpty ? [L("common.ok")] : buttons
        for t in titles { alert.addButton(withTitle: t) }
        if let details, !details.isEmpty {
            alert.accessoryView = scrollingText(details)
        }
        let response = await present(alert, window: window)
        return response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
    }

    static func askPassword(window: NSWindow?, archiveName: String, wrong: Bool) async -> String? {
        let alert = NSAlert()
        alert.messageText = L("pw.title")
        alert.informativeText = (wrong ? L("pw.wrong") + "\n\n" : "") + LF("pw.message", archiveName)
        alert.alertStyle = wrong ? .warning : .informational
        alert.icon = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)
        alert.addButton(withTitle: L("common.ok"))
        alert.addButton(withTitle: L("common.cancel"))

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 50))
        let secure = NSSecureTextField(frame: NSRect(x: 0, y: 26, width: 260, height: 24))
        let plain = NSTextField(frame: secure.frame)
        secure.placeholderString = L("pw.placeholder")
        plain.placeholderString = L("pw.placeholder")
        plain.isHidden = true
        let toggle = ToggleTarget(secure: secure, plain: plain)
        let check = NSButton(checkboxWithTitle: L("pw.show"), target: toggle, action: #selector(ToggleTarget.toggle(_:)))
        check.frame = NSRect(x: 0, y: 0, width: 260, height: 20)
        container.addSubview(secure)
        container.addSubview(plain)
        container.addSubview(check)
        alert.accessoryView = container
        alert.window.initialFirstResponder = secure

        let response = await present(alert, window: window, firstResponder: secure)
        _ = toggle // keep alive
        guard response == .alertFirstButtonReturn else { return nil }
        return plain.isHidden ? secure.stringValue : plain.stringValue
    }

    @MainActor private final class ToggleTarget: NSObject {
        let secure: NSSecureTextField
        let plain: NSTextField
        init(secure: NSSecureTextField, plain: NSTextField) { self.secure = secure; self.plain = plain }
        @objc func toggle(_ sender: NSButton) {
            if sender.state == .on {
                plain.stringValue = secure.stringValue
                plain.isHidden = false; secure.isHidden = true
            } else {
                secure.stringValue = plain.stringValue
                secure.isHidden = false; plain.isHidden = true
            }
        }
    }

    private static func present(_ alert: NSAlert, window: NSWindow?, firstResponder: NSView? = nil) async -> NSApplication.ModalResponse {
        if let window, window.isVisible, window.attachedSheet == nil {
            return await withCheckedContinuation { cont in
                alert.beginSheetModal(for: window) { cont.resume(returning: $0) }
                if let firstResponder { alert.window.makeFirstResponder(firstResponder) }
            }
        }
        if let firstResponder { DispatchQueue.main.async { alert.window.makeFirstResponder(firstResponder) } }
        return alert.runModal()
    }

    static func scrollingText(_ text: String) -> NSView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 380, height: 140))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let tv = NSTextView(frame: scroll.bounds)
        tv.isEditable = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        tv.string = text
        tv.autoresizingMask = [.width]
        scroll.documentView = tv
        return scroll
    }
}
