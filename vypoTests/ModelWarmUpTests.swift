import XCTest
@testable import vypo

/// An engine that counts, so the warm-up logic runs without the real model (and without Core ML's cache).
private actor FakeEngine: ASREngine {
    private(set) var loads = 0
    private(set) var warmUps = 0
    private(set) var transcriptions = 0
    private var loaded = false
    private(set) var isWarm = false
    var lastTiming: TranscriptionTiming?
    /// Holds `warmUp` until released, to test a dictation arriving meanwhile.
    var warmUpGate: AsyncStream<Void>.Continuation?
    private var gateStream: AsyncStream<Void>?

    var isLoaded: Bool { loaded }

    func load() async throws {
        guard !loaded else { return }
        loaded = true
        loads += 1
    }

    func unload() async {
        loaded = false
        isWarm = false
    }

    func holdWarmUp() {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        gateStream = stream
        warmUpGate = continuation
    }

    func warmUp() async {
        guard loaded, !isWarm else { return }
        warmUps += 1
        if let gateStream {
            for await _ in gateStream { break }
        }
        isWarm = true
    }

    func transcribe(_ samples: [Float], language: Lang?) async throws -> String {
        try await load()
        transcriptions += 1
        isWarm = true
        return "text"
    }
}

@MainActor
final class ModelWarmUpTests: XCTestCase {
    // MARK: The pill state

    func testTheLoadingStatusIsAPillModeWithItsOwnTextAndLabel() {
        XCTAssertEqual(PillMode.loadingModelText, "Loading speech model…")
        XCTAssertEqual(PillMode.loadingModel.accessibilityLabel, PillMode.loadingModelText)
        XCTAssertTrue(PillMode.loadingModel.isProcessing)
        XCTAssertTrue(PillMode.processing.isProcessing)
        XCTAssertFalse(PillMode.listening.isProcessing)
        XCTAssertFalse(PillMode.loadingModel.isRecording)
    }

    func testThePillWidensForTheTextAndNeverShortensIt() {
        let dots = PillMetrics.size(for: .processing)
        let loading = PillMetrics.size(for: .loadingModel)
        XCTAssertGreaterThan(loading.width, dots.width)
        XCTAssertEqual(loading.height, dots.height)
        let text = PillMetrics.textWidth(PillMode.loadingModelText, PillMetrics.noticeFont)
        XCTAssertEqual(loading.width, PillMetrics.padding + 13 + 6 + text + PillMetrics.padding)
    }

    func testTheLoadingStatusFollowsThePillSetting() {
        XCTAssertTrue(PillVisibility.isVisible(.loadingModel, showPill: true))
        XCTAssertFalse(PillVisibility.isVisible(.loadingModel, showPill: false), "with the pill off the menu bar mark works")
        XCTAssertFalse(PillVisibility.needsYou(.loadingModel))
    }

