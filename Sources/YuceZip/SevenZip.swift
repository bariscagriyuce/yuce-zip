import Foundation

// MARK: - Result of running 7zz

struct SevenZipResult {
    var exitCode: Int32
    var output: String
    var cancelled: Bool

    var succeeded: Bool { exitCode == 0 && !cancelled }
    var hasWarnings: Bool { exitCode == 1 }

    /// 7-Zip asks for a password (or the given one was wrong).
    var needsPassword: Bool {
        let o = output
        return o.contains("Enter password")
            || o.contains("Wrong password")
            || o.contains("Can not open encrypted archive")
            || o.contains("Data Error in encrypted file")
            || o.contains("CRC Failed in encrypted file")
    }

    /// The file could not be opened as an archive at all.
    var notArchive: Bool {
        output.contains("Cannot open the file as archive") || output.contains("Can not open the file as archive")
    }

    /// Lines worth showing to the user (errors / warnings).
    var errorSummary: String {
        let lines = output
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                guard !line.isEmpty else { return false }
                let l = line.lowercased()
                return l.contains("error") || l.contains("warning") || l.contains("cannot")
                    || l.contains("can not") || l.contains("wrong") || l.contains("unsupported")
                    || l.contains("failed") || l.contains("denied") || l.contains("no such file")
            }
        var seen = Set<String>()
        let unique = lines.filter { seen.insert($0).inserted }
        return unique.prefix(30).joined(separator: "\n")
    }
}

// MARK: - Process wrapper

/// Runs the bundled `7zz` executable.
final class SevenZipProcess {
    private let process = Process()
    private let lock = NSLock()
    private var buffer = Data()
    private var wasCancelled = false

    /// Location of the 7zz binary: inside the app bundle, falling back to Homebrew for development.
    static var executableURL: URL? {
        var candidates: [URL] = []
        if let res = Bundle.main.resourceURL { candidates.append(res.appendingPathComponent("7zz")) }
        if let exe = Bundle.main.executableURL?.deletingLastPathComponent() {
            candidates.append(exe.appendingPathComponent("7zz"))
        }
        candidates += [
            URL(fileURLWithPath: "/opt/homebrew/bin/7zz"),
            URL(fileURLWithPath: "/usr/local/bin/7zz"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static var isAvailable: Bool { executableURL != nil }

    /// Runs 7zz with the given arguments and reports progress (0…1).
    func run(_ arguments: [String],
             currentDirectory: URL? = nil,
             onProgress: ((Double) -> Void)? = nil) async -> SevenZipResult {
        guard let exe = Self.executableURL else {
            return SevenZipResult(exitCode: -1, output: L("error.engine"), cancelled: false)
        }

        process.executableURL = exe
        process.arguments = arguments
        if let dir = currentDirectory { process.currentDirectoryURL = dir }

        var env = ProcessInfo.processInfo.environment
        env["LANG"] = "en_US.UTF-8"
        env["LC_ALL"] = "en_US.UTF-8"
        process.environment = env

        // No stdin: if 7-Zip asks for a password it receives EOF and stops instead of hanging.
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let percentRegex = try? NSRegularExpression(pattern: "(\\d{1,3})%")

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else { return }
            self.lock.lock()
            self.buffer.append(data)
            self.lock.unlock()

            if let onProgress, let regex = percentRegex,
               let chunk = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                let range = NSRange(chunk.startIndex..., in: chunk)
                if let last = regex.matches(in: chunk, range: range).last,
                   let r = Range(last.range(at: 1), in: chunk),
                   let value = Double(chunk[r]) {
                    onProgress(min(max(value / 100.0, 0), 1))
                }
            }
        }

        return await withCheckedContinuation { continuation in
            process.terminationHandler = { [weak self] proc in
                guard let self else { return }
                pipe.fileHandleForReading.readabilityHandler = nil
                let rest = pipe.fileHandleForReading.readDataToEndOfFile()
                self.lock.lock()
                self.buffer.append(rest)
                let data = self.buffer
                let cancelled = self.wasCancelled
                self.lock.unlock()
                let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
                continuation.resume(returning: SevenZipResult(exitCode: proc.terminationStatus,
                                                              output: text,
                                                              cancelled: cancelled))
            }
            do {
                try process.run()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                process.terminationHandler = nil
                continuation.resume(returning: SevenZipResult(exitCode: -1,
                                                              output: error.localizedDescription,
                                                              cancelled: false))
            }
        }
    }

    func cancel() {
        lock.lock()
        wasCancelled = true
        lock.unlock()
        if process.isRunning { process.interrupt() }
        let p = process
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
            if p.isRunning { p.terminate() }
        }
    }

