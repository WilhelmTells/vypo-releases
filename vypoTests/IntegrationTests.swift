import AVFoundation
import XCTest
@testable import vypo

/// Downloads real models and transcribes generated speech. Opt-in: set `VYPO_INTEGRATION_DIR`
/// (via `TEST_RUNNER_VYPO_INTEGRATION_DIR`) to a scratch folder; models go there, not to Application Support.
@MainActor
final class IntegrationTests: XCTestCase {
    private var dir: URL? {
        ProcessInfo.processInfo.environment["VYPO_INTEGRATION_DIR"].map { URL(fileURLWithPath: $0) }
    }

    private func speech(_ text: String, voice: String = "Samantha") throws -> [Float] {
        try TestSpeech.say(text, voice: voice)
    }

    private func install(_ id: ModelID, _ manager: ModelManager) async throws {
        manager.download(id)
        let deadline = Date().addingTimeInterval(1800)
        while manager.state(id) != .installed {
            if manager.state(id) == .failed { XCTFail("download failed"); return }
            if Date() > deadline { XCTFail("timeout"); return }
            try await Task.sleep(for: .seconds(1))
        }
    }

    func testParakeetEndToEnd() async throws {
        guard let dir else { throw XCTSkip("Integration tests are opt-in") }
        let manager = ModelManager(store: Store(directory: dir))
        try await install(.parakeetUltra, manager)
        let engines = EngineManager(models: manager)
        let engine = try XCTUnwrap(engines.engine(for: .parakeetUltra))

        let plain = try await engine.transcribe(try speech("Please deploy the new service on Monday."), language: nil)
        print("PARAKEET:", plain)
        let lastPlain = await engine.lastTiming
        let plainTiming = try XCTUnwrap(lastPlain)
        XCTAssertGreaterThan(plainTiming.decode, .zero)
        XCTAssertTrue(plain.lowercased().contains("deploy"), plain)
        let german = try await engine.transcribe(try speech("Guten Morgen, wie geht es dir heute?", voice: "Anna"), language: nil)
        print("PARAKEET DE:", german)
        XCTAssertTrue(german.lowercased().contains("morgen"), german)
        await engines.unload(.parakeetUltra)
    }
}

/// Records from the built-in mic for real. Opt-in: set `VYPO_MIC_TEST` (via `TEST_RUNNER_VYPO_MIC_TEST`).
final class RecorderHardwareTests: XCTestCase {
    func testCapturesSixteenKilohertzFromTheBuiltInMic() throws {
        guard ProcessInfo.processInfo.environment["VYPO_MIC_TEST"] != nil else { throw XCTSkip("Mic test is opt-in") }
        let device = try XCTUnwrap(AudioDevices.inputDevices().first(where: \.isBuiltIn)?.id)
        let meter = LevelMeter()
        let recorder = AudioRecorder(meter: meter)
        try recorder.start(device: device)
        Thread.sleep(forTimeInterval: 2)
        let samples = recorder.stop()
        let seconds = Double(samples.count) / AudioRecorder.sampleRate
        // Session start-up eats a little at the front; a wrong rate would be off by 3×.
        XCTAssertGreaterThan(seconds, 1.4)
        XCTAssertLessThan(seconds, 2.1)
        XCTAssertGreaterThan(meter.peakDB, -160, "got real audio, not zeros")
        XCTAssertFalse(recorder.isRunning)
    }
}
