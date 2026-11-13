import AppKit
import SwiftUI

@main
@MainActor
enum YuceZipMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        AppDelegate.shared = delegate
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

// MARK: - Window controller for one archive

@MainActor
final class BrowserWindowController: NSWindowController, NSWindowDelegate {
    let model = ArchiveViewModel()

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 560),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "YUCE ZIP"
        window.minSize = NSSize(width: 640, height: 420)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .preferred
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: RootView(model: model))
        window.setContentSize(NSSize(width: 860, height: 560))
        window.delegate = self
        model.window = window
        window.setFrameAutosaveName("YuceZipBrowser")
        if !window.setFrameUsingName("YuceZipBrowser") { window.center() }
    }

    required init?(coder: NSCoder) { fatalError() }

    func windowWillClose(_ notification: Notification) {
        model.cancelOperation()
        AppDelegate.shared.windowClosed(self)
    }
}

// MARK: - App delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    static var shared: AppDelegate!

    private var windows: [BrowserWindowController] = []
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var didOpenFilesAtLaunch = false

    // MARK: Lifecycle

    func applicationWillFinishLaunching(_ notification: Notification) {
        buildMenu()
        NotificationCenter.default.addObserver(forName: .languageChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.languageChanged() }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            if self.windows.isEmpty { self.newWindow() }
        }
        UpdateChecker.shared.checkAtLaunchIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        TempFiles.cleanUp()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { newWindow() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func application(_ application: NSApplication, open urls: [URL]) {
        var nonArchives: [URL] = []
        for url in urls {
            if ArchiveTypes.isArchive(url) {
                openArchive(url)
            } else {
                nonArchives.append(url)
            }
        }
        if !nonArchives.isEmpty {
            let wc = emptyWindow() ?? newWindow()
            wc.showWindow(nil)
            wc.model.sheet = .compress(files: nonArchives)
        }
    }

    // MARK: Windows

    @discardableResult
    func newWindow() -> BrowserWindowController {
        let wc = BrowserWindowController()
        if let last = windows.last?.window {
            wc.window?.setFrameTopLeftPoint(NSPoint(x: last.frame.minX + 24, y: last.frame.maxY - 24))
        }
        windows.append(wc)
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        return wc
    }

    func windowClosed(_ wc: BrowserWindowController) {
        windows.removeAll { $0 === wc }
    }

    private func emptyWindow() -> BrowserWindowController? {
        windows.first { !$0.model.isOpen && !$0.model.isBusy && $0.model.sheet == nil }
    }

    private var currentWindowController: BrowserWindowController? {
        if let key = NSApp.keyWindow ?? NSApp.mainWindow,
           let wc = windows.first(where: { $0.window === key }) { return wc }
        return nil
    }

    func openArchive(_ url: URL, forceNewWindow: Bool = false) {
        // Already open? Bring it to front.
        if let existing = windows.first(where: { $0.model.archiveURL?.standardizedFileURL == url.standardizedFileURL }) {
            existing.showWindow(nil)
            return
        }
        let wc = (forceNewWindow ? nil : emptyWindow()) ?? newWindow()
        wc.showWindow(nil)
        Task { await wc.model.open(url) }
    }

    // MARK: Panels

    func showOpenPanel(for model: ArchiveViewModel?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = L("menu.open").replacingOccurrences(of: "…", with: "")
        guard panel.runModal() == .OK else { return }
        for (i, url) in panel.urls.enumerated() {
            if i == 0, let model, !model.isOpen, !model.isBusy {
                Task { await model.open(url) }
            } else {
                openArchive(url)
            }
        }
    }

    func showCompressPanel(for model: ArchiveViewModel?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = L("menu.compress").replacingOccurrences(of: "…", with: "")
        panel.prompt = L("compress.start")
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let target = model ?? (emptyWindow() ?? newWindow()).model
        target.sheet = .compress(files: panel.urls)
    }

    func showAddPanel(for model: ArchiveViewModel) {
        guard let window = model.window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = L("add.button")
        panel.beginSheetModal(for: window) { response in
            guard response == .OK else { return }
            let urls = panel.urls
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                await model.addFiles(urls, confirm: false)
            }
        }
    }

    // MARK: Menu actions

    @objc func newWindowAction(_ sender: Any?) { newWindow() }

    @objc func openAction(_ sender: Any?) {
        showOpenPanel(for: currentWindowController?.model)
    }

    @objc func compressAction(_ sender: Any?) {
        showCompressPanel(for: currentWindowController?.model)
    }

    @objc func extractAction(_ sender: Any?) {
        guard let m = currentWindowController?.model, m.isOpen else { return }
        m.sheet = .extract(selected: Array(m.selection))
    }

    @objc func extractHereAction(_ sender: Any?) {
        guard let m = currentWindowController?.model, m.isOpen else { return }
        Task { await m.extractHere() }
    }

    @objc func testAction(_ sender: Any?) {
        guard let m = currentWindowController?.model, m.isOpen else { return }
        Task { await m.test() }
    }

    @objc func propertiesAction(_ sender: Any?) {
        guard let m = currentWindowController?.model, m.isOpen else { return }
        m.sheet = .info
    }

    @objc func checkUpdatesAction(_ sender: Any?) {
        Task { await UpdateChecker.shared.check(userInitiated: true) }
    }

    @objc func githubAction(_ sender: Any?) {
        NSWorkspace.shared.open(UpdateChecker.repositoryURL)
    }

    @objc func showSettings(_ sender: Any?) {
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        settingsWindow?.title = L("settings.title")
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showAbout(_ sender: Any?) {
        if aboutWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: AboutView()))
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            aboutWindow = w
        }
        aboutWindow?.title = L("menu.about")
        aboutWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let model = currentWindowController?.model
        switch menuItem.action {
        case #selector(extractAction(_:)), #selector(extractHereAction(_:)),
             #selector(testAction(_:)), #selector(propertiesAction(_:)):
            return model?.isOpen == true && model?.isBusy == false
        case #selector(checkUpdatesAction(_:)):
            return !UpdateChecker.shared.isChecking
        default:
            return true
        }
    }

    private func languageChanged() {
        buildMenu()
        settingsWindow?.title = L("settings.title")
        aboutWindow?.title = L("menu.about")
    }

    // MARK: Main menu

    private func buildMenu() {
        let main = NSMenu()

        // App menu
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "YUCE ZIP")
        appMenu.addItem(item(L("menu.about"), #selector(showAbout(_:))))
        appMenu.addItem(item(L("menu.checkUpdates"), #selector(checkUpdatesAction(_:))))
        appMenu.addItem(.separator())
        appMenu.addItem(item(L("menu.settings"), #selector(showSettings(_:)), key: ","))
        appMenu.addItem(.separator())
        let servicesItem = NSMenuItem(title: L("menu.services"), action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: L("menu.services"))
        servicesItem.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        appMenu.addItem(servicesItem)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: L("menu.hide"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let hideOthers = NSMenuItem(title: L("menu.hideOthers"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(NSMenuItem(title: L("menu.showAll"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: L("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)

        // File menu
        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: L("menu.file"))
        fileMenu.addItem(item(L("menu.newWindow"), #selector(newWindowAction(_:)), key: "n"))
        fileMenu.addItem(item(L("menu.open"), #selector(openAction(_:)), key: "o"))
        fileMenu.addItem(item(L("menu.compress"), #selector(compressAction(_:)), key: "k"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(item(L("menu.extract"), #selector(extractAction(_:)), key: "e"))
        let here = item(L("menu.extractHere"), #selector(extractHereAction(_:)), key: "e")
        here.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(here)
        fileMenu.addItem(item(L("menu.test"), #selector(testAction(_:)), key: "t"))
        fileMenu.addItem(item(L("menu.properties"), #selector(propertiesAction(_:)), key: "i"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(NSMenuItem(title: L("menu.close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        // Edit menu (needed for copy/paste in text fields)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: L("menu.edit"))
        editMenu.addItem(NSMenuItem(title: L("menu.undo"), action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: L("menu.redo"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: L("menu.cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: L("menu.copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: L("menu.paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: L("menu.selectAll"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu
        main.addItem(editItem)

        // Window menu
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: L("menu.window"))
        windowMenu.addItem(NSMenuItem(title: L("menu.minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: L("menu.zoom"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        windowMenu.addItem(.separator())
        windowMenu.addItem(NSMenuItem(title: L("menu.front"), action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: ""))
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        // Help menu
        let helpItem = NSMenuItem()
        let helpMenu = NSMenu(title: L("menu.help"))
        helpMenu.addItem(item(L("menu.github"), #selector(githubAction(_:))))
        helpItem.submenu = helpMenu
        main.addItem(helpItem)
        NSApp.helpMenu = helpMenu

        NSApp.mainMenu = main
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }
}
