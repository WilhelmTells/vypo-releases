import XCTest
@testable import vypo

@MainActor
final class ProfileTests: XCTestCase {
    func testPromptStripsOneTrailingPeriodButKeepsQuestionMark() {
        XCTAssertEqual(ProfileTweaks.apply("Fix the bug.", mode: .prompt), "Fix the bug")
        XCTAssertEqual(ProfileTweaks.apply("Is it fixed?", mode: .prompt), "Is it fixed?")
        XCTAssertEqual(ProfileTweaks.apply("Done!", mode: .prompt), "Done!")
        XCTAssertEqual(ProfileTweaks.apply("Fix the bug.", mode: .standard), "Fix the bug.")
        var ctx = PipelineContext(language: .en)
        ctx.mode = .prompt
        XCTAssertEqual(TextPipeline.process("say \"hi\".", ctx), "say \"hi\"")
    }

    func testExcludedBlocksRecording() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let prefs = Preferences(defaults: UserDefaults(suiteName: "vypo.tests.\(UUID().uuidString)")!)
        let app = AppState(prefs: prefs, store: Store(directory: dir))
        // No apps until the user adds them.
        XCTAssertTrue(app.profiles.profiles.isEmpty)
        app.profiles.update(AppProfile(bundleID: "com.1password.1password", appName: "1Password", mode: .excluded))
        XCTAssertEqual(app.profiles.mode(for: "com.1password.1password"), .excluded)
        XCTAssertEqual(app.profiles.mode(for: "com.example.Other"), .standard)

        let hotkey = HotkeyMonitor()
        let dictation = DictationController(app: app, recorder: AudioRecorder(meter: app.levelMeter), muter: AudioMuter(), hotkey: hotkey)
        dictation.modeForApp = { _ in .excluded }
        var recorded = false
        dictation.onRecordingStarted = { _ in recorded = true }
        hotkey.onEffect(.startPushToTalk)
        XCTAssertFalse(recorded)
        XCTAssertEqual(dictation.phase, .idle)
        XCTAssertEqual(app.pillBase, .error(.offInThisApp))
        XCTAssertEqual(PillError.offInThisApp.duration, 2)
    }
}
