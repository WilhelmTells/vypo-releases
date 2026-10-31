import CoreAudio
import XCTest
@testable import vypo

/// The microphone is open only while recording and through the double-tap window after a short tap;
/// then the capture stops completely and the orange dot goes away. Drives the real controller with fn
/// events and asks CoreAudio whether this process still captures input. Needs the microphone permission.
@MainActor
final class MicReleaseTests: XCTestCase {
    /// The double-tap window, plus the time a capture session takes to stop.
    static let tapRelease = HotkeyStateMachine.doubleTapWindow + 0.65
    static let recordingRelease: TimeInterval = 0.5
    /// The longest a capture session may take to start once a recording began.
    static let captureStart: TimeInterval = 3

    private var app: AppState!
    private var hotkey: HotkeyMonitor!
    private var dictation: DictationController!

    override func setUp() async throws {
        guard Permissions.micGranted else { throw XCTSkip("needs the microphone permission") }
        guard let device = AudioDevices.resolveInputDevice(selectedUID: nil, preferBuiltIn: true),
              !AudioDevices.isBluetooth(device) else { throw XCTSkip("the pre-roll needs a wired or built-in mic") }
        let prefs = Preferences(defaults: UserDefaults(suiteName: "vypo.tests.\(UUID().uuidString)")!)
        app = AppState(prefs: prefs, store: Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        hotkey = HotkeyMonitor()
        dictation = DictationController(app: app, recorder: AudioRecorder(meter: app.levelMeter), muter: AudioMuter(), hotkey: hotkey)
        dictation.inputDevice = { device }
        XCTAssertNil(waitForRelease(within: 2), "something in this process already captures input")
    }

    override func tearDown() async throws {
        dictation?.shutdown()
    }

    /// The test host is the real app, launched like from /Applications: without any input the
    /// microphone stays closed, also past the double-tap window and the linger.
    func testTheMicIsClosedAfterLaunch() {
        let start = Date()
        while Date().timeIntervalSince(start) < Self.tapRelease + 0.5 {
            XCTAssertFalse(Self.capturingInput(), "the microphone is open without any input")
            wait(0.05)
        }
        XCTAssertEqual(dictation.phase, .idle)
    }

    /// The Level row meters only while the Recording pane is visible.
    func testTheRecordingPaneReleasesTheMicWhenLeftOrClosed() throws {
        let windows = WindowManager(app: app)
        windows.showSettings(.recording)
        let window = try XCTUnwrap(NSApp.windows.last { $0.title == String(localized: "vypo Settings") && $0.isVisible })
        defer { window.close() }
        XCTAssertTrue(waitForCapture(within: 2), "the Level row didn't start")

        app.settingsPane = .general
        assertReleased(within: Self.recordingRelease)

        app.settingsPane = .recording
        XCTAssertTrue(waitForCapture(within: 2), "the Level row didn't start again")
        window.close()
        assertReleased(within: Self.recordingRelease)

        // Reopened, the pane meters again, and closing releases again.
        windows.showSettings(.recording)
        XCTAssertTrue(waitForCapture(within: 2), "the Level row didn't start after reopening")
        window.close()
        assertReleased(within: Self.recordingRelease)
    }

    func testAHoldReleasesTheMicOnRelease() {
        down()
        // The capture session starts off the main thread; a fixed 0.4 s sometimes was not enough (failed once in
        // a full run on 2026-10-31, passed alone). Wait for it. The release times below stay strict.
        // The pre-roll opens the microphone on key-down, before the hold counts as a hold: wait for the recording itself.
        XCTAssertTrue(waitForPhase(.recording(handsFree: false), within: Self.captureStart), "the hold never became a recording")
        XCTAssertTrue(waitForCapture(within: Self.captureStart), "the microphone never opened")
        XCTAssertEqual(dictation.phase, .recording(handsFree: false))
        up()
        assertReleased(within: Self.recordingRelease)
    }

    func testAShortTapReleasesTheMicAfterTheDoubleTapWindow() {
        tap()
        let end = Date()
        assertOpened()
        assertReleased(within: Self.tapRelease, since: end)
        XCTAssertEqual(dictation.phase, .idle)
    }

    func testTwoTapsJustOutsideTheWindowRelease() {
        tap()
        wait(HotkeyStateMachine.doubleTapWindow + 0.03)
        tap()
        let end = Date()
        assertOpened()
        assertReleased(within: Self.tapRelease, since: end)
        XCTAssertEqual(dictation.phase, .idle)
    }

    func testFnWithAnotherKeyReleases() {
        down()
        wait(0.05)
        _ = hotkey.handle(type: .keyDown, flags: .maskSecondaryFn, keyCode: 123, isRepeat: false)
        wait(0.05)
        up()
        let end = Date()
        assertOpened()
        assertReleased(within: Self.tapRelease, since: end)
        XCTAssertEqual(dictation.phase, .idle)
    }

    func testHandsFreeReleasesWhenATapStopsIt() {
        tap()
        wait(0.1)
        tap()
        wait(0.6)
        XCTAssertEqual(dictation.phase, .recording(handsFree: true))
        XCTAssertTrue(waitForCapture(within: Self.captureStart), "the microphone never opened")
        tap()
        assertReleased(within: Self.recordingRelease)
    }

    func testTapThenHoldReleasesOnRelease() {
        tap()
        wait(0.1)
        down()
        wait(0.6)
        XCTAssertEqual(dictation.phase, .recording(handsFree: false))
        up()
        assertReleased(within: Self.recordingRelease)
    }

    func testManyTapsInARowRelease() {
        for _ in 0..<7 {
            tap()
            wait(HotkeyStateMachine.doubleTapWindow + 0.1)
        }
        tap()
        let end = Date()
        assertOpened()
        assertReleased(within: Self.tapRelease, since: end)
        XCTAssertEqual(dictation.phase, .idle)
    }

    func testEscDuringARecordingReleases() {
        down()
        wait(0.4)
        XCTAssertTrue(hotkey.onEscape())
        assertReleased(within: Self.recordingRelease)
        up()
        wait(Self.tapRelease)
        XCTAssertFalse(Self.capturingInput())
    }

    // MARK: Helpers

    private func down() { _ = hotkey.handle(type: .flagsChanged, flags: .maskSecondaryFn, keyCode: 63, isRepeat: false) }
    private func up() { _ = hotkey.handle(type: .flagsChanged, flags: [], keyCode: 63, isRepeat: false) }

    private func tap() {
        down()
        wait(0.06)
        up()
    }

    private func wait(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// Seconds until this process stops capturing input, or nil if it already doesn't.
    @discardableResult
    private func waitForRelease(within limit: TimeInterval) -> TimeInterval? {
        let start = Date()
        guard Self.capturingInput() else { return nil }
        while Date().timeIntervalSince(start) < limit + 3 {
            wait(0.02)
            if !Self.capturingInput() { return Date().timeIntervalSince(start) }
        }
        return .infinity
    }

    private func waitForPhase(_ phase: DictationController.Phase, within limit: TimeInterval) -> Bool {
        let start = Date()
        while dictation.phase != phase && Date().timeIntervalSince(start) < limit { wait(0.01) }
        return dictation.phase == phase
    }

    private func waitForCapture(within limit: TimeInterval) -> Bool {
        let start = Date()
        while !Self.capturingInput() && Date().timeIntervalSince(start) < limit { wait(0.01) }
        return Self.capturingInput()
    }

    /// A tap's pre-roll opened the microphone (otherwise a tap test proves nothing).
    private func assertOpened(file: StaticString = #filePath, line: UInt = #line) {
        let start = Date()
        while !Self.capturingInput() && Date().timeIntervalSince(start) < 0.3 { wait(0.005) }
        XCTAssertTrue(Self.capturingInput(), "the microphone never opened", file: file, line: line)
    }

    /// The microphone closes within `limit` of `end`, the end of the gesture.
    private func assertReleased(within limit: TimeInterval, since end: Date = Date(), file: StaticString = #filePath, line: UInt = #line) {
        while Self.capturingInput() && Date().timeIntervalSince(end) < limit + 3 { wait(0.02) }
        let released = Date().timeIntervalSince(end)
        XCTAssertLessThanOrEqual(released, limit, "the microphone was still open \(released) s later", file: file, line: line)
    }

    /// Whether CoreAudio reports this process as capturing input (what the orange dot shows).
    static func capturingInput() -> Bool {
        var address = AudioDevices.address(kAudioHardwarePropertyProcessObjectList)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return false }
        var processes = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &processes) == noErr else { return false }
        let me = getpid()
        return processes.contains { process in
            let pid: pid_t? = AudioDevices.value(process, kAudioProcessPropertyPID)
            let input: UInt32? = AudioDevices.value(process, kAudioProcessPropertyIsRunningInput)
            return pid == me && input == 1
        }
    }
}
