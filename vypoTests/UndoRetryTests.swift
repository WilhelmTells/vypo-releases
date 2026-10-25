import XCTest
@testable import vypo

@MainActor
private final class MockAccess: InsertionAccess {
    var content: NSString
    var selection: NSRange
    var deleted = false
    var undone = false

    init(_ content: String, cursor: Int) {
        self.content = content as NSString
        selection = NSRange(location: cursor, length: 0)
    }

    func selectedRange() -> NSRange? { selection }
    func text(in range: NSRange) -> String? {
        guard range.location >= 0, NSMaxRange(range) <= content.length else { return nil }
        return content.substring(with: range)
    }
    func select(_ range: NSRange) -> Bool { selection = range; return true }
    func pressDelete() { deleted = true; content = content.replacingCharacters(in: selection, with: "") as NSString }
    func pressUndo() { undone = true }
}

@MainActor
final class UndoTests: XCTestCase {
    func testMatchingRangeIsDeleted() {
        let access = MockAccess("Hello there world", cursor: 17)
        let action = UndoPerformer.undo(" world", access: access)
        XCTAssertEqual(action, .deletedRange(NSRange(location: 11, length: 6)))
        XCTAssertEqual(access.content as String, "Hello there")
        XCTAssertFalse(access.undone)
    }

    func testOtherwiseCommandZ() {
        let access = MockAccess("Something else", cursor: 14)
        XCTAssertEqual(UndoPerformer.undo(" world", access: access), .commandZ)
        XCTAssertTrue(access.undone)
        XCTAssertFalse(access.deleted)
    }

    func testFiveMinuteExpiryClearsSamples() {
        let memory = DictationMemory()
        let t0 = Date()
        memory.store(samples: [0.1, 0.2], at: t0)
        memory.store(LastInsertion(text: "hi", pid: 1, date: t0, language: .en))
        memory.expire(now: t0.addingTimeInterval(299))
        XCTAssertNotNil(memory.samples)
        XCTAssertNotNil(memory.usable(frontPID: 1, now: t0.addingTimeInterval(299)))
        memory.expire(now: t0.addingTimeInterval(301))
        XCTAssertNil(memory.samples)
        XCTAssertNil(memory.last)
    }

    func testOnlyInTheSameApp() {
        let memory = DictationMemory()
        memory.store(LastInsertion(text: "hi", pid: 42, date: Date(), language: .en))
        XCTAssertNil(memory.usable(frontPID: 7))
        XCTAssertNotNil(memory.usable(frontPID: 42))
    }
}