    func testOnlyTheDictationInProcessingTakesTheStatus() {
        let app = AppState(prefs: Preferences(defaults: UserDefaults(suiteName: "vypo.tests.\(UUID().uuidString)")!),
                           store: Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        let job = DictationJob()
        app.setPill(.processing)
        app.showLoadingModel(for: job)
        XCTAssertEqual(app.pillBase, .loadingModel)

        app.setPill(.ready)
        app.showLoadingModel(for: job)
        XCTAssertEqual(app.pillBase, .ready, "a finished or cancelled dictation does not bring the pill back")

        app.showError(.modelError)
        app.showLoadingModel(for: job)
        XCTAssertEqual(app.pillBase, .error(.modelError))

        app.setPill(.listening)
        app.showLoadingModel(for: job)
        XCTAssertEqual(app.pillBase, .listening, "a newer recording owns the pill")
    }

    // MARK: When the status shows

    func testADictationWhileTheModelIsNotReadyShowsTheStatusAtOnce() {
        var shown = 0
        let watch = LoadingStatusWatch(delay: .seconds(60), isReady: { false }, show: { shown += 1 })
        watch.start()
        defer { watch.stop() }
        XCTAssertEqual(shown, 1)
    }

    func testADictationWithAReadyModelShowsNothingAtFirst() {
        var shown = 0
        let watch = LoadingStatusWatch(delay: .seconds(60), isReady: { true }, show: { shown += 1 })
        watch.start()
        defer { watch.stop() }
        XCTAssertEqual(shown, 0)
    }

    func testARecognitionOverTheLimitShowsTheStatusOnce() async throws {
        var shown = 0
        let watch = LoadingStatusWatch(delay: .milliseconds(80), isReady: { true }, show: { shown += 1 })
        watch.start()
        defer { watch.stop() }
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(shown, 0)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(shown, 1)
    }

    func testAnUnreadyModelDoesNotShowTheStatusASecondTimeAtTheLimit() async throws {
        var shown = 0
        let watch = LoadingStatusWatch(delay: .milliseconds(50), isReady: { false }, show: { shown += 1 })
        watch.start()
        defer { watch.stop() }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(shown, 1)
    }

    func testAFastRecognitionNeverShowsTheStatus() async throws {
        var shown = 0
        let watch = LoadingStatusWatch(delay: .milliseconds(80), isReady: { true }, show: { shown += 1 })
        watch.start()
        watch.stop()
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(shown, 0)
    }

    func testTheLimitIsFiveSeconds() {
        XCTAssertEqual(LoadingStatusWatch.after, .seconds(5))
    }

    // MARK: Warm-up

    private func makeService(engine: FakeEngine) throws -> (ModelService, ModelManager, Store) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vypo-warmup-\(UUID().uuidString)")
        let modelFolder = dir.appendingPathComponent("model")
        try FileManager.default.createDirectory(at: modelFolder, withIntermediateDirectories: true)
        let store = Store(directory: dir)
        store.save([InstalledModel.Stored(id: ModelCatalog.speech.rawValue, path: modelFolder.path,
                                          deletePath: modelFolder.path, sizeBytes: 1)], to: "models.json")
        let manager = ModelManager(store: store)
        let engines = EngineManager(models: manager, makeEngine: { _ in engine })
        return (ModelService(manager: manager, engines: engines), manager, store)
    }

    /// Waits until `condition` holds.
    private func eventually(_ condition: @MainActor () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("did not happen in time", file: file, line: line)
    }

    func testTheModelIsNotReadyBeforeTheWarmUp() async throws {
        let engine = FakeEngine()
        let (service, _, _) = try makeService(engine: engine)
        XCTAssertFalse(service.isReady, "nothing happens at launch until preload runs")
        await engine.holdWarmUp()
        service.preload()
        await eventually { await engine.warmUps == 1 }
        XCTAssertFalse(service.isReady, "loaded, but still warming up")
        await engine.warmUpGate?.yield()
        await eventually { service.isReady }
    }

    func testWarmUpRunsOncePerLoad() async throws {
        let engine = FakeEngine()
        let (service, manager, _) = try makeService(engine: engine)
        service.preload()
        await eventually { service.isReady }
        service.preload()
        service.preload()
        try await Task.sleep(for: .milliseconds(100))
        let warmUps = await engine.warmUps
        let loads = await engine.loads
        XCTAssertEqual(warmUps, 1)
        XCTAssertEqual(loads, 1)

        // A recording starting calls preload again (the load while you talk): still nothing more.
        service.preload()
        try await Task.sleep(for: .milliseconds(50))
        let again = await engine.warmUps
        XCTAssertEqual(again, 1)

        // A new download or reload: not ready again, then warmed once more.
        await engine.unload()
        manager.onInstalled(ModelCatalog.speech)
        XCTAssertFalse(service.isReady)
        await eventually { service.isReady }
        let afterReload = await engine.warmUps
        XCTAssertEqual(afterReload, 2)
    }

    func testAWarmUpNeverRunsAsADictation() async throws {
        let engine = FakeEngine()
        let (service, _, _) = try makeService(engine: engine)
        service.preload()
        await eventually { service.isReady }
        let transcriptions = await engine.transcriptions
        XCTAssertEqual(transcriptions, 0, "it takes the warm-up path, not the transcription one (no History, stats or achievements are reachable from there)")
    }

