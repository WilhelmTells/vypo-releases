import AppKit
@preconcurrency import FluidAudio
import Foundation
import Observation

enum ModelInstallState: Equatable, Sendable {
    case notInstalled
    case queued
    case downloading(Double)
    case installed
    case failed
}

/// An installed model as recorded in `models.json` (§17).
struct InstalledModel: Codable, Equatable, Sendable {
    /// A record as stored; models vypo no longer offers (Whisper, Parakeet v2/v3) have unknown ids.
    struct Stored: Codable {
        var id: String
        var path: String
        var deletePath: String
        var sizeBytes: Int64
    }

    var id: ModelID
    /// The folder the engine loads from.
    var path: String
    /// What to delete; differs from `path` when the library used its own folder (§9.3 fallback).
    var deletePath: String
    var sizeBytes: Int64
}

/// Downloads, queues, cancels and deletes models (§9.3).
@MainActor
@Observable
final class ModelManager {
    private(set) var states: [ModelID: ModelInstallState] = [:]
    private(set) var records: [ModelID: InstalledModel] = [:]
    private(set) var storageBytes: Int64 = 0
    /// Why the last download failed, for the onboarding path bar (offline reads differently from a failed download).
    private(set) var lastFailure: ModelProblem?

    @ObservationIgnored private let store: Store
    @ObservationIgnored private var queue: [ModelID] = []
    @ObservationIgnored private var current: (id: ModelID, task: Task<Void, Never>)?
    /// Called on the main actor after a model finished installing.
    @ObservationIgnored var onInstalled: (ModelID) -> Void = { _ in }

    private static let file = "models.json"

    init(store: Store = .shared) {
        self.store = store
        let saved = store.load([InstalledModel.Stored].self, from: Self.file) ?? []
        var retired = false
        for r in saved {
            guard let id = ModelID(rawValue: r.id) else {
                // A model vypo no longer offers (Whisper, Parakeet v2/v3, the glossary helper): its files go, if they're in vypo's own folder.
                // The helper's files live in FluidAudio's folder; `RetiredGlossaryHelper` removes those.
                retired = true
                if r.deletePath.hasPrefix(store.modelsDirectory.path) {
                    try? FileManager.default.removeItem(atPath: r.deletePath)
                }
                Log.models.notice("Removed retired model \(r.id, privacy: .public)")
                continue
            }
            guard FileManager.default.fileExists(atPath: r.path) else { continue }
            records[id] = InstalledModel(id: id, path: r.path, deletePath: r.deletePath, sizeBytes: r.sizeBytes)
        }
        if retired { save() }
        for id in ModelID.allCases {
            states[id] = records[id] != nil ? .installed : .notInstalled
        }
        refreshStorage()
    }

    var installed: Set<ModelID> { Set(records.keys) }

    func state(_ id: ModelID) -> ModelInstallState { states[id] ?? .notInstalled }

    func isInstalled(_ id: ModelID) -> Bool { records[id] != nil }

    func url(for id: ModelID) -> URL? { records[id].map { URL(fileURLWithPath: $0.path) } }

    func sizeOnDisk(_ id: ModelID) -> Int64? { records[id]?.sizeBytes }

    /// The model being downloaded and its progress, if any.
    var activeDownload: (id: ModelID, progress: Double)? {
        guard let id = current?.id, case .downloading(let p) = state(id) else { return nil }
        return (id, p)
    }

    // MARK: Download

    /// The speech model.
    func download(_ id: ModelID) {
        guard id == ModelCatalog.speech else { return }
        guard records[id] == nil, current?.id != id, !queue.contains(id) else { return }
        queue.append(id)
        states[id] = .queued
        startNext()
    }

    func cancel(_ id: ModelID) {
        if let i = queue.firstIndex(of: id) {
            queue.remove(at: i)
            states[id] = .notInstalled
            return
        }
        guard current?.id == id else { return }
        current?.task.cancel()
    }

    private func startNext() {
        guard current == nil, !queue.isEmpty else { return }
        let id = queue.removeFirst()
        states[id] = .downloading(0)
        lastFailure = nil
        let modelsDir = store.modelsDirectory
        let task = Task { [weak self] in
            // FluidAudio reports every network chunk; the UI only needs whole percents.
            let throttle = PercentThrottle()
            let report: @Sendable (Double) -> Void = { p in
                guard throttle.isNewPercent(p) else { return }
                Task { @MainActor in self?.progress(id, p) }
            }
            do {
                let record = try await Self.performDownload(id, modelsDir: modelsDir, progress: report)
                try Task.checkCancellation()
                self?.finished(id, record: record)
            } catch {
                self?.failed(id, error: error)
            }
        }
        current = (id, task)
    }

    private func progress(_ id: ModelID, _ p: Double) {
        guard current?.id == id, case .downloading(let old) = state(id) else { return }
        states[id] = .downloading(max(old, min(p, 0.99)))
    }