    /// Version of the bundled engine, e.g. "26.06".
    static let engineVersion: String = {
        guard let exe = executableURL else { return "?" }
        let p = Process()
        p.executableURL = exe
        p.arguments = []
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return "?" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        if let r = text.range(of: #"7-Zip \(z\) ([0-9.]+)"#, options: .regularExpression) {
            return text[r].replacingOccurrences(of: "7-Zip (z) ", with: "")
        }
        return "?"
    }()
}

// MARK: - Archive listing

struct ArchiveEntry {
    var path: String
    var isDirectory: Bool
    var size: Int64
    var packedSize: Int64
    var modified: Date?
    var method: String
    var encrypted: Bool
}

struct ArchiveInfo {
    var type: String = ""
    var physicalSize: Int64 = 0
    var method: String = ""
    var solid: Bool = false
    var headersEncrypted: Bool = false
}

enum ArchiveListing {
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    /// Parses the output of `7zz l -slt`.
    static func parse(_ output: String) -> (ArchiveInfo, [ArchiveEntry]) {
        var info = ArchiveInfo()
        var entries: [ArchiveEntry] = []

        let normalized = output.replacingOccurrences(of: "\r\n", with: "\n")
        // The archive header block is between "--" and "----------"; entries follow.
        let headerAndBody: (String, String)
        if let sep = normalized.range(of: "\n----------\n") {
            headerAndBody = (String(normalized[..<sep.lowerBound]), String(normalized[sep.upperBound...]))
        } else {
            headerAndBody = (normalized, "")
        }

        // Header
        var headerStarted = false
        for line in headerAndBody.0.components(separatedBy: "\n") {
            if line == "--" { headerStarted = true; continue }
            guard headerStarted, let (k, v) = keyValue(line) else { continue }
            switch k {
            case "Type": if info.type.isEmpty { info.type = v }
            case "Physical Size": info.physicalSize = Int64(v) ?? 0
            case "Method": info.method = v
            case "Solid": info.solid = (v == "+")
            default: break
            }
        }

        // Entries
        for block in headerAndBody.1.components(separatedBy: "\n\n") {
            var dict: [String: String] = [:]
            for line in block.components(separatedBy: "\n") {
                if let (k, v) = keyValue(line), dict[k] == nil { dict[k] = v }
            }
            guard let rawPath = dict["Path"], !rawPath.isEmpty else { continue }
            let attrs = dict["Attributes"] ?? ""
            let isDir = dict["Folder"] == "+" || attrs.hasPrefix("D")
            var modified: Date? = nil
            if let m = dict["Modified"], m.count >= 19 {
                modified = dateFormatter.date(from: String(m.prefix(19)))
            }
            entries.append(ArchiveEntry(
                path: rawPath.replacingOccurrences(of: "\\", with: "/"),
                isDirectory: isDir,
                size: Int64(dict["Size"] ?? "") ?? 0,
                packedSize: Int64(dict["Packed Size"] ?? "") ?? 0,
                modified: modified,
                method: dict["Method"] ?? "",
                encrypted: dict["Encrypted"] == "+"
            ))
        }
        return (info, entries)
    }

    private static func keyValue(_ line: String) -> (String, String)? {
        guard let r = line.range(of: " = ") else {
            if line.hasSuffix(" =") { return (String(line.dropLast(2)), "") }
            return nil
        }
        return (String(line[..<r.lowerBound]), String(line[r.upperBound...]))
    }
}

// MARK: - Formats

