import Observation
import XCTest
@testable import vypo

/// An engine whose load waits until the test lets it finish, like Core ML recompiling the model after a macOS update.
private actor SlowLoadEngine: ASREngine {
    private var loaded = false
    private var gate: AsyncStream<Void>?
    private var release: AsyncStream<Void>.Continuation?
    var lastTiming: TranscriptionTiming?
    var isLoaded: Bool { loaded }
    var isWarm: Bool { loaded }

    init() {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        gate = stream
        release = continuation
    }

    func finishLoading() { release?.yield() }

    func load() async throws {
        guard !loaded else { return }
        if let gate {
            for await _ in gate { break }
            self.gate = nil
        }
        loaded = true
    }

    func unload() async { loaded = false }
    func warmUp() async {}

    func transcribe(_ samples: [Float], language: Lang?) async throws -> String {
        try await load()
        return "text"
    }
}

private final class Flag: @unchecked Sendable { var value = false }

/// 0.6.0: a dictation that waits for the speech model is never silent, Try it never invites a dictation before the
/// model is ready, and a dictation moved to the background or cancelled never brings up the “click into the field”
/// prompt (task brief “Try it model loading”, 0.6.0).
@MainActor
final class TryItModelLoadingTests: XCTestCase {
    // MARK: Goal 2: Preparing until the model is ready

    func testADownloadedModelThatIsStillLoadingIsPreparing() {
        XCTAssertEqual(TryItState.modelStatus(for: .ready, isReady: false), .preparing)
        XCTAssertEqual(TryItState.modelStatus(for: .ready, isReady: true), .ready)
        let loading = TryItState(model: TryItState.modelStatus(for: .ready, isReady: false), focused: false)
        XCTAssertEqual(loading.area, .locked(.preparing), "no “Click here, then hold fn” while the model loads")
        XCTAssertNil(loading.resultLine)
        let focused = TryItState(model: TryItState.modelStatus(for: .ready, isReady: false), focused: true)
        XCTAssertEqual(focused.area, .locked(.preparing), "no “Your text appears here.” either")
    }

    func testTheOtherModelStatesDoNotDependOnReadiness() {
        for ready in [false, true] {
            XCTAssertEqual(TryItState.modelStatus(for: .failed(.couldntLoad), isReady: ready), .failed)
            XCTAssertEqual(TryItState.modelStatus(for: .downloading(percent: 40), isReady: ready), .loading(percent: 40))
            XCTAssertEqual(TryItState.modelStatus(for: .preparing, isReady: ready), .preparing)
            XCTAssertEqual(TryItState.modelStatus(for: .notStarted, isReady: ready), .loading(percent: 0))
        }
    }

    func testTryItFollowsTheRealModelServiceFromLaunchToReady() async throws {
        let engine = SlowLoadEngine()
        let service = try makeService(engine: engine)
        func area() -> TryItState.Area {
            let badge = ModelBadge.make(state: service.state, loadFailed: service.loadFailed, failure: nil)
            return TryItState(model: TryItState.modelStatus(for: badge, isReady: service.isReady), focused: true).area
        }
        XCTAssertEqual(service.state, .installed)
        XCTAssertEqual(area(), .locked(.preparing), "relaunch, `--no-reset`, `-VYPOOnboardingStep 5`: installed is not ready")
        service.preload()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(area(), .locked(.preparing), "still loading")
        await engine.finishLoading()
        await eventually { service.isReady }
        XCTAssertEqual(area(), .ready)
    }

    func testReadinessIsObservedSoTheStepUpdatesWhenTheModelIsReady() async throws {
        let engine = SlowLoadEngine()
        let service = try makeService(engine: engine)
        let changed = Flag()
        withObservationTracking { _ = service.isReady } onChange: { changed.value = true }
        service.preload()
        await engine.finishLoading()
        await eventually { service.isReady }
        XCTAssertTrue(changed.value)

        // Set only when it changes: a dictation that worked does not wake every view again.
        let again = Flag()
        withObservationTracking { _ = service.isReady } onChange: { again.value = true }
        _ = try await service.transcribe([0], with: ModelCatalog.speech, hint: nil)
        XCTAssertFalse(again.value)
    }

    // MARK: Goal 1: the pill shows the wait, also during onboarding

    func testOnboardingHidesThePillExceptForTheModelWait() {
        XCTAssertTrue(PillVisibility.isVisible(.loadingModel, showPill: true, pillHidden: true))
        for mode: PillMode in [.listening, .handsfree, .processing, .ready, .error(.modelError), .added(.onClipboard), .add] {
            XCTAssertFalse(PillVisibility.isVisible(mode, showPill: true, pillHidden: true), "\(mode)")
        }
        XCTAssertFalse(PillVisibility.isVisible(.loadingModel, showPill: false, pillHidden: true), "the pill setting still counts")
        // Outside onboarding nothing changes.
        for mode: PillMode in [.listening, .processing, .loadingModel, .ready, .add] {
            XCTAssertEqual(PillVisibility.isVisible(mode, showPill: true, pillHidden: false), PillVisibility.isVisible(mode, showPill: true))
            XCTAssertEqual(PillVisibility.isVisible(mode, showPill: false, pillHidden: false), PillVisibility.isVisible(mode, showPill: false))
        }
    }

    // MARK: Goal 3: no prompt while a dictation is still on its way

