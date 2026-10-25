import XCTest
@testable import vypo

/// The CTC glossary helper is off by default: not downloaded, not loaded. The Debug menu turns it on
/// (downloaded if needed, then loaded) and off (unloaded; the files stay).
@MainActor
final class GlossaryHelperTests: XCTestCase {
    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("vypo-helper-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// A store whose models.json lists the speech model and, if asked, the helper, with folders that exist.
    private func manager(helper: Bool) throws -> ModelManager {
        let store = Store(directory: dir)
        var records = [InstalledModel.Stored]()
        for (id, on) in [(ModelID.parakeetUltra, true), (.ctcVocab, helper)] where on {
            let folder = dir.appendingPathComponent(id.rawValue)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            records.append(.init(id: id.rawValue, path: folder.path, deletePath: folder.path, sizeBytes: 1))
        }
        store.save(records, to: "models.json")
        return ModelManager(store: store)
    }

    func testOffByDefault() {
        let prefs = Preferences(defaults: UserDefaults(suiteName: "vypo.tests.\(UUID().uuidString)")!)
        XCTAssertFalse(prefs.glossaryHelper)
        XCTAssertFalse(ModelManager(store: Store(directory: dir)).includeHelper)
    }

    func testOffTheEngineGetsNoHelperAndOnItDoes() async throws {
        let models = try manager(helper: true)
        let engines = EngineManager(models: models)
        XCTAssertNil(engines.helperDirectory)
        let engine = try XCTUnwrap(engines.engine(for: .parakeetUltra) as? ParakeetEngine)
        var on = await engine.isHelperOn
        XCTAssertFalse(on)

        engines.helperEnabled = true
        XCTAssertEqual(engines.helperDirectory?.lastPathComponent, ModelID.ctcVocab.rawValue)
        on = try await waitFor(engine, on: true)
        XCTAssertTrue(on)

        // Off again: unloaded, but the files stay.
        engines.helperEnabled = false
        on = try await waitFor(engine, on: false)
        XCTAssertFalse(on)
        XCTAssertTrue(models.isInstalled(.ctcVocab))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent(ModelID.ctcVocab.rawValue).path))
    }

    func testOnButNotInstalledTheEngineGetsNothing() async throws {
        let engines = EngineManager(models: try manager(helper: false))
        engines.helperEnabled = true
        XCTAssertNil(engines.helperDirectory)
        let engine = try XCTUnwrap(engines.engine(for: .parakeetUltra) as? ParakeetEngine)
        let on = await engine.isHelperOn
        XCTAssertFalse(on)
    }

    /// The helper downloads on its own only once the speech model is there.
    func testTheHelperDownloadNeedsTheSpeechModel() {
        let models = ModelManager(store: Store(directory: dir))
        models.download(.ctcVocab)
        XCTAssertEqual(models.state(.ctcVocab), .notInstalled)
    }

    func testTheStatusText() {
        func status(_ enabled: Bool, _ install: ModelInstallState, loaded: Bool = false) -> String {
            GlossaryHelperStatus(enabled: enabled, install: install, loaded: loaded).description
        }
        XCTAssertEqual(status(false, .notInstalled), "off")
        XCTAssertEqual(status(false, .installed, loaded: false), "off (installed)")
        XCTAssertEqual(status(true, .installed, loaded: true), "on")
        XCTAssertEqual(status(true, .installed), "loading")
        XCTAssertEqual(status(true, .downloading(0.42)), "downloading 42 %")
        XCTAssertEqual(status(true, .queued), "downloading 0 %")
        XCTAssertEqual(status(true, .notInstalled), "not installed")
        XCTAssertEqual(status(true, .failed), "download failed")
    }

    private func waitFor(_ engine: ParakeetEngine, on: Bool) async throws -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while await engine.isHelperOn != on, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        return await engine.isHelperOn
    }
}