enum ArchiveFormat: String, CaseIterable, Identifiable {
    case sevenZ = "7z"
    case zip
    case tar
    case gzip
    case bzip2
    case xz
    case wim

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sevenZ: return "7z"
        case .zip: return "ZIP"
        case .tar: return "TAR"
        case .gzip: return "TAR.GZ (gzip)"
        case .bzip2: return "TAR.BZ2 (bzip2)"
        case .xz: return "TAR.XZ (xz)"
        case .wim: return "WIM"
        }
    }

    /// The `-t` switch value.
    var typeSwitch: String {
        switch self {
        case .sevenZ: return "7z"
        case .zip: return "zip"
        case .tar: return "tar"
        case .gzip: return "gzip"
        case .bzip2: return "bzip2"
        case .xz: return "xz"
        case .wim: return "wim"
        }
    }

    /// Single-stream compressors need a tar container for several files / folders.
    var isStreamCompressor: Bool { [.gzip, .bzip2, .xz].contains(self) }

    /// Extension of the produced file. A single plain file compressed with gzip/bzip2/xz is not wrapped in tar.
    func fileExtension(singlePlainFile: Bool) -> String {
        if singlePlainFile && isStreamCompressor { return typeSwitch == "gzip" ? "gz" : (typeSwitch == "bzip2" ? "bz2" : "xz") }
        return fileExtension
    }

    var fileExtension: String {
        switch self {
        case .sevenZ: return "7z"
        case .zip: return "zip"
        case .tar: return "tar"
        case .gzip: return "tar.gz"
        case .bzip2: return "tar.bz2"
        case .xz: return "tar.xz"
        case .wim: return "wim"
        }
    }

    var supportsEncryption: Bool { self == .sevenZ || self == .zip }
    var supportsHeaderEncryption: Bool { self == .sevenZ }
    var supportsLevel: Bool { self != .tar && self != .wim }
}

enum ArchiveTypes {
    /// Extensions that YUCE ZIP opens as archives.
    static let extensions: Set<String> = [
        "7z", "zip", "zipx", "rar", "tar", "gz", "tgz", "bz2", "tbz", "tbz2", "xz", "txz", "lzma",
        "tlz", "lz", "zst", "tzst", "z", "taz", "iso", "img", "dmg", "cab", "wim", "swm", "esd",
        "arj", "lzh", "lha", "cpio", "rpm", "deb", "xar", "pkg", "jar", "war", "ear", "apk", "xpi",
        "msi", "chm", "vhd", "vhdx", "vmdk", "qcow", "qcow2", "squashfs", "udf", "hfs", "apfs",
        "cramfs", "ext", "fat", "ntfs", "mbr", "gpt", "lzh", "uefi", "ihex", "nsis", "001",
    ]

    static func isArchive(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".tar.gz") || name.hasSuffix(".tar.bz2") || name.hasSuffix(".tar.xz") || name.hasSuffix(".tar.zst") {
            return true
        }
        if name.range(of: #"\.(7z|zip|rar|r|z)\.?\d{2,3}$"#, options: .regularExpression) != nil { return true }
        if name.range(of: #"\.part\d+\.rar$"#, options: .regularExpression) != nil { return true }
        return extensions.contains(url.pathExtension.lowercased())
    }

    /// Archive types 7-Zip can modify (add / delete items).
    static let writableTypes: Set<String> = ["7z", "zip", "tar", "wim"]

    /// Removes archive extensions to get a folder name, e.g. "photos.tar.gz" → "photos".
    static func baseName(of url: URL) -> String {
        var name = url.lastPathComponent
        let lower = name.lowercased()
        for suffix in [".tar.gz", ".tar.bz2", ".tar.xz", ".tar.zst"] where lower.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        if let r = name.range(of: #"\.(part\d+\.rar|7z\.\d+|zip\.\d+)$"#, options: [.regularExpression, .caseInsensitive]) {
            return String(name[..<r.lowerBound])
        }
        if !url.pathExtension.isEmpty { name = url.deletingPathExtension().lastPathComponent }
        return name
    }
}

// MARK: - Helpers

enum Format {
    static func bytes(_ value: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: value)
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return "" }
        let f = DateFormatter()
        f.locale = L10n.shared.locale
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}
