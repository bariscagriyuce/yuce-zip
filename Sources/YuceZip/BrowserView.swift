import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Root view of every window. Re-creates its content when the language changes.
struct RootView: View {
    @ObservedObject var l10n = L10n.shared
    @ObservedObject var model: ArchiveViewModel

    var body: some View {
        BrowserView(model: model)
            .id(l10n.effectiveCode)
            .environment(\.locale, l10n.locale)
    }
}

struct BrowserView: View {
    @ObservedObject var model: ArchiveViewModel
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            ToolbarRow(model: model)
            Divider()
            if model.isOpen {
                PathBar(model: model)
                Divider()
                FileTable(model: model)
                Divider()
                StatusBar(model: model)
            } else {
                WelcomeView(model: model, targeted: dropTargeted)
            }
        }
        .frame(minWidth: 640, minHeight: 400)
        .overlay {
            if let op = model.operation {
                ProgressOverlay(state: op) { model.cancelOperation() }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            handleDrop(providers)
            return true
        }
        .sheet(item: $model.sheet) { sheet in
            switch sheet {
            case .extract(let selected):
                ExtractSheet(model: model, selected: selected)
            case .compress(let files):
                CompressSheet(model: model, files: files)
            case .info:
                InfoSheet(model: model)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        guard !model.isBusy else { return }
        var urls: [URL] = []
        let group = DispatchGroup()
        let lock = NSLock()
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url { lock.lock(); urls.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            guard !urls.isEmpty else { return }
            if model.isOpen {
                if model.isWritable {
                    Task { await model.addFiles(urls) }
                } else if urls.count == 1, ArchiveTypes.isArchive(urls[0]) {
                    AppDelegate.shared.openArchive(urls[0], forceNewWindow: true)
                }
            } else if urls.count == 1, ArchiveTypes.isArchive(urls[0]) {
                Task { await model.open(urls[0]) }
            } else {
                model.sheet = .compress(files: urls)
            }
        }
    }
}

// MARK: - Toolbar

struct ToolbarRow: View {
    @ObservedObject var model: ArchiveViewModel

    var body: some View {
        HStack(spacing: 4) {
            ToolButton(title: L("menu.open").replacingOccurrences(of: "…", with: ""), symbol: "folder") {
                AppDelegate.shared.showOpenPanel(for: model)
            }
            ToolButton(title: L("toolbar.add"), symbol: "plus.rectangle.on.folder", enabled: model.isOpen && model.isWritable) {
                AppDelegate.shared.showAddPanel(for: model)
            }
            ToolButton(title: L("toolbar.extract"), symbol: "arrow.down.doc", enabled: model.isOpen) {
                model.sheet = .extract(selected: Array(model.selection))
            }
            ToolButton(title: L("toolbar.test"), symbol: "checkmark.shield", enabled: model.isOpen) {
                Task { await model.test() }
            }
            ToolButton(title: L("toolbar.delete"), symbol: "trash", enabled: model.isOpen && model.isWritable && !model.selection.isEmpty) {
                Task { await model.deleteSelected() }
            }
            ToolButton(title: L("toolbar.info"), symbol: "info.circle", enabled: model.isOpen) {
                model.sheet = .info
            }
            Spacer()
            ToolButton(title: L("welcome.compress").replacingOccurrences(of: "…", with: ""), symbol: "doc.zipper") {
                AppDelegate.shared.showCompressPanel(for: model)
            }
            if model.isOpen {
                ToolButton(title: L("toolbar.close"), symbol: "xmark.circle") {
                    model.closeArchive()
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.bar)
        .disabled(model.isBusy)
    }
}

struct ToolButton: View {
    let title: String
    let symbol: String
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .regular))
                    .frame(height: 22)
                Text(title)
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
            .frame(minWidth: 58)
            .padding(.vertical, 3)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(ToolButtonStyle())
        .disabled(!enabled)
        .help(title)
    }
}

struct ToolButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? Color.accentColor : Color.secondary.opacity(0.5))
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed ? Color.primary.opacity(0.12) : Color.clear)
            )
    }
}

// MARK: - Path bar

struct PathBar: View {
    @ObservedObject var model: ArchiveViewModel

