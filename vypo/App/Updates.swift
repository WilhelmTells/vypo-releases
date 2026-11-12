import AppKit
import Foundation
import Observation
import Sparkle

/// Updates with Sparkle: a check once a day (Info.plist: `SUFeedURL`, `SUScheduledCheckInterval`), and
/// “Check for Updates…” by hand. Sparkle verifies every download with the EdDSA key in `SUPublicEDKey`.
/// vypo isn't sandboxed, so Sparkle's XPC services aren't needed.
///
/// An update the daily check finds opens no window: the menu bar mark turns gold and the menu shows an
/// “Update available” row with the new version and an Install button (`waitingVersion`). A check by hand shows
/// Sparkle's window as before.
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
    /// The display version of an update the daily check found and that waits for the user (“0.6.0”), nil without
    /// one. While set, the mark is gold and the menu offers it.
    private(set) var waitingVersion: String?
    var updateWaiting: Bool { waitingVersion != nil }

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: delegate, userDriverDelegate: delegate)
        automatic = controller.updater.automaticallyChecksForUpdates
        canCheck = controller.updater.canCheckForUpdates
        lastChecked = controller.updater.lastUpdateCheckDate
        delegate.onCycleFinished = { [weak self] in
            guard let self else { return }
            self.lastChecked = self.controller.updater.lastUpdateCheckDate
        }
        delegate.onHintChange = { [weak self] hint in self?.waitingVersion = hint.waiting ? hint.version : nil }
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
        // `-VYPOScheduledCheckAtLaunch YES` runs the check the daily schedule runs (not one by hand), for the gold hint.
        if UserDefaults.standard.bool(forKey: "VYPOScheduledCheckAtLaunch") {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(3))
                self?.controller.updater.checkForUpdatesInBackground()
            }
        }
        // `-VYPOAutoClick YES` presses the update window's buttons for the test, a few seconds after each shows.
        if UserDefaults.standard.bool(forKey: "VYPOAutoClick") { Self.pressUpdateButtons() }
        #endif
    }

    /// “Check for Updates…”, “Check Now”, and the menu's “Update available” row: with an update waiting, Sparkle brings
    /// its window forward instead of asking again (`SPUUpdater.checkForUpdates`, `showUpdateInFocus`).
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

/// Whether an update found by the daily check waits for the user. Pure, so the rules are testable without Sparkle.
struct UpdateHint: Equatable {
    private(set) var waiting = false
    /// Sparkle's display version of the waiting update (`SUAppcastItem.displayVersionString`).
    private(set) var version = ""

    /// Sparkle is about to show an update. Only one the daily check found, and that vypo shows itself (Sparkle
    /// doesn't), waits; a check by hand always gets Sparkle's window and changes nothing here.
    mutating func willShowUpdate(handledBySparkle: Bool, userInitiated: Bool, version: String) {
        guard !handledBySparkle && !userInitiated else { return }
        waiting = true
        self.version = version
    }

    /// Sparkle's update session ends: the update was skipped, put off (“Remind Me Later”, or the window closed),
    /// or failed. An installed update relaunches vypo, which starts without a hint. After “Remind Me Later” the
    /// next daily check can set it again.
    mutating func sessionFinished() {
        waiting = false
        version = ""
    }
}

/// Sparkle's two delegates in one. vypo is a menu bar app, so an update that a daily check finds would open behind
/// the other apps; instead vypo shows it itself with Sparkle's “gentle reminders”: Sparkle keeps the window back
/// (`standardUserDriverShouldHandleShowingScheduledUpdate` → false), the mark turns gold, and the menu entry brings the
/// window forward with `checkForUpdates`. See https://sparkle-project.org/documentation/gentle-reminders.
///
/// In debug builds the feed can also be pointed elsewhere (`-VYPOFeedURL http://127.0.0.1:8000/appcast.xml`) to
/// test an update against a local server. Release builds don't have this at all.
@MainActor
final class UpdateDelegate: NSObject, @preconcurrency SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }
    var onCycleFinished: () -> Void = {}
    var onHintChange: (UpdateHint) -> Void = { _ in }
    private(set) var hint = UpdateHint() {
        didSet { if hint != oldValue { onHintChange(hint) } }
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        onCycleFinished()
    }

    /// Never a window for an update the daily check found, not even after days; the gold mark stands for it.
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        willShowUpdate(handledBySparkle: handleShowingUpdate, userInitiated: state.userInitiated, version: update.displayVersionString)
    }

    func standardUserDriverWillFinishUpdateSession() {
        hint.sessionFinished()
    }

    /// The part of `standardUserDriverWillHandleShowingUpdate` that doesn't need Sparkle's state object.
    func willShowUpdate(handledBySparkle: Bool, userInitiated: Bool, version: String) {
        hint.willShowUpdate(handledBySparkle: handledBySparkle, userInitiated: userInitiated, version: version)
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
