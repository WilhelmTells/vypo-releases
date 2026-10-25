import AppKit

/// Whether vypo is a menu bar app (`.accessory`) or a regular one with a Dock icon and its own
/// menu bar. `LSUIElement` stays on, so vypo starts as a menu bar app; this switches the activation
/// policy at runtime. vypo is regular while a window of its own is open (Settings, Onboarding), so
/// the menu bar reads “vypo” and ⌘W, ⌘, and ⌘C/⌘V reach it, and always with Dock on
/// (Settings → Appearance → Dock).
@MainActor
enum AppPresence {
    static func policy(showInDock: Bool, windowOpen: Bool) -> NSApplication.ActivationPolicy {
        showInDock || windowOpen ? .regular : .accessory
    }

    /// The policy vypo asked for last. Under unit tests only this changes: the test host stays a menu
    /// bar app, because the Dock keeps a tile, with a running dot, for each switch of a test host to
    /// regular that the runner's kill cuts short.
    private(set) static var current: NSApplication.ActivationPolicy = .accessory

    /// `activate` brings vypo forward so the Dock icon appears at once; not at launch, where vypo
    /// must not take focus, and not when the last window closes, where focus goes back.
    static func apply(showInDock: Bool, windowOpen: Bool, activate: Bool) {
        let policy = policy(showInDock: showInDock, windowOpen: windowOpen)
        current = policy
        if policy == .regular { MainMenu.install() }
        guard !AppDelegate.isRunningTests, NSApp.activationPolicy() != policy else { return }
        // Leaving the Dock deactivates vypo and drops its windows behind others; bring them back.
        let windows = NSApp.windows.filter { $0.isVisible && !($0 is NSPanel) }
        let key = NSApp.keyWindow
        NSApp.setActivationPolicy(policy)
        guard activate else { return }
        NSApp.activate()
        if policy == .accessory {
            for w in windows { w.orderFront(nil) }
            key?.makeKeyAndOrderFront(nil)
        }
    }
}

/// The menu bar while vypo is regular: vypo · Edit · Window, nothing more.
@MainActor
enum MainMenu {
    /// Opens Settings (set by the app delegate).
    static var openSettings: () -> Void = {}
    /// Opens Settings on the About page (set by the app delegate).
    static var openAbout: () -> Void = {}
    /// Looks for an update (set by the app delegate).
    static var checkForUpdates: () -> Void = {}

    private static var menu: NSMenu?

    /// Sets the menu, also over the one SwiftUI builds for its scenes.
    static func install() {
        let menu = menu ?? make()
        self.menu = menu
        if NSApp.mainMenu !== menu { NSApp.mainMenu = menu }
    }

    static func make() -> NSMenu {
        let main = NSMenu()

        let app = NSMenu(title: "vypo")
        app.addItem(ClosureMenuItem(String(localized: "About vypo")) { openAbout() })
        app.addItem(ClosureMenuItem(String(localized: "Check for Updates…")) { checkForUpdates() })
        app.addItem(.separator())
        app.addItem(ClosureMenuItem(String(localized: "Settings…"), keyEquivalent: ",") { openSettings() })
        app.addItem(.separator())
        app.addItem(withTitle: String(localized: "Quit vypo"),
                    action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        add(app, to: main)

        let edit = NSMenu(title: String(localized: "Edit"))
        edit.addItem(withTitle: String(localized: "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(.separator())
        edit.addItem(withTitle: String(localized: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: String(localized: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: String(localized: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: String(localized: "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        add(edit, to: main)

        let window = NSMenu(title: String(localized: "Window"))
        window.addItem(withTitle: String(localized: "Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        add(window, to: main)

        return main
    }

    private static func add(_ submenu: NSMenu, to main: NSMenu) {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        main.addItem(item)
    }
}