    var body: some View {
        HStack(spacing: 6) {
            Button {
                model.goUp()
            } label: {
                Image(systemName: "arrow.up")
            }
            .help(L("toolbar.up"))
            .disabled(model.currentFolder?.parent == nil)
            .keyboardShortcut(.upArrow, modifiers: .command)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array((model.currentFolder?.ancestry ?? []).enumerated()), id: \.element.id) { index, node in
                        if index > 0 {
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                        }
                        Button {
                            model.enter(node)
                        } label: {
                            HStack(spacing: 4) {
                                if index == 0 {
                                    Image(nsImage: FileIcons.icon(forName: node.name, isDirectory: false))
                                        .resizable().frame(width: 14, height: 14)
                                } else {
                                    Image(nsImage: FileIcons.folder).resizable().frame(width: 14, height: 14)
                                }
                                Text(node.name).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4)
                            .fill(node.id == model.currentFolder?.id ? Color.accentColor.opacity(0.15) : .clear))
                    }
                }
            }
            if model.hasEncryptedEntries {
                Label(L("status.encrypted"), systemImage: "lock.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

// MARK: - File table

struct FileTable: View {
    @ObservedObject var model: ArchiveViewModel

    var body: some View {
        Table(model.rows, selection: $model.selection, sortOrder: $model.sortOrder) {
            TableColumn(L("col.name"), value: \ArchiveNode.sortName) { node in
                HStack(spacing: 6) {
                    Image(nsImage: node.isDirectory ? FileIcons.folder : FileIcons.icon(forName: node.name, isDirectory: false))
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(node.name).lineLimit(1).truncationMode(.middle)
                    if node.encrypted {
                        Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.orange)
                    }
                }
            }
            .width(min: 180, ideal: 320)

            TableColumn(L("col.size"), value: \ArchiveNode.sortSize) { node in
                Text(Format.bytes(node.size)).foregroundStyle(.secondary).monospacedDigit()
            }
            .width(min: 70, ideal: 90)

            TableColumn(L("col.packed"), value: \ArchiveNode.sortPacked) { node in
                Text(node.packedSize > 0 ? Format.bytes(node.packedSize) : "—")
                    .foregroundStyle(.secondary).monospacedDigit()
            }
            .width(min: 70, ideal: 90)

            TableColumn(L("col.modified"), value: \ArchiveNode.sortDate) { node in
                Text(Format.date(node.modified)).foregroundStyle(.secondary)
            }
            .width(min: 110, ideal: 150)

            TableColumn(L("col.method")) { node in
                Text(node.method).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 60, ideal: 110)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if !ids.isEmpty {
                Button(L("context.open")) {
                    if let id = ids.first, let node = model.node(for: id) {
                        Task { await model.openEntry(node) }
                    }
                }
                .disabled(ids.count != 1)
                Button(L("context.extract")) {
                    model.selection = ids
                    model.sheet = .extract(selected: Array(ids))
                }
                if model.isWritable {
                    Divider()
                    Button(L("context.delete"), role: .destructive) {
                        model.selection = ids
                        Task { await model.deleteSelected() }
                    }
                }
            }
        } primaryAction: { ids in
            guard ids.count == 1, let id = ids.first, let node = model.node(for: id) else { return }
            Task { await model.openEntry(node) }
        }
        .onDeleteCommand {
            if model.isWritable && !model.selection.isEmpty {
                Task { await model.deleteSelected() }
            }
        }
    }
}

// MARK: - Status bar

struct StatusBar: View {
    @ObservedObject var model: ArchiveViewModel

    var body: some View {
        HStack {
            Text(model.statusText)
            Spacer()
            if !model.isWritable {
                Label(L("status.readOnly"), systemImage: "lock")
                    .labelStyle(.titleAndIcon)
            }
            Text(model.summaryText)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.bar)
    }
}

// MARK: - Welcome / drop zone

struct WelcomeView: View {
    @ObservedObject var model: ArchiveViewModel
    var targeted: Bool

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .shadow(radius: targeted ? 10 : 3)
                .scaleEffect(targeted ? 1.08 : 1)
                .animation(.spring(response: 0.3), value: targeted)
            Text("YUCE ZIP")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
            Text(L("welcome.title"))
                .font(.title2.weight(.semibold))
            Text(L("welcome.subtitle"))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            HStack(spacing: 12) {
                Button {
                    AppDelegate.shared.showOpenPanel(for: model)
                } label: {
                    Label(L("welcome.open"), systemImage: "folder")
                        .padding(.horizontal, 8).padding(.vertical, 4)
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                Button {
                    AppDelegate.shared.showCompressPanel(for: model)
                } label: {
                    Label(L("welcome.compress"), systemImage: "doc.zipper")
                        .padding(.horizontal, 8).padding(.vertical, 4)
                }
                .controlSize(.large)
            }
            Spacer()
            Text(L("welcome.formats"))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 14)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .foregroundStyle(targeted ? Color.accentColor : Color.secondary.opacity(0.35))
                .padding(16)
        )
    }
}

// MARK: - Progress overlay

struct ProgressOverlay: View {
    let state: OperationState
    let cancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                Text(state.title).font(.headline)
                if !state.detail.isEmpty {
                    Text(state.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                if let p = state.progress {
                    ProgressView(value: p)
                    Text("\(Int(p * 100))%").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
                HStack {
                    Spacer()
                    Button(L("common.cancel"), action: cancel)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(20)
            .frame(width: 360)
            .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
            .shadow(radius: 20)
        }
    }
}

// MARK: - Icons

enum FileIcons {
    private static var cache: [String: NSImage] = [:]

    static let folder: NSImage = NSWorkspace.shared.icon(for: .folder)

    static func icon(forName name: String, isDirectory: Bool) -> NSImage {
        if isDirectory { return folder }
        let ext = (name as NSString).pathExtension.lowercased()
        if let cached = cache[ext] { return cached }
        let type = UTType(filenameExtension: ext) ?? .data
        let img = NSWorkspace.shared.icon(for: type)
        cache[ext] = img
        return img
    }
}
