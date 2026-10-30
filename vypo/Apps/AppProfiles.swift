import AppKit
import Observation

/// Per-app behavior (§23.5).
struct AppProfile: Codable, Identifiable, Hashable, Sendable {
    var bundleID: String
    var appName: String
    var mode: AppMode
    var autoEnter = false

    var id: String { bundleID }
}

/// `appProfiles.json`. Starts empty: the user adds the apps that should behave differently.
@MainActor
@Observable
final class AppProfileStore {
    private(set) var profiles: [AppProfile]
    @ObservationIgnored private let store: Store
    /// An app was switched to another mode (Right Tool).
    @ObservationIgnored var onModeChanged: (AppMode) -> Void = { _ in }
    private static let file = "appProfiles.json"
    private static let formerDefaultsRemovedKey = "appProfileDefaultsRemoved"

    /// What vypo used to add at first launch; removed once from existing installs unless the user changed them.
    static let formerDefaults: [AppProfile] = [
        AppProfile(bundleID: "com.apple.Terminal", appName: "Terminal", mode: .prompt),
        AppProfile(bundleID: "com.googlecode.iterm2", appName: "iTerm", mode: .prompt),
        AppProfile(bundleID: "com.mitchellh.ghostty", appName: "Ghostty", mode: .prompt),
        AppProfile(bundleID: "dev.warp.Warp-Stable", appName: "Warp", mode: .prompt),
        AppProfile(bundleID: "com.anthropic.claudefordesktop", appName: "Claude", mode: .prompt),
        AppProfile(bundleID: "com.openai.chat", appName: "ChatGPT", mode: .prompt),
        AppProfile(bundleID: "com.todesktop.230313mzl4w4u92", appName: "Cursor", mode: .prompt),
        AppProfile(bundleID: "com.microsoft.VSCode", appName: "Visual Studio Code", mode: .prompt),
        AppProfile(bundleID: "com.apple.iWork.Pages", appName: "Pages", mode: .writing),
        AppProfile(bundleID: "com.microsoft.Word", appName: "Microsoft Word", mode: .writing),
        AppProfile(bundleID: "com.apple.TextEdit", appName: "TextEdit", mode: .writing),
        AppProfile(bundleID: "com.apple.Notes", appName: "Notes", mode: .writing),
        AppProfile(bundleID: "com.1password.1password", appName: "1Password", mode: .excluded),
        AppProfile(bundleID: "com.agilebits.onepassword7", appName: "1Password 7", mode: .excluded),
        AppProfile(bundleID: "com.apple.keychainaccess", appName: "Keychain Access", mode: .excluded),
        AppProfile(bundleID: "com.apple.Passwords", appName: "Passwords", mode: .excluded),
        AppProfile(bundleID: "com.bitwarden.desktop", appName: "Bitwarden", mode: .excluded),
    ]

    init(store: Store = .shared) {
        self.store = store
        profiles = store.load([AppProfile].self, from: Self.file) ?? []
        if !AppDefaults.standard.bool(forKey: Self.formerDefaultsRemovedKey) {
            AppDefaults.standard.set(true, forKey: Self.formerDefaultsRemovedKey)
            let before = profiles.count
            profiles.removeAll { p in Self.formerDefaults.contains(p) }
            if profiles.count != before { save() }
        }
    }

    var sorted: [AppProfile] {
        profiles.sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
    }

    func profile(for bundleID: String?) -> AppProfile? {
        guard let bundleID else { return nil }
        return profiles.first { $0.bundleID == bundleID }
    }

    /// All other apps use `default`.
    func mode(for bundleID: String?) -> AppMode { profile(for: bundleID)?.mode ?? .standard }

    func autoEnter(for bundleID: String?) -> Bool {
        guard let p = profile(for: bundleID), p.mode == .prompt else { return false }
        return p.autoEnter
    }

    func update(_ profile: AppProfile) {
        let before = self.profile(for: profile.bundleID)?.mode
        defer { if profile.mode != before { onModeChanged(profile.mode) } }
        if let i = profiles.firstIndex(where: { $0.bundleID == profile.bundleID }) { profiles[i] = profile } else { profiles.append(profile) }
        save()
    }

    func remove(_ bundleID: String) {
        profiles.removeAll { $0.bundleID == bundleID }
        save()
    }

    /// Adds an app chosen in the open panel; new apps start in `default`.
    func add(appAt url: URL) {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, profile(for: id) == nil else { return }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        update(AppProfile(bundleID: id, appName: name, mode: .standard))
    }

    private func save() { store.save(profiles, to: Self.file) }

    /// The app icon (16 px), or a generic app icon if it isn't installed.
    static func icon(for bundleID: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }
}
