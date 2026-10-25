import Synchronization
import XCTest
@testable import vypo

final class ParakeetProgressTests: XCTestCase {
    /// FluidAudio 0.17: the first `loadModels` downloads everything (0–0.5) and compiles (0.5–1);
    /// the other three find the files cached (0.5) and compile.
    func testDownloadFillsTheBarAndCompilesFinishIt() {
        let seen = Mutex<[Double]>([])
        let progress = ParakeetProgress(files: 4) { p in seen.withLock { $0.append(p) } }
        for f in [0, 0.1, 0.25, 0.4, 0.5, 0.75, 1] { progress.update(f) }
        for _ in 0..<3 { for f in [0.5, 0.75, 1] { progress.update(f) } }
        let values = seen.withLock { $0 }
        XCTAssertEqual(values[2], 0.45, accuracy: 1e-9, "half the download is half of the download share")
        XCTAssertEqual(values[4], 0.9, accuracy: 1e-9)
        XCTAssertEqual(values.last ?? 0, 1, accuracy: 1e-9)
        XCTAssertEqual(values, values.sorted(), "never goes backwards")
    }

    func testScaleLeavesRoomForTheHelper() {
        let last = Mutex(0.0)
        let progress = ParakeetProgress(files: 4, scale: 0.85) { p in last.withLock { $0 = p } }
        progress.update(0.5)
        XCTAssertEqual(last.withLock { $0 }, 0.9 * 0.85, accuracy: 1e-9)
    }
}
