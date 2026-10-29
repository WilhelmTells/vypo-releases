import Foundation
import Observation

/// The speech model (§9.3, §9.4): Parakeet Ultra for every language, downloaded once and kept loaded.
@MainActor
@Observable
final class ModelService {
    let manager: ModelManager
    @ObservationIgnored let engines: EngineManager
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    /// The model is installed but could not be loaded (the onboarding path bar says so).
    var loadFailed = false

    init(manager: ModelManager = ModelManager()) {
        self.manager = manager
        engines = EngineManager(models: manager)
        manager.onInstalled = { [weak self] id in
            if id == ModelCatalog.speech { self?.preload() }
        }
    }

    /// The model to dictate with; nil until it's downloaded.
    var effectiveModel: ModelID? { manager.isInstalled(ModelCatalog.speech) ? ModelCatalog.speech : nil }

    var state: ModelInstallState { manager.state(ModelCatalog.speech) }

    func download() { manager.download(ModelCatalog.speech) }

    /// “Try again” in the path bar: download again after a failure, or load again after a load failure.
    func retry() {
        if state == .failed { download() } else if loadFailed { preload() }
    }

    func cancelDownload() { manager.cancel(ModelCatalog.speech) }

    /// Loads the model in the background, so the first dictation doesn't wait for it.
    func preload() {
        guard let id = effectiveModel, loadTask == nil else { return }
        loadTask = Task {
            do {
                try await engines.load(id)
                loadFailed = false
            } catch {
                loadFailed = true
                Log.asr.error("Preloading \(id.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
            loadTask = nil
        }
    }

    /// Transcribes, loading the model if needed. `hint` is a language whose script all the user's languages share; Parakeet uses it only to drop wrong-script tokens.
    func transcribe(_ samples: [Float], with id: ModelID, hint: Lang?) async throws -> String {
        guard let engine = engines.engine(for: id) else { throw ASREngineError.modelFilesMissing }
        return try await engine.transcribe(samples, language: hint)
    }

    func lastTiming(for id: ModelID) async -> TranscriptionTiming? {
        await engines.engine(for: id)?.lastTiming
    }
}
