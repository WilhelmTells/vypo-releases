import XCTest
@testable import vypo

/// A short tap's pre-roll session lingers through the double-tap window instead of stopping at once.
final class PreRollLingerTests: XCTestCase {
    func testDoubleTapReusesTheSession() {
        var preRoll = PreRoll()
        XCTAssertEqual(preRoll.prepare(42), .start)
        XCTAssertTrue(preRoll.linger())
        XCTAssertEqual(preRoll.lingering, 42)
        // The second press within the window: no new session.
        XCTAssertEqual(preRoll.prepare(42), .reuse)
        XCTAssertNil(preRoll.lingering)
        XCTAssertFalse(preRoll.lingerEnded(), "the reused session isn't stopped when the window ends")
        XCTAssertTrue(preRoll.take(42))
        XCTAssertFalse(preRoll.discard())
    }

    func testASingleTapStopsWhenTheWindowEnds() {
        var preRoll = PreRoll()
        _ = preRoll.prepare(42)
        XCTAssertTrue(preRoll.linger())
        XCTAssertTrue(preRoll.lingerEnded())
        XCTAssertFalse(preRoll.lingerEnded())
        XCTAssertFalse(preRoll.discard())
    }

    func testAnotherDeviceStartsANewSession() {
        var preRoll = PreRoll()
        _ = preRoll.prepare(42)
        _ = preRoll.linger()
        XCTAssertEqual(preRoll.prepare(7), .start)
        XCTAssertNil(preRoll.lingering)
        XCTAssertFalse(preRoll.take(42))
        XCTAssertTrue(preRoll.take(7))
    }

    func testNothingToLingerOrStop() {
        var preRoll = PreRoll()
        XCTAssertFalse(preRoll.linger())
        XCTAssertFalse(preRoll.lingerEnded())
        XCTAssertFalse(preRoll.discard())
        _ = preRoll.prepare(42)
        _ = preRoll.linger()
        XCTAssertTrue(preRoll.discard(), "a lingering session is stopped at once by an error or quit")
    }
}
