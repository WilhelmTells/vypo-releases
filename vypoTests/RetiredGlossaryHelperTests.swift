import XCTest
@testable import vypo

/// The update from 0.2.0: the CTC glossary helper is gone, its folder and preference go once, nothing else changes.
@MainActor
final class RetiredGlossaryHelperTests: XCTestCase {
    private var support: URL!
    private var defaults: UserDefaults!

    override func setUp() {
        support = FileManager.default.temporaryDirectory.appendingPathComponent("vypo-helper-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: "vypo.test.\(UUID().uuidString)")!
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: support)
    }

    private func makeHelperFolder() throws -> URL {
        let folder = RetiredGlossaryHelper.folder(applicationSupport: support)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(count: 1024).write(to: folder.appendingPathComponent("Encoder.mlmodelc"))
        return folder
    }

    func testTheFolderIsFluidAudiosCtcFolder() {
        XCTAssertEqual(RetiredGlossaryHelper.folder(applicationSupport: support).path,
                       support.path + "/FluidAudio/Models/parakeet-ctc-110m-coreml")
    }

    func testFolderPresentAndPreferenceOn() throws {
        let folder = try makeHelperFolder()
        defaults.set(true, forKey: "glossaryHelper")
        let result = RetiredGlossaryHelper.cleanUp(applicationSupport: support, defaults: defaults)
        XCTAssertEqual(result, .init(deletedFolder: true, removedPreference: true, error: nil))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertNil(defaults.object(forKey: "glossaryHelper"))
    }

    func testFolderPresentAndPreferenceOff() throws {
        let folder = try makeHelperFolder()
        defaults.set(false, forKey: "glossaryHelper")
        let result = RetiredGlossaryHelper.cleanUp(applicationSupport: support, defaults: defaults)
        XCTAssertEqual(result, .init(deletedFolder: true, removedPreference: true, error: nil))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func testFolderAbsentAndPreferenceOn() {
        defaults.set(true, forKey: "glossaryHelper")
        let result = RetiredGlossaryHelper.cleanUp(applicationSupport: support, defaults: defaults)
        XCTAssertEqual(result, .init(deletedFolder: false, removedPreference: true, error: nil))
        XCTAssertNil(defaults.object(forKey: "glossaryHelper"))
    }

    func testFolderAbsentAndPreferenceNeverSetDoesNothing() {
        XCTAssertEqual(RetiredGlossaryHelper.cleanUp(applicationSupport: support, defaults: defaults), .init())
    }

    func testASecondRunDoesNothing() throws {
        _ = try makeHelperFolder()
        defaults.set(true, forKey: "glossaryHelper")
        RetiredGlossaryHelper.cleanUp(applicationSupport: support, defaults: defaults)
        XCTAssertEqual(RetiredGlossaryHelper.cleanUp(applicationSupport: support, defaults: defaults), .init())
    }

    func testOtherFilesAreNotTouched() throws {
        _ = try makeHelperFolder()
        let models = support.appendingPathComponent("FluidAudio/Models", isDirectory: true)
        let other = models.appendingPathComponent("some-other-model", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let glossary = support.appendingPathComponent("glossary.json")
        let replacements = support.appendingPathComponent("replacements.json")
        try Data("[1]".utf8).write(to: glossary)
        try Data("[2]".utf8).write(to: replacements)
        defaults.set("normal", forKey: "correctionStrength")

        RetiredGlossaryHelper.cleanUp(applicationSupport: support, defaults: defaults)

        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path))
        XCTAssertEqual(try Data(contentsOf: glossary), Data("[1]".utf8))
        XCTAssertEqual(try Data(contentsOf: replacements), Data("[2]".utf8))
        XCTAssertEqual(defaults.string(forKey: "correctionStrength"), "normal")
    }

    /// `models.json` of a 0.2.0 install with the helper: the speech model stays, the helper's record goes.
    func testAnOldModelListWithTheHelperKeepsTheSpeechModel() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vypo-list-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = Store(directory: dir)
        let speech = dir.appendingPathComponent("Models/parakeet-ultra/parakeet-ultra", isDirectory: true)
        try FileManager.default.createDirectory(at: speech, withIntermediateDirectories: true)
        let helper = support.appendingPathComponent("elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: helper, withIntermediateDirectories: true)
        store.save([
            InstalledModel.Stored(id: "parakeet-ultra", path: speech.path, deletePath: speech.deletingLastPathComponent().path, sizeBytes: 1),
            InstalledModel.Stored(id: "ctc-vocab", path: helper.path, deletePath: helper.path, sizeBytes: 1),
        ], to: "models.json")

        let manager = ModelManager(store: store)
        XCTAssertTrue(manager.isInstalled(.parakeetUltra))
        XCTAssertEqual(manager.installed, [.parakeetUltra])
        XCTAssertTrue(FileManager.default.fileExists(atPath: speech.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: helper.path), "a path outside vypo's own folder is never deleted by the model list")
        let saved = try XCTUnwrap(store.load([InstalledModel.Stored].self, from: "models.json"))
        XCTAssertEqual(saved.map(\.id), ["parakeet-ultra"])
    }
}
