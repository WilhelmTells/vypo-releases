import AppKit
import Foundation
import Observation
import Sparkle

/// Updates with Sparkle: a check once a day (Info.plist: `SUFeedURL`, `SUScheduledCheckInterval`), and
/// “Check for Updates…” by hand. Sparkle verifies every download with the EdDSA key in `SUPublicEDKey`.
/// vypo isn't sandboxed, so Sparkle's XPC services aren't needed.
@MainActor
@Observable
final class Updates {
    private let controller: SPUStandardUpdaterController
    private let delegate = UpdateDelegate()
    private var observation: NSKeyValueObservation?

    /// Whether vypo asks once a day. Sparkle keeps the choice in the preferences (`SUEnableAutomaticChecks`).
    var automatic: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = automatic }
    }
    /// False while a check or an update is already running.
    private(set) var canCheck: Bool
    /// When Sparkle last asked the server, if it ever has.
    private(set) var lastChecked: Date?

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: delegate, userDriverDelegate: delegate)
        automatic = controller.updater.automaticallyChecksForUpdates
        canCheck = controller.updater.canCheckForUpdates
        lastChecked = controller.updater.lastUpdateCheckDate
        delegate.onCycleFinished = { [weak self] in
            guard let self else { return }
            self.lastChecked = self.controller.updater.lastUpdateCheckDate
        }
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, change in
            let can = change.newValue ?? true
            Task { @MainActor in self?.canCheck = can }
        }
        #if DEBUG
        // For the local update test: `-VYPOCheckAtLaunch YES` looks for an update at once.
        if UserDefaults.standard.bool(forKey: "VYPOCheckAtLaunch") {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(3))
                self?.checkNow()
            }
        }
        // `-VYPOAutoClick YES` presses the update window's buttons for the test, a few seconds after each shows.
        if UserDefaults.standard.bool(forKey: "VYPOAutoClick") { Self.pressUpdateButtons() }
        #endif
    }

    func checkNow() {
        // vypo has no Dock icon: bring it forward, or the update window opens behind other apps.
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    /// “0.2.0 (2)”.
    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

/// Sparkle's two delegates in one. vypo is a menu bar app, so an update that a daily check finds has to come
/// forward itself, or its window would open behind the other apps and nobody would see it (Sparkle's “gentle
/// reminders” for background apps).
///
/// In debug builds the feed can also be pointed elsewhere (`-VYPOFeedURL http://127.0.0.1:8000/appcast.xml`) to
/// test an update against a local server. Release builds don't have this at all.
@MainActor
private final class UpdateDelegate: NSObject, @preconcurrency SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }
    var onCycleFinished: () -> Void = {}

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        onCycleFinished()
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard handleShowingUpdate, !state.userInitiated else { return }
        NSApp.activate()
    }

    #if DEBUG
    func feedURLString(for updater: SPUUpdater) -> String? {
        UserDefaults.standard.string(forKey: "VYPOFeedURL")
    }
    #endif
}

#if DEBUG
extension Updates {
    /// Looks for the update window's buttons every half second; presses one after it has been on screen for 4 s.
    @MainActor
    static func pressUpdateButtons() {
        let titles = ["Install Update", "Install and Relaunch", "Relaunch"]
        var seenSince: [String: Date] = [:]
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated {
                for window in NSApp.windows where window.isVisible {
                    guard let button = window.contentView.flatMap({ firstButton(in: $0, titles: titles) }) else { continue }
                    let first = seenSince[button.title] ?? Date()
                    seenSince[button.title] = first
                    if Date().timeIntervalSince(first) > 4 {
                        Log.app.info("Update test: pressing “\(button.title, privacy: .public)”")
                        seenSince[button.title] = Date.distantFuture
                        button.performClick(nil)
                    }
                }
            }
        }
    }

    @MainActor
    private static func firstButton(in view: NSView, titles: [String]) -> NSButton? {
        if let b = view as? NSButton, titles.contains(b.title), b.isEnabled { return b }
        for sub in view.subviews { if let b = firstButton(in: sub, titles: titles) { return b } }
        return nil
    }
}
#endif
