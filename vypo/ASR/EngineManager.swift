import Foundation

/// Creates engines for installed models and decides which stay loaded (§9.4).
@MainActor
final class EngineManager {
    private let models: ModelManager
    private var engines: [ModelID: any ASREngine] = [:]

    init(models: ModelManager) {
        self.models = models
    }

    /// The engine for an installed model (not necessarily loaded).
    func engine(for id: ModelID) -> (any ASREngine)? {
        if let e = engines[id] { return e }
        guard id == ModelCatalog.speech, let record = models.records[id] else { return nil }
        let engine = ParakeetEngine(directory: URL(fileURLWithPath: record.path))
        engines[id] = engine
        return engine
    }

    func load(_ id: ModelID) async throws {
        guard let e = engine(for: id) else { throw ASREngineError.modelFilesMissing }
        try await e.load()
    }

    func unload(_ id: ModelID) async {
        guard let e = engines.removeValue(forKey: id) else { return }
        await e.unload()
    }

    /// Unloads every engine not in `keep`.
    func keepOnly(_ keep: Set<ModelID>) async {
        for id in engines.keys where !keep.contains(id) {
            await unload(id)
        }
    }

    func isLoaded(_ id: ModelID) async -> Bool {
        guard let e = engines[id] else { return false }
        return await e.isLoaded
    }
}
