import Foundation
import Synchronization

/// RMS level meter (§8): RMS per buffer → dBFS → 0–1 over −50…−10 dBFS, smoothed with attack 0.5 / release 0.1.
/// Written from the audio thread, read by the UI at display refresh.
final class LevelMeter: Sendable {
    private struct State {
        var smoothed: Float = 0
        var peakDB: Float = -160
        var lastLoudAt: Date = .distantPast
    }

    static let silenceDB: Float = -45
    /// Above digital silence: the microphone delivers real sound. Bluetooth mics start with
    /// about 0.6 s of exact zeros (−160 dBFS) while they switch modes.
    static let liveDB: Float = -100
    private let state = Mutex(State())

    init() {}

    /// Smoothed level 0–1 for drawing.
    var level: Float { state.withLock { $0.smoothed } }

    /// Highest buffer RMS seen since `reset()`, in dBFS.
    var peakDB: Float { state.withLock { $0.peakDB } }

    /// When the RMS last exceeded −45 dBFS.
    var lastLoudAt: Date { state.withLock { $0.lastLoudAt } }

    func reset() {
        state.withLock { $0 = State(lastLoudAt: Date()) }
    }

    /// Feed one buffer of mono samples.
    func process(_ samples: UnsafeBufferPointer<Float>) {
        let db = Self.dbfs(rms: Self.rms(samples))
        let target = Self.normalize(db: db)
        state.withLock { s in
            let k: Float = target > s.smoothed ? 0.5 : 0.1
            s.smoothed += (target - s.smoothed) * k
            s.peakDB = max(s.peakDB, db)
            if db > Self.silenceDB { s.lastLoudAt = Date() }
        }
    }

    static func rms(_ samples: UnsafeBufferPointer<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        return (sum / Float(samples.count)).squareRoot()
    }

    static func dbfs(rms: Float) -> Float { rms > 0 ? 20 * log10(rms) : -160 }

    static func normalize(db: Float) -> Float { min(max((db + 50) / 40, 0), 1) }
}
