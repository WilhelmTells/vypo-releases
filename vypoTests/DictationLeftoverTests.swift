@preconcurrency import FluidAudio
import AppKit
import XCTest
@testable import vypo

/// A new dictation during processing: the old one finishes in the background for History, nothing is lost silently.
/// Drives the real controller from `startProcessing`, with a `process` that waits until the test lets it end.
@MainActor
final class DictationLeftoverTests: XCTestCase {
    private var app: AppState!
    private var dictation: DictationController!
    private var jobs: [DictationJob] = []
    private var released: Set<Int> = []
    private var cancelled: [Bool] = []

    override func setUp() async throws {
        let prefs = Preferences(defaults: UserDefaults(suiteName: "vypo.tests.\(UUID().uuidString)")!)
        app = AppState(prefs: prefs, store: Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        dictation = DictationController(app: app, recorder: AudioRecorder(meter: app.levelMeter), muter: AudioMuter(), hotkey: HotkeyMonitor())
        dictation.process = { [unowned self] _, _, job in
            let index = self.jobs.count
            self.jobs.append(job)
            self.cancelled.append(false)
            while !self.released.contains(index), !Task.isCancelled { await Task.yield() }
            self.cancelled[index] = Task.isCancelled
        }
    }

    private func start() async {
        let before = jobs.count
        dictation.startProcessing([], RecordingContext(startedAt: Date()))
        while jobs.count == before { await Task.yield() }
    }

    private func end(_ index: Int) { released.insert(index) }

    /// Lets the finished task run its last lines.
    private func settle() async {
        for _ in 0..<200 { await Task.yield() }
    }

    func testTheOldDictationGoesOnInTheBackground() async {
        await start()
        dictation.moveProcessingToBackground()
        XCTAssertTrue(jobs[0].isLeftover)
        XCTAssertFalse(cancelled[0])
        XCTAssertEqual(dictation.phase, .idle)
        XCTAssertEqual(app.pillBase, .ready)
    }

    func testALeftoverEndingDoesNotEndTheNewDictation() async {
        await start()
        dictation.moveProcessingToBackground()
        await start()
        end(0)
        await settle()
        XCTAssertEqual(dictation.phase, .processing)
        XCTAssertEqual(app.pillBase, .processing)
        end(1)
        await settle()
        XCTAssertEqual(dictation.phase, .idle)
        XCTAssertEqual(app.pillBase, .ready)
    }

    func testAThirdDictationCancelsTheOldestLeftover() async {
        await start()
        dictation.moveProcessingToBackground()
        await start()
        dictation.moveProcessingToBackground()
        await settle()
        XCTAssertTrue(cancelled[0])
        XCTAssertFalse(cancelled[1])
        XCTAssertTrue(jobs[1].isLeftover)
    }

    func testAFinishedLeftoverLeavesRoomForTheNext() async {
        await start()
        dictation.moveProcessingToBackground()
        end(0)
        await settle()
        await start()
        dictation.moveProcessingToBackground()
        await settle()
        XCTAssertFalse(cancelled[1])
        XCTAssertTrue(jobs[1].isLeftover)
    }

    func testWithoutHistoryTheOldDictationIsDropped() async {
        app.prefs.saveHistory = false
        await start()
        dictation.moveProcessingToBackground()
        await settle()
        XCTAssertTrue(cancelled[0])
        XCTAssertFalse(jobs[0].isLeftover)
        XCTAssertEqual(dictation.phase, .idle)
    }

    func testEscCancelsOnlyTheNewDictation() async {
        await start()
        dictation.moveProcessingToBackground()
        await start()
        dictation.cancel()
        await settle()
        XCTAssertFalse(cancelled[0])
        XCTAssertTrue(cancelled[1])
        XCTAssertEqual(dictation.phase, .idle)
    }

    func testAPastedDictationIsNotALeftover() async {
        await start()
        jobs[0].inserted = true
        dictation.moveProcessingToBackground()
        XCTAssertFalse(jobs[0].isLeftover)
        XCTAssertFalse(cancelled[0])
        XCTAssertEqual(dictation.phase, .idle)
        end(0)
        await settle()
        XCTAssertEqual(dictation.phase, .idle)
    }

    func testOtherPhasesStayAsTheyAre() {
        dictation.moveProcessingToBackground()
        XCTAssertEqual(dictation.phase, .idle)
    }
}

final class TurnQueueTests: XCTestCase {
    private actor Log {
        var entries: [String] = []
        func add(_ entry: String) { entries.append(entry) }
    }

    func testOneAtATimeInOrder() async throws {
        let queue = TurnQueue()
        let log = Log()
        let first = Task {
            try await queue.withTurn {
                await log.add("first starts")
                try await Task.sleep(for: .milliseconds(50))
                await log.add("first ends")
            }
        }
        try await Task.sleep(for: .milliseconds(10))
        let second = Task {
            try await queue.withTurn { await log.add("second") }
        }
        try await first.value
        try await second.value
        let entries = await log.entries
        XCTAssertEqual(entries, ["first starts", "first ends", "second"])
    }

    func testACancelledWaiterLeavesTheLine() async throws {
        let queue = TurnQueue()
        let log = Log()
        let first = Task {
            try await queue.withTurn { try await Task.sleep(for: .milliseconds(80)) }
        }
        try await Task.sleep(for: .milliseconds(10))
        let waiter = Task {
            try await queue.withTurn { await log.add("waiter ran") }
        }
        try await Task.sleep(for: .milliseconds(10))
        waiter.cancel()
        do {
            try await waiter.value
            XCTFail("the waiter should have been cancelled")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        try await first.value
        try await queue.withTurn { await log.add("next") }
        let entries = await log.entries
        XCTAssertEqual(entries, ["next"])
    }

    func testTheNextOneRunsAfterAFailure() async throws {
        struct Failure: Error {}
        let queue = TurnQueue()
        do {
            try await queue.withTurn { throw Failure() }
            XCTFail("should have thrown")
        } catch {}
        let value = try await queue.withTurn { 7 }
        XCTAssertEqual(value, 7)
    }
}

final class ParakeetConfigTests: XCTestCase {
    func testOneChunkAtATimeOtherwiseTheDefaults() {
        let config = ParakeetEngine.config, standard = ASRConfig.default
        XCTAssertEqual(config.parallelChunkConcurrency, 1)
        XCTAssertEqual(config.sampleRate, standard.sampleRate)
        XCTAssertEqual(config.encoderHiddenSize, standard.encoderHiddenSize)
        XCTAssertEqual(config.streamingEnabled, standard.streamingEnabled)
        XCTAssertEqual(config.streamingThreshold, standard.streamingThreshold)
        XCTAssertEqual(config.melChunkContextOverride, standard.melChunkContextOverride)
        XCTAssertEqual(config.dualDecodeArbitration, standard.dualDecodeArbitration)
        XCTAssertEqual(config.seamGapRepair, standard.seamGapRepair)
        XCTAssertEqual(config.seamGapRepairMinGapSeconds, standard.seamGapRepairMinGapSeconds)
    }
}