    func testATranscriptionThatWorkedMakesTheModelReady() async throws {
        let engine = FakeEngine()
        let (service, _, _) = try makeService(engine: engine)
        let text = try await service.transcribe([0], with: ModelCatalog.speech, hint: nil)
        XCTAssertEqual(text, "text")
        XCTAssertTrue(service.isReady)
        await service.engines.warmUp(ModelCatalog.speech)
        let warmUps = await engine.warmUps
        XCTAssertEqual(warmUps, 0, "a dictation already warmed the model")
    }

    // MARK: Order

    func testADictationDuringTheWarmUpWaitsForItAndGoesNext() async throws {
        let queue = TurnQueue()
        let order = OrderLog()
        let started = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        let warm = Task {
            try await queue.withTurn {
                await order.add("warm-up start")
                started.1.yield()
                for await _ in release.0 { break }
                await order.add("warm-up end")
            }
        }
        for await _ in started.0 { break }
        let dictation = Task { try await queue.withTurn { await order.add("dictation") } }
        try await Task.sleep(for: .milliseconds(50))
        let early = await order.items
        XCTAssertEqual(early, ["warm-up start"], "the dictation waits its turn, it does not run alongside")
        release.1.yield()
        try await warm.value
        try await dictation.value
        let all = await order.items
        XCTAssertEqual(all, ["warm-up start", "warm-up end", "dictation"])
    }
}

private actor OrderLog {
    private(set) var items: [String] = []
    func add(_ s: String) { items.append(s) }
}

/// The real model, right after a start: the pill says “Loading speech model…”, then the dictation is recognised.
/// Opt-in (`TEST_RUNNER_VYPO_WARMUP_LIVE=1`): it reads the installed model from `~/Library/Application Support/vypo/`
/// (read only) and, through `scripts/test.sh`, fills the Core ML cache of the scratch home, never the installed app's.
/// Run it once with `build.noindex/test-home/Library/Caches` deleted (cold) and once more (warm); the times print as `WARMUP`.
@MainActor
final class ModelWarmUpLiveTests: XCTestCase {
    func testADictationRightAfterStartShowsTheStatusThenInserts() async throws {
        guard ProcessInfo.processInfo.environment["VYPO_WARMUP_LIVE"] != nil else { throw XCTSkip("opt-in") }
        let service = ModelService(manager: ModelManager(store: .shared))
        try XCTSkipUnless(service.effectiveModel != nil, "no installed model in the test's model list")
        let app = AppState(prefs: Preferences(defaults: UserDefaults(suiteName: "vypo.tests.\(UUID().uuidString)")!),
                           store: Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        let samples = try TestSpeech.say("Das ist ein kurzer Test am Montag.", voice: "Anna")
        let clock = ContinuousClock()
        let began = clock.now

        // The launch: the model starts loading. The user dictates right away.
        service.preload()
        let job = DictationJob()
        app.setPill(.processing)
        let watch = LoadingStatusWatch(isReady: { service.isReady }, show: { app.showLoadingModel(for: job) })
        watch.start()
        defer { watch.stop() }
        XCTAssertEqual(app.pillBase, .loadingModel, "the model is not ready: the pill says so at once")

        let text = try await service.transcribe(AudioPadding.padded(samples), with: ModelCatalog.speech, hint: nil)
        let waited = clock.now - began
        print("WARMUP right after start: text arrived after \(waited.milliseconds) ms: \(text)")
        XCTAssertTrue(text.lowercased().contains("montag"), text)
        XCTAssertTrue(service.isReady)

        // The next dictation, with the model ready: no status, fast.
        app.setPill(.processing)
        let second = LoadingStatusWatch(isReady: { service.isReady }, show: { app.showLoadingModel(for: job) })
        second.start()
        defer { second.stop() }
        XCTAssertEqual(app.pillBase, .processing, "ready: the plain dots")
        let next = clock.now
        _ = try await service.transcribe(AudioPadding.padded(samples), with: ModelCatalog.speech, hint: nil)
        print("WARMUP next dictation: \((clock.now - next).milliseconds) ms")
    }
}
