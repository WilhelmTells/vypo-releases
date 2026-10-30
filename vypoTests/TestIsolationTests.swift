import XCTest
@testable import vypo

/// Tests run inside the real app; they must never touch the owner's data or preferences.
@MainActor
final class TestIsolationTests: XCTestCase {
    func testTheSharedStoreIsNotTheRealOne() {
        XCTAssertTrue(RunEnvironment.isTesting)
        let shared = Store.shared.directory.standardizedFileURL.path
        let real = RunEnvironment.realDirectory.standardizedFileURL.path
        XCTAssertNotEqual(shared, real)
        XCTAssertFalse(shared.hasPrefix(real), "not even below it")
        XCTAssertTrue(shared.hasPrefix(FileManager.default.temporaryDirectory.standardizedFileURL.path))
        XCTAssertTrue(shared.contains("vypo-tests-"))
        XCTAssertNotEqual(Store.defaultDirectory.standardizedFileURL.path, shared == real ? "" : shared)
    }

    func testOnlyTheModelsAreReadFromTheRealPlace() {
        XCTAssertEqual(Store.shared.modelsDirectory.standardizedFileURL.path,
                       RunEnvironment.realDirectory.appendingPathComponent("Models").standardizedFileURL.path)
        XCTAssertEqual(Store(directory: URL(fileURLWithPath: "/tmp/x")).modelsDirectory.path, "/tmp/x/Models")
    }

    func testPreferencesAreASuiteOfTheirOwn() {
        XCTAssertNotEqual(AppDefaults.suiteName, Bundle.main.bundleIdentifier)
        XCTAssertTrue(AppDefaults.suiteName.hasPrefix("vypo.tests."))
        let key = "isolationProbe-\(UUID().uuidString)"
        AppDefaults.standard.set(true, forKey: key)
        defer { AppDefaults.standard.removeObject(forKey: key) }
        XCTAssertNil(UserDefaults.standard.object(forKey: key), "not in the app's real preferences")
        XCTAssertNil(UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?[key])
    }

    func testTheAppStateOfTheHostUsesThem() {
        let app = AppState()
        XCTAssertEqual(app.prefs.defaults, AppDefaults.standard)
        app.replacements.upsert(Replacement(spoken: "isolation", output: "x"))
        let real = RunEnvironment.realDirectory.appendingPathComponent("replacements.json")
        XCTAssertFalse((try? String(contentsOf: real, encoding: .utf8))?.contains("isolation") ?? false)
    }

    /// `AppCoordinator.start()` under a test must not turn the test host into the user's login item.
    func testATestHostIsNeverRegisteredAsALoginItem() {
        let defaults = UserDefaults(suiteName: "vypo.tests.\(UUID().uuidString)")!
        LoginItem.applyDefaultOnce(defaults)
        XCTAssertFalse(defaults.bool(forKey: "openAtLoginConfigured"))
    }
}
