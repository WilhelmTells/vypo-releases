import XCTest
@testable import vypo

/// Defaults of Settings → Appearance.
@MainActor
final class AppearanceSettingsTests: XCTestCase {
    func testDefaults() {
        let prefs = Preferences(defaults: UserDefaults(suiteName: "vypo.appearance.\(UUID().uuidString)")!)
        XCTAssertFalse(prefs.menuBarTintWhileDictating)
        XCTAssertTrue(prefs.showPill)
        XCTAssertFalse(prefs.showInDock)
    }
}