    func testWaitingForTheModelIsProcessingNotIdle() {
        XCTAssertEqual(TryItState.activity(for: .loadingModel), .processing)
        XCTAssertEqual(TryItState.activity(for: .processing), .processing)
        XCTAssertEqual(TryItState.activity(for: .listening), .recording)
        XCTAssertEqual(TryItState.activity(for: .handsfree), .recording)
        XCTAssertEqual(TryItState.activity(for: .ready), .idle)
        XCTAssertEqual(TryItState.activity(for: .error(.tooQuiet)), .idle)
        let waiting = TryItState(model: .ready, focused: false, activity: TryItState.activity(for: .loadingModel))
        XCTAssertEqual(waiting.area, .processing, "the area keeps the dots, it does not fall back to “Click here, then hold fn”")
        XCTAssertNil(waiting.resultLine)
    }

    /// The live case of 12.11.: three dictations while the model loads. The first goes to the background, a third
    /// cancels it. Seen from Try it with the focus flag off (the worst case), no step shows the prompt or a result line.
    func testBackgroundAndCancelledDictationsNeverBringUpThePrompt() async {
        let prefs = Preferences(defaults: UserDefaults(suiteName: "vypo.tests.\(UUID().uuidString)")!)
        let app = AppState(prefs: prefs, store: Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        let dictation = DictationController(app: app, recorder: AudioRecorder(meter: app.levelMeter), muter: AudioMuter(), hotkey: HotkeyMonitor())
        var jobs: [DictationJob] = []
        var released: Set<Int> = []
        var cancelled: [Bool] = []
        dictation.process = { _, _, job in
            let index = jobs.count
            jobs.append(job)
            cancelled.append(false)
            // Like `transcribeAndInsert`: the model is not ready, so the pill says so at once.
            app.showLoadingModel(for: job)
            while !released.contains(index), !Task.isCancelled { await Task.yield() }
            cancelled[index] = Task.isCancelled
        }
        func start() async {
            let before = jobs.count
            dictation.startProcessing([], RecordingContext(startedAt: Date()))
            while jobs.count == before { await Task.yield() }
        }
        func settle() async { for _ in 0..<200 { await Task.yield() } }
        func tryIt() -> TryItState {
            TryItState(model: .ready, focused: false, activity: TryItState.activity(for: app.pillBase))
        }

        await start()
        XCTAssertEqual(app.pillBase, .loadingModel)
        XCTAssertEqual(tryIt().area, .processing)

        // A second dictation: the first goes on in the background (in the app the new recording follows at once).
        dictation.moveProcessingToBackground()
        await start()
        XCTAssertTrue(jobs[0].isLeftover)
        XCTAssertEqual(app.pillBase, .loadingModel, "the new dictation owns the pill")
        XCTAssertEqual(tryIt().area, .processing)

        // A third: the oldest is cancelled, the second goes to the background.
        dictation.moveProcessingToBackground()
        await start()
        await settle()
        XCTAssertTrue(cancelled[0])
        XCTAssertTrue(jobs[1].isLeftover)
        XCTAssertEqual(tryIt().area, .processing)
        XCTAssertNil(tryIt().resultLine)

        // The leftover ends first: the newest is still on its way.
        released.insert(1)
        await settle()
        XCTAssertEqual(tryIt().area, .processing)
        XCTAssertNil(app.lastOutcome, "a leftover or cancelled dictation reports nothing to Try it")

        released.insert(2)
        await settle()
        XCTAssertEqual(app.pillBase, .ready)
    }

    func testEscWhileWaitingForTheModelEndsTheDictationQuietly() async {
        let app = AppState(prefs: Preferences(defaults: UserDefaults(suiteName: "vypo.tests.\(UUID().uuidString)")!),
                           store: Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        let dictation = DictationController(app: app, recorder: AudioRecorder(meter: app.levelMeter), muter: AudioMuter(), hotkey: HotkeyMonitor())
        var started = false
        dictation.process = { _, _, job in
            app.showLoadingModel(for: job)
            started = true
            try? await Task.sleep(for: .seconds(60))
        }
        dictation.startProcessing([], RecordingContext(startedAt: Date()))
        while !started { await Task.yield() }
        XCTAssertEqual(app.pillBase, .loadingModel)
        dictation.cancel()
        XCTAssertEqual(app.pillBase, .ready)
        XCTAssertNil(app.lastOutcome, "no red or failure line for a dictation the user cancelled")
        XCTAssertEqual(TryItState(model: .ready, focused: true, activity: TryItState.activity(for: app.pillBase)).area, .ready)
    }

    // MARK: Helpers

    private func makeService(engine: SlowLoadEngine) throws -> ModelService {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vypo-tryit-loading-\(UUID().uuidString)")
        let modelFolder = dir.appendingPathComponent("model")
        try FileManager.default.createDirectory(at: modelFolder, withIntermediateDirectories: true)
        let store = Store(directory: dir)
        store.save([InstalledModel.Stored(id: ModelCatalog.speech.rawValue, path: modelFolder.path,
                                          deletePath: modelFolder.path, sizeBytes: 1)], to: "models.json")
        let manager = ModelManager(store: store)
        let engines = EngineManager(models: manager, makeEngine: { _ in engine })
        return ModelService(manager: manager, engines: engines)
    }

    private func eventually(_ condition: @MainActor () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("did not happen in time", file: file, line: line)
    }
}
