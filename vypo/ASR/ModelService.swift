import Foundation
import Observation

/// The speech model (§9.3, §9.4): Parakeet Ultra for every language, downloaded once and kept loaded.
@MainActor
@Observable
final class ModelService {
    let manager: ModelManager
    @ObservationIgnored let engines: EngineManager
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init(manager: ModelManager = ModelManager()) {
        self.manager = manager
        engines = EngineManager(models: manager)
        manager.onInstalled = { [weak self] id in
            if id == .ctcVocab { self?.engines.applyHelper() }
            if id == ModelCatalog.speech { self?.preload() }
        }
    }

    /// The model to dictate with; nil until it's downloaded.
    var effectiveModel: ModelID? { manager.isInstalled(ModelCatalog.speech) ? ModelCatalog.speech : nil }

    var state: ModelInstallState { manager.state(ModelCatalog.speech) }

    func download() { manager.download(ModelCatalog.speech) }

    func cancelDownload() { manager.cancel(ModelCatalog.speech) }

    /// Loads the model in the background, so the first dictation doesn't wait for it.
    func preload() {
        guard let id = effectiveModel, loadTask == nil else { return }
        loadTask = Task {
            do { try await engines.load(id) } catch {
                Log.asr.error("Preloading \(id.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
            loadTask = nil
        }
    }

    /// Transcribes, loading the model if needed. `hint` is a language whose script all the user's languages share; Parakeet uses it only to drop wrong-script tokens.
    func transcribe(_ samples: [Float], with id: ModelID, hint: Lang?, glossary: [GlossaryEntry]) async throws -> String {
        guard let engine = engines.engine(for: id) else { throw ASREngineError.modelFilesMissing }
        return try await engine.transcribe(samples, language: hint, glossary: glossary)
    }

    /// The glossary helper (Debug menu, off by default). On: downloaded if it isn't there yet (with the
    /// speech model, or on its own after it), then loaded. Off: a running download stops and it's unloaded;
    /// installed files stay.
    func setGlossaryHelper(_ on: Bool) {
        manager.includeHelper = on
        engines.helperEnabled = on
        if on {
            manager.download(.ctcVocab)
        } else {
            manager.cancel(.ctcVocab)
        }
    }

    /// The helper's state for the timing log, e.g. “off”, “on”, “loading”.
    func helperStatus() async -> GlossaryHelperStatus {
        let loaded = await (engines.engine(for: ModelCatalog.speech) as? ParakeetEngine)?.isVocabularyLoaded ?? false
        return GlossaryHelperStatus(enabled: engines.helperEnabled, install: manager.state(.ctcVocab), loaded: loaded)
    }

    func lastTiming(for id: ModelID) async -> TranscriptionTiming? {
        await engines.engine(for: id)?.lastTiming
    }
}

/// The glossary helper's state, as the timing log and the diagnostics show it.
struct GlossaryHelperStatus: Equatable {
    var enabled: Bool
    var install: ModelInstallState
    var loaded: Bool

    /// “off”, “off (installed)”, “on”, “loading”, “downloading 40 %”, “not installed”, “download failed”.
    var description: String {
        guard enabled else { return install == .installed ? "off (installed)" : "off" }
        switch install {
        case .installed: return loaded ? "on" : "loading"
        case .queued: return "downloading 0 %"
        case .downloading(let p): return "downloading \(Int(p * 100)) %"
        case .notInstalled: return "not installed"
        case .failed: return "download failed"
        }
    }
}
