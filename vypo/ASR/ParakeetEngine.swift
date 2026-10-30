@preconcurrency import FluidAudio
import Foundation

/// Parakeet Ultra via FluidAudio (§9).
actor ParakeetEngine: ASREngine {
    static let version: AsrModelVersion = .ultra
    /// One chunk at a time, otherwise FluidAudio's defaults. Every further worker opens its own Core ML stream on
    /// first use, and if the E5 cache has lost a file by then, each of them recompiles the encoder for about 30 s.
    /// See DECISIONS, “0.4.0: long dictations”.
    static let config = ASRConfig(parallelChunkConcurrency: 1)
    /// Over this, a transcription gets a warning in the log.
    static let slowAfter: Duration = .seconds(10)
    private let directory: URL
    private let config: ASRConfig

    private var manager: AsrManager?
    private var loading: Task<AsrManager, Error>?
    private(set) var lastTiming: TranscriptionTiming?
    /// A dictation left in the background and the next one must not predict on the same models at once.
    private let turns = TurnQueue()

    init(directory: URL, config: ASRConfig = ParakeetEngine.config) {
        self.directory = directory
        self.config = config
    }

    var isLoaded: Bool { manager != nil }

    func load() async throws {
        guard manager == nil else { return }
        // Concurrent callers share one load.
        let task = loading ?? Task { [directory, config] in
            let models = try await AsrModels.load(from: directory, version: Self.version)
            let m = AsrManager(config: config)
            try await m.loadModels(models)
            return m
        }
        loading = task
        defer { loading = nil }
        manager = try await task.value
        Log.asr.info("Loaded Parakeet Ultra")
    }

    func unload() async {
        loading?.cancel()
        loading = nil
        await manager?.cleanup()
        manager = nil
    }

    /// vypo's language as FluidAudio's, which only uses its script: with a hint the decoder prefers a
    /// token in that script over a likelier one in another (Cyrillic "Слэш" for "Slash").
    static func fluidLanguage(_ lang: Lang) -> Language {
        switch lang {
        case .bg: .bulgarian
        case .cs: .czech
        case .da: .danish
        case .de: .german
        case .el: .greek
        case .en: .english
        case .es: .spanish
        case .fi: .finnish
        case .fr: .french
        case .hr: .croatian
        case .hu: .hungarian
        case .it: .italian
        case .nl: .dutch
        case .pl: .polish
        case .pt: .portuguese
        case .ro: .romanian
        case .ru: .russian
        case .sk: .slovak
        case .sv: .swedish
        case .uk: .ukrainian
        }
    }

    func transcribe(_ samples: [Float], language: Lang?) async throws -> String {
        try await turns.withTurn { try await self.decode(samples, language: language) }
    }

    private func decode(_ samples: [Float], language: Lang?) async throws -> String {
        let seconds = Double(samples.count) / AudioRecorder.sampleRate
        let chunked = samples.count > ASRConstants.maxModelSamples
        Log.asr.notice("Transcription started: \(seconds, format: .fixed(precision: 1)) s of audio, \(chunked ? "chunked" : "one pass", privacy: .public)")
        // While it runs, so a transcription that never ends shows too.
        let watch = Task {
            try await Task.sleep(for: Self.slowAfter)
            Log.asr.warning("Transcription of \(seconds, format: .fixed(precision: 1)) s of audio is still running after \(Self.slowAfter.milliseconds) ms")
        }
        defer { watch.cancel() }
        if manager == nil { try await load() }
        guard let manager else { throw ASREngineError.notLoaded }
        var timing = TranscriptionTiming()
        defer { lastTiming = timing }
        let clock = ContinuousClock()
        var mark = clock.now
        /// The time since the previous call, which starts the next span.
        func lap() -> Duration {
            let now = clock.now
            defer { mark = now }
            return now - mark
        }
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let result = try await manager.transcribe(samples, decoderState: &state, language: language.map(Self.fluidLanguage))
        timing.decode = lap()
        if timing.decode > Self.slowAfter {
            Log.asr.warning("Transcription of \(seconds, format: .fixed(precision: 1)) s of audio took \(timing.decode.milliseconds) ms")
        }
        return result.text
    }
}

/// One at a time, in the order they came. A cancelled waiter leaves the line.
actor TurnQueue {
    private var busy = false
    private var waiting: [(id: UUID, turn: CheckedContinuation<Void, Error>)] = []

    func withTurn<T: Sendable>(_ work: @Sendable () async throws -> T) async throws -> T {
        try await enter()
        defer { leave() }
        try Task.checkCancellation()
        return try await work()
    }

    private func enter() async throws {
        guard busy else {
            busy = true
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { waiting.append((id, $0)) }
        } onCancel: {
            Task { await self.giveUp(id) }
        }
    }

    private func leave() {
        if waiting.isEmpty { busy = false } else { waiting.removeFirst().turn.resume() }
    }

    private func giveUp(_ id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else { return }
        waiting.remove(at: index).turn.resume(throwing: CancellationError())
    }
}
