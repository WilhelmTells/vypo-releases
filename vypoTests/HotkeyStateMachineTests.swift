import Carbon.HIToolbox
import XCTest
@testable import vypo

final class HotkeyStateMachineTests: XCTestCase {
    private var m = HotkeyStateMachine()

    override func setUp() { m = HotkeyStateMachine() }

    /// Feeds a press from `down` to `up`, ticking at each deadline the driver would schedule.
    private func press(_ down: TimeInterval, _ up: TimeInterval) -> [HotkeyStateMachine.Effect] {
        var effects = m.keyDown(at: down)
        if let d = m.deadline, d <= up { effects += m.tick(at: d) }
        effects += m.keyUp(at: up)
        return effects
    }

    private func settle(_ t: TimeInterval) -> [HotkeyStateMachine.Effect] {
        guard let d = m.deadline, d <= t else { return [] }
        return m.tick(at: d)
    }

    func testPress199msDoesNothing() {
        XCTAssertEqual(press(0, 0.199), [])
        XCTAssertEqual(settle(1), [])
        XCTAssertEqual(m.state, .idle)
    }

    func testPress200msStartsPushToTalk() {
        XCTAssertEqual(m.keyDown(at: 0), [])
        XCTAssertEqual(m.tick(at: 0.2), [.startPushToTalk])
        XCTAssertEqual(m.keyUp(at: 1.5), [.stopPushToTalk])
        XCTAssertEqual(m.state, .idle)
    }

    func testDoubleTapWithin350msStartsHandsFree() {
        XCTAssertEqual(press(0, 0.1), [])
        XCTAssertEqual(press(0.1 + 0.349, 0.55), [.startHandsFree])
        XCTAssertEqual(m.state, .handsFree)
    }

    func testGapOf351msDoesNothing() {
        XCTAssertEqual(press(0, 0.1), [])
        XCTAssertEqual(press(0.1 + 0.351, 0.5), [])
        XCTAssertEqual(settle(2), [])
        XCTAssertEqual(m.state, .idle)
    }

    func testKeyDownDuringHoldCancels() {
        _ = m.keyDown(at: 0)
        XCTAssertEqual(m.otherKey(at: 0.1), [])
        XCTAssertEqual(m.tick(at: 0.3), [])
        XCTAssertEqual(m.keyUp(at: 0.5), [])
        XCTAssertEqual(m.state, .idle)

        _ = m.keyDown(at: 1)
        XCTAssertEqual(m.tick(at: 1.2), [.startPushToTalk])
        XCTAssertEqual(m.otherKey(at: 1.5), [.cancelPushToTalk])
        XCTAssertEqual(m.keyUp(at: 1.6), [])
        XCTAssertEqual(m.state, .idle)
    }

    func testHandsFreeTapStops() {
        _ = press(0, 0.1)
        XCTAssertEqual(press(0.2, 0.3), [.startHandsFree])
        XCTAssertEqual(press(5, 5.1), [.stopHandsFree])
        XCTAssertEqual(m.state, .idle)
    }

    func testHandsFreeLongPressDoesNotStop() {
        _ = press(0, 0.1)
        _ = press(0.2, 0.3)
        XCTAssertEqual(press(5, 5.5), [])
        XCTAssertEqual(m.state, .handsFree)
    }

    func testHoldToTalkOffDisablesHold() {
        m.holdToTalk = false
        XCTAssertEqual(press(0, 1), [])
        XCTAssertEqual(m.state, .idle)
        // Double-tap still works.
        _ = press(2, 2.1)
        XCTAssertEqual(press(2.2, 2.3), [.startHandsFree])
    }

    func testDoubleTapOffDisablesHandsFree() {
        m.doubleTapHandsFree = false
        XCTAssertEqual(press(0, 0.1), [])
        XCTAssertEqual(press(0.2, 0.3), [])
        XCTAssertEqual(m.state, .idle)
        // Hold still works.
        _ = m.keyDown(at: 1)
        XCTAssertEqual(m.tick(at: 1.2), [.startPushToTalk])
    }

    func testReleaseAfterMissedTickStartsAndStops() {
        _ = m.keyDown(at: 0)
        XCTAssertEqual(m.keyUp(at: 0.25), [.startPushToTalk, .stopPushToTalk])
    }
}

/// `prepare` / `discardPrepared` around presses that may become recordings.
final class PreRollTests: XCTestCase {
    private var m = HotkeyStateMachine(preRoll: true)

    func testHoldPreparesThenStarts() {
        XCTAssertEqual(m.keyDown(at: 0), [.prepare])
        XCTAssertEqual(m.tick(at: 0.2), [.startPushToTalk])
        XCTAssertEqual(m.keyUp(at: 1), [.stopPushToTalk])
    }

    func testTapDiscards() {
        XCTAssertEqual(m.keyDown(at: 0), [.prepare])
        XCTAssertEqual(m.keyUp(at: 0.1), [.discardPrepared])
    }

