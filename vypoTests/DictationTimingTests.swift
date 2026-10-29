import XCTest
@testable import vypo

/// The timing line per dictation: every section, memory and the pause, and numbers only.
final class DictationTimingTests: XCTestCase {
    private let memory = MemorySnapshot(freePercent: 34, pressureLevel: 2, compressedBytes: 2_576_980_378, footprintBytes: 154_140_672)

    func testTheLineHasEverySection() {
        let asr = TranscriptionTiming(decode: .milliseconds(1657))
        let line = DictationTimingLog.line(audio: 48.54, pause: 576, transcribe: .milliseconds(6080), asr: asr,
                                           text: .milliseconds(61), ready: .milliseconds(6141), memory: memory)
        XCTAssertEqual(line, "Dictation timing: audio 48.5 s; pause 9.6 min; "
            + "transcribe 6080 ms (decode 1657 ms); "
            + "text 61 ms; ready 6141 ms; memory free 34 %, pressure warning, compressed 2.4 GB, vypo 147 MB")
    }

    func testFirstDictationSinceLaunch() {
        let line = DictationTimingLog.line(audio: 3, pause: nil, transcribe: .milliseconds(400),
                                           asr: TranscriptionTiming(decode: .milliseconds(390)),
                                           text: .milliseconds(2), ready: .milliseconds(402), memory: memory)
        XCTAssertTrue(line.contains("first since launch"), line)
        XCTAssertTrue(line.contains("(decode 390 ms)"), line)
    }

    func testUnknownEngineTiming() {
        let line = DictationTimingLog.line(audio: 3, pause: 30, transcribe: .milliseconds(400), asr: nil,
                                           text: .milliseconds(2), ready: .milliseconds(402), memory: memory)
        XCTAssertTrue(line.contains("transcribe 400 ms; text"), line)
    }

    func testTheMemorySnapshotReadsTheSystem() {
        let now = MemorySnapshot.current()
        XCTAssertTrue((0...100).contains(now.freePercent), "\(now.freePercent)")
        XCTAssertTrue([1, 2, 4].contains(now.pressureLevel), "\(now.pressureLevel)")
        XCTAssertGreaterThan(now.footprintBytes, 1_000_000)
    }

    func testShortPausesInSeconds() {
        func pause(_ seconds: TimeInterval) -> String {
            DictationTimingLog.line(audio: 3, pause: seconds, transcribe: .zero, asr: nil, text: .zero, ready: .zero, memory: memory)
        }
        XCTAssertTrue(pause(2.6).contains("; pause 3 s;"))
        XCTAssertTrue(pause(59.4).contains("; pause 59 s;"))
        XCTAssertTrue(pause(78).contains("; pause 1.3 min;"))
    }
}
