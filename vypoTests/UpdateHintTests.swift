import AppKit
import Sparkle
import XCTest
@testable import vypo

/// The gold update hint: when an update waits, when it ends, and how the menu bar mark shows it. Sparkle itself
/// isn't started here (no feed, no network); its delegate calls are made by hand in the order Sparkle makes them.
final class UpdateHintTests: XCTestCase {
    // MARK: State

    func testStartsWithoutAnUpdateWaiting() {
        // Also after an installed update: Sparkle relaunches vypo, and a new launch starts here.
        XCTAssertFalse(UpdateHint().waiting)
    }

    func testDailyCheckFindingAnUpdateWaits() {
        var hint = UpdateHint()
        hint.willShowUpdate(handledBySparkle: false, userInitiated: false, version: "0.6.0")
        XCTAssertTrue(hint.waiting)
        XCTAssertEqual(hint.version, "0.6.0", "the menu row shows Sparkle's display version")
    }

    func testCheckByHandNeverWaits() {
        var hint = UpdateHint()
        // Sparkle always shows the window for a check by hand (`handleShowingUpdate` is true then).
        hint.willShowUpdate(handledBySparkle: true, userInitiated: true, version: "0.6.0")
        XCTAssertFalse(hint.waiting)
        XCTAssertEqual(hint.version, "")
    }

    func testUpdateSparkleShowsItselfDoesNotWait() {
        var hint = UpdateHint()
        hint.willShowUpdate(handledBySparkle: true, userInitiated: false, version: "0.6.0")
        XCTAssertFalse(hint.waiting)
    }

    func testSkipRemindLaterOrErrorEndsIt() {
        // “Skip This Version”, “Remind Me Later”, closing the window and a failed install all end Sparkle's session.
        var hint = UpdateHint()
        hint.willShowUpdate(handledBySparkle: false, userInitiated: false, version: "0.6.0")
        hint.sessionFinished()
        XCTAssertFalse(hint.waiting)
        XCTAssertEqual(hint.version, "")
    }

    func testAfterRemindLaterTheNextDailyCheckWaitsAgain() {
        var hint = UpdateHint()
        hint.willShowUpdate(handledBySparkle: false, userInitiated: false, version: "0.6.0")
        hint.sessionFinished()
        hint.willShowUpdate(handledBySparkle: false, userInitiated: false, version: "0.6.0")
        XCTAssertTrue(hint.waiting)
    }

    func testNewerUpdateAfterRemindLaterShowsItsVersion() {
        var hint = UpdateHint()
        hint.willShowUpdate(handledBySparkle: false, userInitiated: false, version: "0.6.0")
        hint.sessionFinished()
        hint.willShowUpdate(handledBySparkle: false, userInitiated: false, version: "0.6.1")
        XCTAssertEqual(hint.version, "0.6.1")
    }

    func testCheckByHandWhileWaitingKeepsIt() {
        // With an update waiting, Sparkle brings that window forward; the gold stays until the user decides.
        var hint = UpdateHint()
        hint.willShowUpdate(handledBySparkle: false, userInitiated: false, version: "0.6.0")
        hint.willShowUpdate(handledBySparkle: true, userInitiated: true, version: "0.6.0")
        XCTAssertTrue(hint.waiting)
    }

    // MARK: Sparkle delegate

    @MainActor func testDelegateKeepsSparklesWindowBackForScheduledUpdates() {
        let delegate = UpdateDelegate()
        XCTAssertTrue(delegate.supportsGentleScheduledUpdateReminders)
        XCTAssertFalse(delegate.standardUserDriverShouldHandleShowingScheduledUpdate(.empty(), andInImmediateFocus: true))
        XCTAssertFalse(delegate.standardUserDriverShouldHandleShowingScheduledUpdate(.empty(), andInImmediateFocus: false))
    }

    @MainActor func testDelegateReportsEachChangeOnce() {
        let delegate = UpdateDelegate()
        var changes: [Bool] = []
        delegate.onHintChange = { changes.append($0.waiting) }
        delegate.willShowUpdate(handledBySparkle: true, userInitiated: true, version: "0.6.0")
        delegate.willShowUpdate(handledBySparkle: false, userInitiated: false, version: "0.6.0")
        delegate.willShowUpdate(handledBySparkle: false, userInitiated: false, version: "0.6.0")
        delegate.standardUserDriverWillFinishUpdateSession()
        delegate.standardUserDriverWillFinishUpdateSession()
        XCTAssertEqual(changes, [true, false])
        XCTAssertFalse(delegate.hint.waiting)
    }

    // MARK: Menu bar mark

    func testMarkRestsInGoldWhileAnUpdateWaits() {
        var t = MenuBarMarkTimeline()
        t.updateWaiting = true
        XCTAssertTrue(t.isAnimating)
        var f = MenuBarMarkFrame()
        for i in 0...20 { f = t.advance(to: Double(i) * 0.016, level: 0) }
        XCTAssertEqual(f.gold, 1)
        XCTAssertEqual(f.tint, 0)
        // Gold and still: no display link while it waits.
        XCTAssertFalse(t.isAnimating)

        t.updateWaiting = false
        for i in 0...20 { f = t.advance(to: 1 + Double(i) * 0.016, level: 0) }
        XCTAssertEqual(f, .rest)
        XCTAssertFalse(t.isAnimating)
    }

    func testDictationKeepsPriorityThenGoldComesBack() {
        var t = MenuBarMarkTimeline()
        t.updateWaiting = true
        for i in 0...20 { _ = t.advance(to: Double(i) * 0.016, level: 0) }

        t.beginRecording(at: 1)
        var f = MenuBarMarkFrame()
        for i in 0...20 { f = t.advance(to: 1 + Double(i) * 0.016, level: 0) }
        XCTAssertEqual(f.gold, 0, "recording looks as always")
        t.beginProcessing(at: 2)
        f = t.advance(to: 2.3, level: 0)
        XCTAssertEqual(f.gold, 0, "processing looks as always")
        XCTAssertNotNil(f.coaster)

        t.inserted(at: 3)
        XCTAssertEqual(t.advance(to: 3.1, level: 0).gold, 0, "the star flies first")
        for i in 0...40 { f = t.advance(to: 3.22 + Double(i) * 0.016, level: 0) }
        XCTAssertEqual(f.gold, 1)
    }

    func testTintOptionShowsAccentNotGoldWhileDictating() {
        var t = MenuBarMarkTimeline()
        t.tintOption = true
        t.updateWaiting = true
        t.beginRecording(at: 0)
        var f = MenuBarMarkFrame()
        for i in 0...30 { f = t.advance(to: Double(i) * 0.016, level: 0) }
        XCTAssertEqual(f.tint, 1)
        XCTAssertEqual(f.gold, 0)
        t.failed(at: 1)
        for i in 0...60 { f = t.advance(to: 1 + Double(i) * 0.016, level: 0) }
        XCTAssertEqual(f.tint, 0)
        XCTAssertEqual(f.gold, 1)
    }

    @MainActor func testGoldMarkIsNoTemplate() {
        XCTAssertTrue(MenuBarMarkRenderer.image(.rest).isTemplate)
        var gold = MenuBarMarkFrame()
        gold.gold = 1
        XCTAssertFalse(MenuBarMarkRenderer.image(gold).isTemplate)
        XCTAssertNotNil(NSColor(named: "update-gold"))
    }
}
