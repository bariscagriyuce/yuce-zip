import SwiftUI
import AppKit

// MARK: - Extract

struct ExtractSheet: View {
    @ObservedObject var model: ArchiveViewModel
    let selected: [String]

    @Environment(\.dismiss) private var dismiss
    @State private var destination: URL = FileManager.default.homeDirectoryForCurrentUser
    @State private var newFolder = true
    @State private var overwrite = "-aoa"
    @State private var selectedOnly = false
    @State private var showInFinder = Prefs.showAfterExtract
    @State private var password = ""

    private var finalDestination: URL {
        guard newFolder, let url = model.archiveURL else { return destination }
        return destination.appendingPathComponent(ArchiveTypes.baseName(of: url), isDirectory: true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.doc.fill").font(.largeTitle).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading) {
                    Text(L("extract.title")).font(.title2.bold())
                    Text(model.archiveName).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }

            Form {
                LabeledContent(L("extract.destination")) {
                    HStack {
                        Text(destination.path)
                            .lineLimit(1).truncationMode(.head)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .help(destination.path)
                        Button(L("common.choose")) { chooseFolder() }
                    }
                }
                Toggle(L("extract.newFolder"), isOn: $newFolder)
                Text(finalDestination.path)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)

                Picker(L("extract.overwrite"), selection: $overwrite) {
                    Text(L("ow.overwrite")).tag("-aoa")
                    Text(L("ow.skip")).tag("-aos")
                    Text(L("ow.rename")).tag("-aou")
                    Text(L("ow.renameExisting")).tag("-aot")
                }

                if !selected.isEmpty {
                    Toggle(LF("extract.selectedOnly", selected.count), isOn: $selectedOnly)
                }

                if model.hasEncryptedEntries {
                    SecureField(L("extract.password"), text: $password)
                }

                Toggle(L("extract.openAfter"), isOn: $showInFinder)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button(L("common.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L("extract.start")) { start() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 540)
        .onAppear {
            destination = model.defaultExtractDestination()
            selectedOnly = !selected.isEmpty
            password = model.password ?? ""
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = destination
        panel.prompt = L("common.choose").replacingOccurrences(of: "…", with: "")
        if panel.runModal() == .OK, let url = panel.url { destination = url }
    }

    private func start() {
        if !password.isEmpty { model.password = password }
        Prefs.showAfterExtract = showInFinder
        let options = ExtractOptions(destination: finalDestination,
                                     paths: selectedOnly ? selected : [],
                                     overwrite: overwrite,
                                     showInFinder: showInFinder)
        dismiss()
        Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            await model.extract(options)
        }
    }
}

// MARK: - Compress

struct CompressSheet: View {
    @ObservedObject var model: ArchiveViewModel
    let files: [URL]

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var directory: URL = FileManager.default.homeDirectoryForCurrentUser
    @State private var format: ArchiveFormat = Prefs.defaultFormat
    @State private var level: Int = Prefs.defaultLevel
    @State private var split = "none"
    @State private var password = ""
    @State private var confirm = ""
    @State private var encryptNames = true
    @State private var excludeMac = true

    private static let levels = [0, 1, 3, 5, 7, 9]
    private static let splits: [(String, String)] = [
        ("10m", "10 MB"), ("100m", "100 MB"), ("650m", "650 MB (CD)"), ("700m", "700 MB (CD)"),
        ("1000m", "1 GB"), ("4092m", "4 GB (FAT32)"), ("4480m", "4.7 GB (DVD)"),
    ]

    private var singlePlainFile: Bool {
        guard files.count == 1 else { return false }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: files[0].path, isDirectory: &isDir) && !isDir.boolValue
    }

    private var ext: String { format.fileExtension(singlePlainFile: singlePlainFile) }

    private var outputURL: URL {
        var n = name.trimmingCharacters(in: .whitespaces)
        if n.isEmpty { n = "Archive" }
        if !n.lowercased().hasSuffix("." + ext) { n += "." + ext }
        return directory.appendingPathComponent(n)
    }

    private var passwordProblem: String? {
        guard format.supportsEncryption, !password.isEmpty else { return nil }
        return password == confirm ? nil : L("compress.mismatch")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "doc.zipper").font(.largeTitle).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading) {
                    Text(L("compress.title")).font(.title2.bold())
                    Text(LF("compress.files", files.count)).foregroundStyle(.secondary)
                }
            }

            Form {
                Section {
                    LabeledContent(L("compress.name")) {
                        HStack(spacing: 4) {
                            TextField("", text: $name).textFieldStyle(.roundedBorder)
                            Text("." + ext).foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent(L("compress.location")) {
                        HStack {
                            Text(directory.path).lineLimit(1).truncationMode(.head)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .help(directory.path)
                            Button(L("common.choose")) { chooseFolder() }
                        }
                    }
                }
                Section {
                    Picker(L("compress.format"), selection: $format) {
                        ForEach(ArchiveFormat.allCases) { f in Text(f.displayName).tag(f) }
                    }
                    Picker(L("compress.level"), selection: $level) {
                        ForEach(Self.levels, id: \.self) { l in Text(L("level.\(l)")).tag(l) }
                    }
                    .disabled(!format.supportsLevel)
                    Picker(L("compress.split"), selection: $split) {
                        Text(L("split.none")).tag("none")
                        ForEach(Self.splits, id: \.0) { s in Text(s.1).tag(s.0) }
                    }
                    Toggle(L("compress.excludeMac"), isOn: $excludeMac)
                }
                Section(L("compress.encryption")) {
                    if format.supportsEncryption {
                        SecureField(L("compress.password"), text: $password)
                        SecureField(L("compress.confirm"), text: $confirm)
                        if format.supportsHeaderEncryption {
                            Toggle(L("compress.encryptNames"), isOn: $encryptNames)
                        }
                        if let problem = passwordProblem {
                            Text(problem).foregroundStyle(.red).font(.caption)
                        }
                    } else {
                        Text(L("compress.noEncryption")).foregroundStyle(.secondary).font(.callout)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button(L("common.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L("compress.start")) { start() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(passwordProblem != nil || files.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear(perform: setup)
    }

    private func setup() {
        guard let first = files.first else { return }
        directory = first.deletingLastPathComponent()
        if !FileManager.default.isWritableFile(atPath: directory.path) {
            directory = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first ?? directory
        }
        if files.count == 1 {
            name = singlePlainFile ? first.deletingPathExtension().lastPathComponent : first.lastPathComponent
            if singlePlainFile && format.isStreamCompressor { name = first.lastPathComponent }
        } else {
            let parentName = directory.lastPathComponent
            name = parentName.isEmpty || parentName == "/" ? "Archive" : parentName
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = directory
        if panel.runModal() == .OK, let url = panel.url { directory = url }
    }

    /// Picks "name (2).ext" etc. if the file already exists.
    private func uniqueOutput() -> URL {
        let fm = FileManager.default
        var url = outputURL
        guard fm.fileExists(atPath: url.path) || fm.fileExists(atPath: url.path + ".001") else { return url }
        let fileName = url.lastPathComponent
        let stem = String(fileName.dropLast(ext.count + 1))
        var i = 2
        repeat {
            url = directory.appendingPathComponent("\(stem) (\(i)).\(ext)")
            i += 1
        } while fm.fileExists(atPath: url.path) || fm.fileExists(atPath: url.path + ".001")
        return url
    }

    private func start() {
        Prefs.defaultFormat = format
        Prefs.defaultLevel = level
        let options = CompressOptions(files: files,
                                      output: uniqueOutput(),
                                      format: format,
                                      level: level,
                                      password: format.supportsEncryption ? password : "",
                                      encryptNames: encryptNames,
                                      volumeSize: split == "none" ? nil : split,
                                      excludeMacFiles: excludeMac)
        dismiss()
        Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            await model.compress(options)
        }
    }
}

// MARK: - Archive properties

struct InfoSheet: View {
    @ObservedObject var model: ArchiveViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(nsImage: FileIcons.icon(forName: model.archiveName, isDirectory: false))
                    .resizable().frame(width: 40, height: 40)
                VStack(alignment: .leading) {
                    Text(L("info.title")).font(.title2.bold())
                    Text(model.archiveName).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            Form {
                row(L("info.path"), model.archiveURL?.deletingLastPathComponent().path ?? "")
                row(L("info.type"), model.info.type)
                row(L("info.physSize"), Format.bytes(model.info.physicalSize))
                row(L("info.unpacked"), Format.bytes(model.totalUnpacked))
                row(L("info.ratio"), ratio)
                row(L("info.files"), "\(model.fileCount)")
                row(L("info.folders"), "\(model.folderCount)")
                if !model.info.method.isEmpty { row(L("info.method"), model.info.method) }
                if model.info.type == "7z" { row(L("info.solid"), model.info.solid ? L("common.yes") : L("common.no")) }
                row(L("info.encrypted"), model.hasEncryptedEntries || model.password != nil ? L("common.yes") : L("common.no"))
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button(L("common.close")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private var ratio: String {
        guard model.totalUnpacked > 0, model.info.physicalSize > 0 else { return "—" }
        let r = Double(model.info.physicalSize) / Double(model.totalUnpacked) * 100
        return String(format: "%.1f%%", r)
    }

    private func row(_ title: String, _ value: String) -> some View {
        LabeledContent(title) {
            Text(value).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
        }
    }
}
