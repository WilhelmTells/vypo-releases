import AppKit
import XCTest
@testable import vypo

/// While a vypo window is open, vypo is a regular app with its own menu bar (vypo · Edit · Window),
/// so ⌘W, ⌘, and ⌘C/⌘V reach it; with the last window closed it is a menu bar app again, unless
/// Dock is on.
@MainActor
final class AppPresenceTests: XCTestCase {
    private var app: AppState!
    private var windows: WindowManager!

    override func setUp() async throws {
        let prefs = Preferences(defaults: UserDefaults(suiteName: "vypo.tests.\(UUID().uuidString)")!)
        app = AppState(prefs: prefs, store: Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        windows = WindowManager(app: app)
    }

    override func tearDown() async throws {
        for w in NSApp.windows where w.isVisible && !(w is NSPanel) { w.close() }
        AppPresence.apply(showInDock: false, windowOpen: false, activate: false)
        // The test host itself never leaves the menu bar: a host killed while regular leaves a
        // Dock tile behind.
        XCTAssertEqual(NSApp.activationPolicy(), .accessory)
    }

    func testPolicy() {
        XCTAssertEqual(AppPresence.policy(showInDock: false, windowOpen: false), .accessory)
        XCTAssertEqual(AppPresence.policy(showInDock: false, windowOpen: true), .regular)
        XCTAssertEqual(AppPresence.policy(showInDock: true, windowOpen: false), .regular)
        XCTAssertEqual(AppPresence.policy(showInDock: true, windowOpen: true), .regular)
    }

    func testAboutVypoOpensSettingsOnTheAboutPage() {
        var opened: [SettingsPane?] = []
        app.onOpenSettings = { opened.append($0) }
        app.openAbout()
        XCTAssertEqual(opened, [.about])
        XCTAssertEqual(SettingsPane.about.title, String(localized: "About"))
        XCTAssertEqual(SettingsPane.visible.last, .about, "last in the sidebar, under Stats")
    }

    func testTheMenuBarIsVypoEditWindow() throws {
        let menu = MainMenu.make()
        XCTAssertEqual(menu.items.map(\.title), ["vypo", String(localized: "Edit"), String(localized: "Window")])
        let app = try XCTUnwrap(menu.items[0].submenu)
        XCTAssertEqual(entries(app), [String(localized: "About vypo"), String(localized: "Check for Updates…"), String(localized: "Settings…") + " ⌘,", String(localized: "Quit vypo") + " ⌘q"])
        let edit = try XCTUnwrap(menu.items[1].submenu)
        XCTAssertEqual(entries(edit), ["Undo ⌘z", "Cut ⌘x", "Copy ⌘c", "Paste ⌘v", "Select All ⌘a"].map(localizedEntry))
        XCTAssertEqual(edit.items.compactMap(\.action),
                       [Selector(("undo:")), #selector(NSText.cut(_:)), #selector(NSText.copy(_:)), #selector(NSText.paste(_:)), #selector(NSText.selectAll(_:))])
        let window = try XCTUnwrap(menu.items[2].submenu)
        XCTAssertEqual(entries(window), [String(localized: "Close") + " ⌘w"])
        XCTAssertEqual(window.items[0].action, #selector(NSWindow.performClose(_:)))
    }

    func testSettingsMakesVypoRegularUntilClosed() throws {
        XCTAssertEqual(AppPresence.current, .accessory)
        windows.showSettings(.general)
        XCTAssertTrue(windows.isWindowOpen)
        XCTAssertEqual(AppPresence.current, .regular)
        XCTAssertEqual(NSApp.mainMenu?.items.map(\.title), ["vypo", String(localized: "Edit"), String(localized: "Window")])

        let window = try settingsWindow()
        window.performClose(nil)
        XCTAssertFalse(windows.isWindowOpen)
        XCTAssertEqual(AppPresence.current, .accessory)

        // Reopened: the content and the menu bar are back.
        windows.showSettings()
        XCTAssertEqual(AppPresence.current, .regular)
        XCTAssertNotNil(window.contentView)
        XCTAssertTrue(window.isVisible)
        window.performClose(nil)
        XCTAssertEqual(AppPresence.current, .accessory)
    }

    func testDockOnKeepsVypoRegularWithoutAWindow() throws {
        app.prefs.showInDock = true
        windows.showSettings(.appearance)
        XCTAssertEqual(AppPresence.current, .regular)
        try settingsWindow().performClose(nil)
        XCTAssertEqual(AppPresence.current, .regular)
    }

    func testOnboardingAndSettingsTogether() throws {
        windows.showOnboarding(step: 0)
        XCTAssertEqual(AppPresence.current, .regular)
        windows.showSettings(.general)
        windows.closeOnboarding()
        XCTAssertEqual(AppPresence.current, .regular, "Settings is still open")
        try settingsWindow().performClose(nil)
        XCTAssertEqual(AppPresence.current, .accessory)

        windows.showOnboarding(step: 0)
        XCTAssertEqual(AppPresence.current, .regular)
        windows.closeOnboarding()
        XCTAssertEqual(AppPresence.current, .accessory)
    }

    private func settingsWindow() throws -> NSWindow {
        try XCTUnwrap(NSApp.windows.last { $0.title == String(localized: "vypo Settings") && $0.isVisible })
    }

    private func entries(_ menu: NSMenu) -> [String] {
        menu.items.filter { !$0.isSeparatorItem }.map { $0.keyEquivalent.isEmpty ? $0.title : "\($0.title) ⌘\($0.keyEquivalent)" }
    }

    private func localizedEntry(_ entry: String) -> String {
        let parts = entry.components(separatedBy: " ⌘")
        return String(localized: String.LocalizationValue(parts[0])) + " ⌘" + parts[1]
    }

    /// A test host, also one left running, never listens for fn: only the app delegate's startup
    /// builds the coordinator, and the event tap refuses under tests.
    func testTheTestHostNeverListensForFn() {
        XCTAssertNil((NSApp.delegate as? AppDelegate)?.coordinator)
        let hotkey = HotkeyMonitor()
        hotkey.start()
        XCTAssertFalse(hotkey.isInstalled)
    }
}
