import SwiftUI

@main
struct vypoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    /// The menu bar icon is an AppKit status item (`StatusItemController`); SwiftUI only needs a scene.
    var body: some Scene {
        // The menu bar itself is AppKit too (`MainMenu`).
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let app = AppState()
    private(set) var coordinator: AppCoordinator?
    private var statusItem: StatusItemController?

    /// Unit tests run inside the app; skip startup side effects then.
    static var isRunningTests: Bool { RunEnvironment.isTesting }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        // The test app never looks for updates (it is a throwaway copy with its own bundle ID).
        app.updates = RunEnvironment.isTestApp ? nil : Updates()
        coordinator = AppCoordinator(app: app)
        coordinator?.start()
        statusItem = StatusItemController(app: app)
        MainMenu.openSettings = { [weak self] in self?.app.openSettings() }
        MainMenu.openAbout = { [weak self] in self?.app.openAbout() }
        MainMenu.checkForUpdates = { [weak self] in self?.app.updates?.checkNow() }
        AppPresence.apply(showInDock: app.prefs.showInDock, windowOpen: coordinator?.windows.isWindowOpen ?? false, activate: false)
        observeChanges { [weak self] in
            guard let self else { return }
            let show = self.app.prefs.showInDock
            // Read for tracking; applied after this pass, so the toggle's own update isn't in its way.
            Task { @MainActor in
                AppPresence.apply(showInDock: show, windowOpen: self.coordinator?.windows.isWindowOpen ?? false, activate: true)
            }
        }
    }

    /// A click on the Dock icon opens Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { app.openSettings() }
        return true
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem(String(localized: "Settings…")) { [weak self] in self?.app.openSettings() })
        return menu
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.shutdown()
    }
}
