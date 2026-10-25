import XCTest
@testable import vypo

/// The CTC helper for the glossary, when it's on, loads with the model, not on the first dictation: on 2026-10-23
/// the first dictation after an install waited 25.8 s for it. Uses the installed models. Opt-in: `TEST_RUNNER_VYPO_WARMUP=1`.
@MainActor
final class VocabularyWarmupTests: XCTestCase {
    func testHelperLoadsWithTheModel() async throws {
        guard ProcessInfo.processInfo.environment["VYPO_WARMUP"] != nil else { throw XCTSkip("Warm-up test is opt-in") }
        let models = ModelManager(store: .shared)
        guard models.isInstalled(.parakeetUltra), models.isInstalled(.ctcVocab) else { throw XCTSkip("Install Parakeet Ultra in vypo first") }
        let engines = EngineManager(models: models)
        engines.helperEnabled = true
        let engine = try XCTUnwrap(engines.engine(for: .parakeetUltra) as? ParakeetEngine)
        try await engine.load()

        // Nothing else is asked of the engine: the helper has to come on its own.
        let deadline = Date().addingTimeInterval(60)
        while !(await engine.isVocabularyLoaded), Date() < deadline {
            try await Task.sleep(for: .milliseconds(200))
        }
        let loaded = await engine.isVocabularyLoaded
        XCTAssertTrue(loaded)

        // The first dictation with a glossary then doesn't wait for it.
        let audio = try TestSpeech.say("We run everything on Kubernetes now.", voice: "Samantha")
        let clock = ContinuousClock()
        let start = clock.now
        _ = try await engine.transcribe(audio, language: nil, glossary: [GlossaryEntry(term: "Kubernetes", soundsLike: ["cooper netties"])])
        let elapsed = clock.now - start
        print("WARMUP first dictation with glossary: \(elapsed.milliseconds) ms")
        XCTAssertLessThan(elapsed, .seconds(2))
        await engines.unload(.parakeetUltra)
    }
}