    private func finished(_ id: ModelID, record: InstalledModel) {
        records[id] = record
        states[id] = .installed
        save()
        current = nil
        Log.models.info("Installed \(id.rawValue, privacy: .public)")
        onInstalled(id)
        startNext()
    }

    private func failed(_ id: ModelID, error: Error) {
        let cancelled = error is CancellationError || Task.isCancelled || (error as? URLError)?.code == .cancelled
        try? FileManager.default.removeItem(at: store.modelsDirectory.appendingPathComponent(id.rawValue))
        states[id] = cancelled ? .notInstalled : .failed
        lastFailure = cancelled ? nil : (Self.isOffline(error) ? .offline : .downloadFailed)
        if !cancelled { Log.models.error("Download of \(id.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)") }
        current = nil
        refreshStorage()
        startNext()
    }

    #if DEBUG
    /// Snapshots and tests: show the model in a state without downloading anything.
    func setPreviewState(_ state: ModelInstallState, failure: ModelProblem? = nil) {
        states[ModelCatalog.speech] = state
        lastFailure = failure
    }
    #endif

    /// Whether the error says there is no network (also when the library wraps it).
    nonisolated static func isOffline(_ error: Error) -> Bool {
        let offline: Set<Int> = [NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorCannotFindHost,
                                 NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed, NSURLErrorTimedOut,
                                 NSURLErrorInternationalRoamingOff, NSURLErrorDataNotAllowed]
        var current: NSError? = error as NSError
        while let e = current {
            if e.domain == NSURLErrorDomain, offline.contains(e.code) { return true }
            current = e.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }

    // MARK: Delete

    /// Removes the files. The caller unloads the engine and fixes the selection first.
    func delete(_ id: ModelID) {
        guard let record = records[id] else { return }
        try? FileManager.default.removeItem(atPath: record.deletePath)
        records[id] = nil
        states[id] = .notInstalled
        save()
    }

    // MARK: Storage

    func showInFinder() {
        try? FileManager.default.createDirectory(at: store.modelsDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(store.modelsDirectory)
    }

    private func save() {
        store.save(records.values.sorted { $0.id.rawValue < $1.id.rawValue }, to: Self.file)
        refreshStorage()
    }

    /// Size of `Models/` plus the recorded fallback paths.
    func refreshStorage() {
        let modelsDir = store.modelsDirectory.path
        var total = Self.directorySize(store.modelsDirectory)
        for r in records.values where !r.deletePath.hasPrefix(modelsDir) {
            total += Self.directorySize(URL(fileURLWithPath: r.deletePath))
        }
        storageBytes = total
    }

    nonisolated static func directorySize(_ url: URL) -> Int64 {
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in e {
            let v = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
            if v?.isRegularFile == true { total += Int64(v?.totalFileAllocatedSize ?? 0) }
        }
        return total
    }

    // MARK: Library calls

    private nonisolated static func performDownload(_ id: ModelID, modelsDir: URL,
                                                    progress: @escaping @Sendable (Double) -> Void) async throws -> InstalledModel {
        guard id == ModelCatalog.speech else { throw ASREngineError.modelFilesMissing }
        let root = modelsDir.appendingPathComponent(id.rawValue, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let target = root.appendingPathComponent(Repo.parakeetUltra.folderName)
        let mapper = ParakeetProgress(files: 4, report: progress)
        let dir = try await AsrModels.download(to: target, version: ParakeetEngine.version) { p in
            mapper.update(p.fractionCompleted)
        }
        // Files already on disk (e.g. left by an interrupted download) return without any progress.
        progress(1)
        return InstalledModel(id: id, path: dir.path, deletePath: root.path, sizeBytes: directorySize(root))
    }
}

/// Lets a progress value through only when its whole percent changed.
final class PercentThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var last = -1

    func isNewPercent(_ fraction: Double) -> Bool {
        let percent = Int(fraction * 100)
        return lock.withLock {
            guard percent != last else { return false }
            last = percent
            return true
        }
    }
}

/// Maps `AsrModels.download` progress onto one bar. FluidAudio runs one `loadModels` per model file:
/// the first downloads the whole repo (its fraction 0–0.5), then each call compiles its file (0.5–1).
/// The download fills 90% of `scale`; each finished compile adds an equal share of the rest.
final class ParakeetProgress: @unchecked Sendable {
    private let files: Int
    private let scale: Double
    private let report: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var downloaded = false
    private var compiled = 0
    private var last = 0.0

    init(files: Int, scale: Double = 1, report: @escaping @Sendable (Double) -> Void) {
        self.files = files
        self.scale = scale
        self.report = report
    }

    func update(_ fraction: Double) {
        let total: Double = lock.withLock {
            if !downloaded && fraction < 0.5 {
                last = max(last, 0.9 * fraction / 0.5)
                return last
            }
            downloaded = true
            if fraction >= 1 { compiled = min(compiled + 1, files) }
            last = max(last, 0.9 + 0.1 * Double(compiled) / Double(files))
            return last
        }
        report(total * scale)
    }
}
