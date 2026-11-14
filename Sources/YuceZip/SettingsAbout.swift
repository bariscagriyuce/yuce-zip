import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var l10n = L10n.shared
    @ObservedObject var updater = UpdateChecker.shared

    @State private var format = Prefs.defaultFormat
    @State private var level = Prefs.defaultLevel
    @State private var showAfterExtract = Prefs.showAfterExtract
    @State private var autoCheck = Prefs.autoCheckUpdates
    @State private var isDefault = SystemIntegration.isDefaultForZip
    @State private var defaultMessage: String?
    @State private var finderEnabled = SystemIntegration.isFinderExtensionEnabled

    var body: some View {
        Form {
            Section(L("settings.general")) {
                Picker(L("settings.language"), selection: $l10n.language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.nativeName).tag(lang)
                    }
                }
                Toggle(L("settings.afterExtract"), isOn: $showAfterExtract)
                    .onChange(of: showAfterExtract) { Prefs.showAfterExtract = $0 }
            }
            Section(L("settings.defaults")) {
                Picker(L("settings.defaultFormat"), selection: $format) {
                    ForEach(ArchiveFormat.allCases) { f in Text(f.displayName).tag(f) }
                }
                .onChange(of: format) { Prefs.defaultFormat = $0 }
                Picker(L("settings.defaultLevel"), selection: $level) {
                    ForEach([0, 1, 3, 5, 7, 9], id: \.self) { l in Text(L("level.\(l)")).tag(l) }
                }
                .onChange(of: level) { Prefs.defaultLevel = $0 }
            }
            Section(L("settings.integration")) {
                HStack {
                    Image(systemName: isDefault ? "checkmark.circle.fill" : "info.circle")
                        .foregroundStyle(isDefault ? .green : .secondary)
                    Text(isDefault ? L("settings.isDefault") : L("settings.notDefault"))
                        .foregroundStyle(.secondary)
                }
                Button(L("settings.makeDefault")) {
                    Task {
                        let (ok, failed) = await SystemIntegration.makeDefaultForArchives()
                        isDefault = SystemIntegration.isDefaultForZip
                        defaultMessage = LF("settings.defaultDone", ok) + (failed > 0 ? "\n" + LF("settings.defaultFailed", failed) : "")
                    }
                }
                if let defaultMessage {
                    Text(defaultMessage).font(.caption).foregroundStyle(.secondary)
                }
                Toggle(L("settings.finderMenu"), isOn: $finderEnabled)
                    .onChange(of: finderEnabled) { value in
                        if value != SystemIntegration.isFinderExtensionEnabled {
                            SystemIntegration.setFinderExtension(enabled: value)
                        }
                    }
                HStack(alignment: .top) {
                    Text(L("settings.finderHint")).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(L("settings.finderSettings")) { SystemIntegration.showFinderExtensionSettings() }
                }
            }
            Section(L("settings.updates")) {
                Toggle(L("settings.autoCheck"), isOn: $autoCheck)
                    .onChange(of: autoCheck) { Prefs.autoCheckUpdates = $0 }
                HStack {
                    Text(LF("settings.lastCheck", updater.lastCheck.map { Format.date($0) } ?? L("settings.never")))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if updater.isChecking { ProgressView().controlSize(.small) }
                    Button(L("settings.checkNow")) {
                        Task { await updater.check(userInitiated: true) }
                    }
                    .disabled(updater.isChecking)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isDefault = SystemIntegration.isDefaultForZip
            finderEnabled = SystemIntegration.isFinderExtensionEnabled
        }
        .fixedSize(horizontal: false, vertical: true)
        .id(l10n.effectiveCode)
        .environment(\.locale, l10n.locale)
    }
}

struct AboutView: View {
    @ObservedObject var l10n = L10n.shared

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
            Text("YUCE ZIP")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
            Text(LF("about.version", UpdateChecker.currentVersion))
                .foregroundStyle(.secondary)
            Text(L("about.description"))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .padding(.top, 4)
            Text(LF("about.engine", SevenZipProcess.engineVersion))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack {
                Link(L("about.github"), destination: UpdateChecker.repositoryURL)
                Text("·").foregroundStyle(.secondary)
                Button(L("menu.checkUpdates")) {
                    Task { await UpdateChecker.shared.check(userInitiated: true) }
                }
                .buttonStyle(.link)
            }
            .padding(.top, 6)
            Text("© 2026 YUCE ZIP · github.com/bariscagriyuce")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding(28)
        .frame(width: 400)
        .id(l10n.effectiveCode)
    }
}
