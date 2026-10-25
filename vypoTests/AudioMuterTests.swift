import CoreAudio
import XCTest
@testable import vypo

private final class MockOutput: AudioOutputHardware {
    var device: AudioDeviceID? = 42
    var muteSettable = true
    var volumeSettable = true
    var muted = false
    var vol: Float = 0.6

    func defaultOutputDevice() -> AudioDeviceID? { device }
    func uid(of device: AudioDeviceID) -> String? { "dev-\(device)" }
    func device(withUID uid: String) -> AudioDeviceID? { uid == "dev-42" ? 42 : nil }
    func isMuteSettable(_ device: AudioDeviceID) -> Bool { muteSettable }
    func isMuted(_ device: AudioDeviceID) -> Bool? { muted }
    func setMuted(_ device: AudioDeviceID, _ m: Bool) -> Bool { muted = m; return true }
    func isVolumeSettable(_ device: AudioDeviceID) -> Bool { volumeSettable }
    func volume(_ device: AudioDeviceID) -> Float? { vol }
    func setVolume(_ device: AudioDeviceID, _ v: Float) -> Bool { vol = v; return true }
}

private final class MemoryStore: PendingRestoreStore {
    var pending: PendingAudioRestore?
}

final class AudioMuterTests: XCTestCase {
    func testMutesAndRestores() {
        let hw = MockOutput(), store = MemoryStore()
        let muter = AudioMuter(hardware: hw, store: store)
        muter.mute()
        XCTAssertTrue(hw.muted)
        XCTAssertEqual(store.pending, PendingAudioRestore(deviceUID: "dev-42", unmute: true, volume: nil))
        muter.restore()
        XCTAssertFalse(hw.muted)
        XCTAssertNil(store.pending)
    }

    func testAlreadyMutedIsUntouched() {
        let hw = MockOutput(), store = MemoryStore()
        hw.muted = true
        let muter = AudioMuter(hardware: hw, store: store)
        muter.mute()
        muter.restore()
        XCTAssertTrue(hw.muted)
        XCTAssertNil(store.pending)
    }

    func testMuteNotSettableLowersVolumeAndRestores() {
        let hw = MockOutput(), store = MemoryStore()
        hw.muteSettable = false
        let muter = AudioMuter(hardware: hw, store: store)
        muter.mute()
        XCTAssertEqual(hw.vol, 0)
        XCTAssertEqual(store.pending?.volume, 0.6)
        muter.restore()
        XCTAssertEqual(hw.vol, 0.6)
    }

    func testUserVolumeChangeDuringRecordingIsKept() {
        let hw = MockOutput(), store = MemoryStore()
        hw.muteSettable = false
        let muter = AudioMuter(hardware: hw, store: store)
        muter.mute()
        hw.vol = 0.3
        muter.restore()
        XCTAssertEqual(hw.vol, 0.3)
    }

    func testPendingRestoreAtLaunchIsApplied() {
        let hw = MockOutput(), store = MemoryStore()
        hw.muted = true
        store.pending = PendingAudioRestore(deviceUID: "dev-42", unmute: true, volume: nil)
        AudioMuter(hardware: hw, store: store).restorePendingFromLastRun()
        XCTAssertFalse(hw.muted)
        XCTAssertNil(store.pending)
    }

    func testNeitherSettableDoesNothing() {
        let hw = MockOutput(), store = MemoryStore()
        hw.muteSettable = false
        hw.volumeSettable = false
        let muter = AudioMuter(hardware: hw, store: store)
        muter.mute()
        XCTAssertFalse(hw.muted)
        XCTAssertEqual(hw.vol, 0.6)
        XCTAssertNil(store.pending)
    }

    func testRestoresOnOriginalDeviceAfterDefaultChanges() {
        let hw = MockOutput(), store = MemoryStore()
        let muter = AudioMuter(hardware: hw, store: store)
        muter.mute()
        hw.device = 7
        muter.restore()
        XCTAssertFalse(hw.muted)
    }
}

final class RecordingFilterTests: XCTestCase {
    func testShortRecordingIsDiscardedSilently() {
        XCTAssertEqual(RecordingFilter.verdict(sampleCount: Int(16_000 * 0.29), peakDB: -20), .tooShort)
        XCTAssertEqual(RecordingFilter.verdict(sampleCount: Int(16_000 * 0.29), peakDB: -60), .tooShort)
        XCTAssertEqual(RecordingFilter.verdict(sampleCount: Int(16_000 * 0.31), peakDB: -20), .transcribe)
    }

    func testQuietRecordingSaysSo() {
        XCTAssertEqual(RecordingFilter.verdict(sampleCount: 32_000, peakDB: -50), .tooQuiet)
        XCTAssertEqual(RecordingFilter.verdict(sampleCount: 32_000, peakDB: -40.5), .tooQuiet)
        XCTAssertEqual(RecordingFilter.verdict(sampleCount: 32_000, peakDB: -39), .transcribe)
    }

    func testPaddingAddsSilenceOnBothSides() {
        let padded = AudioPadding.padded([1, 1])
        XCTAssertEqual(padded.count, 2 + 2 * 4_800)
        XCTAssertEqual(padded[4_799], 0)
        XCTAssertEqual(padded[4_800], 1)
        XCTAssertEqual(padded[4_801], 1)
        XCTAssertEqual(padded.last, 0)
    }

    func testSilentSamplesMeterBelowThreshold() {
        let meter = LevelMeter()
        meter.reset()
        let silence = [Float](repeating: 0.001, count: 1024)
        silence.withUnsafeBufferPointer { meter.process($0) }
        XCTAssertLessThanOrEqual(meter.peakDB, LevelMeter.silenceDB)
        let loud = [Float](repeating: 0.2, count: 1024)
        loud.withUnsafeBufferPointer { meter.process($0) }
        XCTAssertGreaterThan(meter.peakDB, LevelMeter.silenceDB)
    }
}