    func testDoubleTapKeepsSecondPress() {
        _ = m.keyDown(at: 0)
        _ = m.keyUp(at: 0.1)
        XCTAssertEqual(m.keyDown(at: 0.2), [.prepare])
        XCTAssertEqual(m.keyUp(at: 0.3), [.startHandsFree])
    }

    func testOtherKeyDiscards() {
        _ = m.keyDown(at: 0)
        XCTAssertEqual(m.otherKey(at: 0.05), [.discardPrepared])
        XCTAssertEqual(m.keyUp(at: 0.1), [])
    }

    func testWithoutHoldToTalkFirstPressDoesntPrepare() {
        m.holdToTalk = false
        XCTAssertEqual(m.keyDown(at: 0), [])
        XCTAssertEqual(m.keyUp(at: 0.1), [.discardPrepared])
        XCTAssertEqual(m.keyDown(at: 0.2), [.prepare])
        XCTAssertEqual(m.keyUp(at: 0.3), [.startHandsFree])
    }

    func testPressDuringHandsFreeDoesntPrepare() {
        _ = m.keyDown(at: 0); _ = m.keyUp(at: 0.1); _ = m.keyDown(at: 0.2); _ = m.keyUp(at: 0.3)
        XCTAssertEqual(m.keyDown(at: 2), [])
        XCTAssertEqual(m.keyUp(at: 2.1), [.stopHandsFree])
    }
}

/// The custom dictation shortcut as the event tap sees it (`HotkeyMonitor.handle`).
@MainActor
final class CustomShortcutTests: XCTestCase {
    private let d = Int64(kVK_ANSI_D)
    private let ctrlOpt: CGEventFlags = [.maskControl, .maskAlternate]
    private var monitor = HotkeyMonitor()
    private var effects: [HotkeyStateMachine.Effect] = []

    override func setUp() {
        monitor = HotkeyMonitor()
        monitor.key = .custom
        monitor.customShortcut = .init(.d, modifiers: [.control, .option])
        effects = []
        // Pre-roll effects are covered by PreRollTests.
        monitor.onEffect = { [unowned self] in if $0 != .prepare && $0 != .discardPrepared { effects.append($0) } }
    }

    private func down(_ flags: CGEventFlags? = nil, repeat r: Bool = false) -> Bool {
        monitor.handle(type: .keyDown, flags: flags ?? ctrlOpt, keyCode: d, isRepeat: r)
    }

    private func up() -> Bool {
        monitor.handle(type: .keyUp, flags: ctrlOpt, keyCode: d, isRepeat: false)
    }

    private func wait(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    func testMatchesOnlyExactModifiers() {
        XCTAssertTrue(monitor.isCustomShortcut(flags: ctrlOpt, keyCode: d))
        XCTAssertTrue(monitor.isCustomShortcut(flags: ctrlOpt.union(.maskSecondaryFn), keyCode: d))
        XCTAssertFalse(monitor.isCustomShortcut(flags: [.maskControl], keyCode: d))
        XCTAssertFalse(monitor.isCustomShortcut(flags: ctrlOpt.union(.maskCommand), keyCode: d))
        XCTAssertFalse(monitor.isCustomShortcut(flags: ctrlOpt, keyCode: Int64(kVK_ANSI_F)))
        monitor.key = .fn
        XCTAssertFalse(monitor.isCustomShortcut(flags: ctrlOpt, keyCode: d))
    }

    func testHoldStartsAndStopsPushToTalk() {
        XCTAssertTrue(down())
        XCTAssertTrue(down(repeat: true), "repeats are swallowed")
        wait(0.3)
        XCTAssertEqual(effects, [.startPushToTalk])
        // Releasing a modifier first still ends the press on the key's key-up.
        XCTAssertTrue(down([.maskControl], repeat: true))
        XCTAssertTrue(up())
        XCTAssertEqual(effects, [.startPushToTalk, .stopPushToTalk])
    }

    func testDoubleTapStartsHandsFree() {
        XCTAssertTrue(down()); XCTAssertTrue(up())
        wait(0.05)
        XCTAssertTrue(down()); XCTAssertTrue(up())
        XCTAssertEqual(effects, [.startHandsFree])
    }

    func testDisabledPassesThrough() {
        monitor.enabled = false
        XCTAssertFalse(down())
        XCTAssertFalse(up())
        wait(0.3)
        XCTAssertEqual(effects, [])
    }

    func testOtherKeyWhileHeldCancels() {
        XCTAssertTrue(down())
        wait(0.3)
        XCTAssertFalse(monitor.handle(type: .keyDown, flags: ctrlOpt, keyCode: Int64(kVK_ANSI_F), isRepeat: false))
        XCTAssertTrue(up())
        XCTAssertEqual(effects, [.startPushToTalk, .cancelPushToTalk])
    }
}
