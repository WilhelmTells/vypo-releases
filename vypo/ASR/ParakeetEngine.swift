@preconcurrency import FluidAudio
import Foundation

/// Parakeet Ultra via FluidAudio (§9).
actor ParakeetEngine: ASREngine {
    static let version: AsrModelVersion = .ultra
    private let directory: URL

    private var manager: AsrManager?
    private var loading: Task<AsrManager, Error>?
    private(set) var lastTiming: TranscriptionTiming?

    init(directory: URL) {
        self.directory = directory
    }

    var isLoaded: Bool { manager != nil }

    func load() async throws {
        guard manager == nil else { return }
        // Concurrent callers share one load.
        let task = loading ?? Task { [directory] in
            let models = try await AsrModels.load(from: directory, version: Self.version)
            let m = AsrManager(config: .default)
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
        return result.text
    }
}
