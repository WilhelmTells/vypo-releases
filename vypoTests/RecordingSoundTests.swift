import XCTest
@testable import vypo

@MainActor
final class RecordingSoundTests: XCTestCase {
    func testEverySoundShipsWithStartAndStop() {
        for sound in RecordingSound.allCases where sound != .off {
            XCTAssertNotNil(sound.start, "\(sound) start")
            XCTAssertNotNil(sound.stop, "\(sound) stop")
            XCTAssertLessThan(sound.start?.duration ?? 1, 0.4, "\(sound) start stays short")
        }
        XCTAssertNil(RecordingSound.off.start)
        XCTAssertEqual(RecordingSound.standard, .glideShort)
    }
}
