import Carbon.HIToolbox
import XCTest
@testable import vypo

/// A dictation without a text field stays on the clipboard until you paste it once.
@MainActor
final class ClipboardKeeperTests: XCTestCase {
    private var pb: NSPasteboard!
    private var keeper: ClipboardKeeper!

    override func setUp() {
        pb = NSPasteboard(name: .init("vypo.test.\(UUID().uuidString)"))
        pb.clearContents()
        pb.setString("before", forType: .string)
        keeper = ClipboardKeeper(pasteboard: pb, policy: .immediate)
    }

    override func tearDown() { pb.releaseGlobally() }

    private func settleTasks() { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }

    func testComesBackAfterYouPasteOnce() {
        keeper.keep("dictated", restoreAfterPaste: true, paste: false)
        XCTAssertEqual(pb.string(forType: .string), "dictated")
        settleTasks()
        XCTAssertEqual(pb.string(forType: .string), "dictated", "stays until you paste it")
        keeper.userPasted()
        settleTasks()
        XCTAssertEqual(pb.string(forType: .string), "before")
        XCTAssertFalse(keeper.isHolding)
    }

    func testSomethingCopiedMeanwhileStays() {
        keeper.keep("dictated", restoreAfterPaste: true, paste: false)
        pb.clearContents()
        pb.setString("copied by you", forType: .string)
        keeper.userPasted()
        settleTasks()
        XCTAssertEqual(pb.string(forType: .string), "copied by you")
    }

    func testWithoutRestoreTheDictationStays() {
        keeper.keep("dictated", restoreAfterPaste: false, paste: false)
        XCTAssertFalse(keeper.isHolding)
        keeper.userPasted()
        settleTasks()
        XCTAssertEqual(pb.string(forType: .string), "dictated")
    }

    func testASecondDictationKeepsTheFirstClipboard() {
        keeper.keep("one", restoreAfterPaste: true, paste: false)
        keeper.keep("two", restoreAfterPaste: true, paste: false)
        XCTAssertEqual(pb.string(forType: .string), "two")
        keeper.userPasted()
        settleTasks()
        XCTAssertEqual(pb.string(forType: .string), "before")
    }

    func testSettleBringsItBackBeforeTheNextPaste() {
        keeper.keep("dictated", restoreAfterPaste: true, paste: false)
        keeper.settle()
        XCTAssertEqual(pb.string(forType: .string), "before")
        XCTAssertFalse(keeper.isHolding)
    }

    func testTheTapReportsOnlyYourCommandV() {
        let monitor = HotkeyMonitor()
        var pastes = 0
        monitor.onPaste = { pastes += 1 }
        let v = Int64(kVK_ANSI_V)
        XCTAssertFalse(monitor.handle(type: .keyDown, flags: .maskCommand, keyCode: v, isRepeat: false), "never swallowed")
        XCTAssertEqual(pastes, 1)
        _ = monitor.handle(type: .keyDown, flags: .maskCommand, keyCode: v, isRepeat: false, synthetic: true)
        _ = monitor.handle(type: .keyDown, flags: .maskCommand, keyCode: v, isRepeat: true)
        _ = monitor.handle(type: .keyDown, flags: [.maskCommand, .maskAlternate], keyCode: v, isRepeat: false)
        _ = monitor.handle(type: .keyDown, flags: [], keyCode: v, isRepeat: false)
        XCTAssertEqual(pastes, 1)
    }

    func testRestoreWaitsASecond() {
        XCTAssertEqual(Paster.restoreDelay, .seconds(1))
        XCTAssertEqual(ClipboardKeeper(pasteboard: pb).policyForTests.fallback, Paster.restoreDelay)
    }

    func testSnapshotKnowsAFileWasCopied() {
        let file = NSPasteboardItem()
        file.setString("file:///tmp/a.wav", forType: .fileURL)
        pb.clearContents()
        pb.writeObjects([file])
        XCTAssertTrue(Paster.snapshot(pb).hasFileURL)
        pb.clearContents()
        pb.setString("text", forType: .string)
        XCTAssertFalse(Paster.snapshot(pb).hasFileURL)
    }
}
