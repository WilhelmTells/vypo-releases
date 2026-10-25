import AVFoundation
import XCTest
@testable import vypo

final class BenchmarkRecordingsTests: XCTestCase {
    private func scratch() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    func testKeepWritesReadableWAV() throws {
        let samples = (0..<16_000).map { Float(sin(Double($0) / 10)) * 0.1 }
        let url = try XCTUnwrap(BenchmarkRecordings.keep(samples, at: Date(timeIntervalSince1970: 0), in: scratch()))
        XCTAssertTrue(url.lastPathComponent.hasSuffix(".wav"))
        XCTAssertEqual(try WAVFile.read(url).count, 16_000)
    }

    func testReadResamplesToSixteenKilohertz() throws {
        let url = scratch().appendingPathExtension("wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)!
        buffer.frameLength = 44_100
        for i in 0..<44_100 { buffer.floatChannelData![0][i] = Float(sin(Double(i) / 20)) * 0.1 }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        file.close()
        XCTAssertEqual(try WAVFile.read(url).count, 16_000, accuracy: 50)
    }

    func testNamesSortByTime() throws {
        let dir = scratch()
        let a = try XCTUnwrap(BenchmarkRecordings.keep([0.1], at: Date(timeIntervalSince1970: 100), in: dir))
        let b = try XCTUnwrap(BenchmarkRecordings.keep([0.1], at: Date(timeIntervalSince1970: 100.5), in: dir))
        XCTAssertLessThan(a.lastPathComponent, b.lastPathComponent)
    }

    func testWriteFailureDoesNotThrowOutOfKeep() {
        let file = scratch()
        FileManager.default.createFile(atPath: file.path, contents: Data())   // a file where the folder should be
        XCTAssertNil(BenchmarkRecordings.keep([0.1], in: file))
    }
}
