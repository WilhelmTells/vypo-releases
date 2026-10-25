import XCTest
@testable import vypo

/// Drives the real pill panel on screen through a dictation's states. Opt-in, because a pill appears:
/// set `VYPO_PILL_LIVE` (via `TEST_RUNNER_VYPO_PILL_LIVE`). Guards the 2026-10-21 crashes, where AppKit threw
/// “more Update Constraints in Window passes than there are views in the window” while the pill animated.
@MainActor
final class PillLiveTests: XCTestCase {
    func testDictationStatesAnimateWithoutLayoutLoops() throws {
        guard ProcessInfo.processInfo.environment["VYPO_PILL_LIVE"] != nil else { throw XCTSkip("Live pill test is opt-in") }
        let scratch = Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let app = AppState(prefs: Preferences(defaults: UserDefaults(suiteName: "vypo.pill.\(UUID().uuidString)")!), store: scratch)
        let pill = PillController(app: app, positioner: PillPositioner(store: scratch))
        func pump(_ seconds: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        for _ in 0..<3 {
            for mode: PillMode in [.listening, .processing, .ready, .handsfree, .processing, .collapsed] {
                app.setPill(mode)
                pump(0.12)  // interrupt springs mid-flight too
            }
            pump(0.5)
        }
        app.setPill(.listening); pump(0.6)
        let panel = try XCTUnwrap(NSApp.windows.first { $0 is PillPanel && $0.isVisible })
        let listening = PillMetrics.size(for: .listening)
        XCTAssertEqual(panel.frame.width, listening.width + 2 * PillMetrics.margin, accuracy: 0.5, "panel settles to the pill's size")
        XCTAssertEqual(panel.frame.height, listening.height + 2 * PillMetrics.margin, accuracy: 0.5)

        app.setPill(.ready); pump(0.6)
        XCTAssertFalse(panel.isVisible, "no pill while idle")
        withExtendedLifetime(pill) {}
    }
}
