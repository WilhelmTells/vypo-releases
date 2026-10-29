import ServiceManagement
import SwiftUI

/// Settings → General (§15).
struct GeneralPane: View {
    @Environment(AppState.self) private var app
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var language = AppLanguage.current
    @State private var askRelaunch = false
    @State private var choosingLanguages = false

    var body: some View {
        @Bindable var prefs = app.prefs
        Form {
            Section {
                Toggle("Open at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { LoginItem.set(openAtLogin) }
            } header: {
                PaneSectionHeader(pane: .general)
            }

            Section {
                Toggle("Paste text automatically", isOn: $prefs.pasteAutomatically)
                Toggle(isOn: $prefs.restoreClipboard) {
                    RowLabel(title: "Restore clipboard", description: "Puts back what was on the clipboard after pasting.")
                }
                Toggle(isOn: $prefs.smartSpacing) {
                    RowLabel(title: "Smart spacing and capitalization",
                             description: "Adds spaces and capital letters so the text fits where your cursor is.")
                }
            } header: {
                Text("Pasting")
            } footer: {
                Text("vypo types the text wherever your cursor is. Your voice and your text never leave this Mac.")
            }

            Section {
                LabeledContent("Languages") {
                    HStack(spacing: Space.s2) {
                        Text(app.prefs.languages.map(\.name).formatted(.list(type: .and).locale(Formatting.uiLocale)))
                            .foregroundStyle(Color.vyLabelSecondary)
                            .lineLimit(1)
                        Button("Choose…") { choosingLanguages = true }
                    }
                }
                SpeechModelRow()
                LabeledContent("Storage") {
                    HStack(spacing: Space.s2) {
                        Text("\(Formatting.bytes(app.models?.manager.storageBytes ?? 0)) used")
                            .foregroundStyle(Color.vyLabelSecondary)
                        Button("Show in Finder") { app.models?.manager.showInFinder() }
                    }
                }
            } header: {
                Text("Speech recognition")
            } footer: {
                Text("vypo recognizes which of your languages you’re speaking. Recognition runs on this Mac.")
            }

            Section {
                Picker("App language", selection: $language) {
                    Text("System").tag(AppLanguage.system)
                    Text(verbatim: "English").tag(AppLanguage.en)
                    Text(verbatim: "Deutsch").tag(AppLanguage.de)
                }
                .onChange(of: language) { AppLanguage.set(language); askRelaunch = true }
            } header: {
                Text("Language")
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $choosingLanguages) { LanguagesSheet().environment(app) }
        .onAppear {
            openAtLogin = SMAppService.mainApp.status == .enabled
            app.models?.manager.refreshStorage()
        }
        .alert("Restart vypo to change the language?", isPresented: $askRelaunch) {
            Button("Restart now") { AppLanguage.relaunch() }
            Button("Later", role: .cancel) {}
        } message: {
            Text("vypo quits and opens again. This takes a second.")
        }
    }
}

extension WindowStyle {
    var name: String {
        switch self {
        case .automatic: String(localized: "Automatic")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        case .glass: String(localized: "Glass")
        }
    }
}

enum LoginItem {
    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            Log.app.error("Login item: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Default on: registered once, on first launch.
    static func applyDefaultOnce(_ defaults: UserDefaults = AppDefaults.standard) {
        let key = "openAtLoginConfigured"
        // The onboarding test build must never register itself as a login item.
        guard !defaults.bool(forKey: key), !RunEnvironment.isOnboardingTestBuild else { return }
        defaults.set(true, forKey: key)
        set(true)
    }
}

/// The language vypo shows (Settings → General): the system's, or English or German regardless of it.
/// Stored as vypo's own `AppleLanguages`, which macOS reads at launch.
enum AppLanguage: String {
    case system, en, de

    private static let key = "AppleLanguages"

    static var current: AppLanguage {
        let domain = AppDefaults.standard.persistentDomain(forName: AppDefaults.suiteName) ?? [:]
        guard let first = (domain[key] as? [String])?.first else { return .system }
        return first.hasPrefix("de") ? .de : first.hasPrefix("en") ? .en : .system
    }

    static func set(_ language: AppLanguage) {
        if language == .system {
            AppDefaults.standard.removeObject(forKey: key)
        } else {
            AppDefaults.standard.set([language.rawValue], forKey: key)
        }
    }

    /// Quits and opens vypo again once this instance is gone.
    @MainActor static func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.1; done; open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }
}

/// Parakeet Ultra: installed, downloading, or ready to download.
struct SpeechModelRow: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let info = ModelCatalog.speech.info
        let models = app.models
        LabeledContent {
            switch models?.state ?? .notInstalled {
            case .installed:
                Text("Installed (\(Formatting.bytes(models?.manager.sizeOnDisk(info.id) ?? info.approxBytes)))")
                    .foregroundStyle(Color.vyLabelSecondary)
            case .queued:
                Text("Waiting…").foregroundStyle(Color.vyLabelSecondary)
            case .downloading(let p):
                HStack(spacing: Space.s2) {
                    ProgressBar(value: p).frame(width: 120)
                    Text("\(Int(p * 100)) %").monospacedDigit().foregroundStyle(Color.vyLabelSecondary)
                    Button("Cancel") { models?.cancelDownload() }
                }
            case .notInstalled:
                Button("Download (\(info.approxSizeText))") { models?.download() }
            case .failed:
                Button("Retry download") { models?.download() }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                RowLabel(title: "\(info.name)", description: "\(info.note)")
                ModelAttribution()
            }
        }
    }
}
