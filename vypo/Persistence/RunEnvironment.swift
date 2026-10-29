import Foundation

/// Where vypo keeps its data. Unit tests run inside the app (the test host starts the real app), so under XCTest
/// everything the app would save goes to a scratch folder and a scratch `UserDefaults` suite; the owner's data in
/// `~/Library/Application Support/vypo/` and in the app's real preferences is never touched. Only the speech models
/// are read from their real place, so tests don't load them again.
enum RunEnvironment {
    /// Whether the code runs under XCTest. The environment variable is set from the start of the test host, before
    /// the XCTest classes are loaded.
    static let isTesting: Bool = {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil
    }()

    /// The scratch folder of this test host: `$TMPDIR/vypo-tests-<pid>/`.
    static let testDirectory: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("vypo-tests-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)

    /// The bundle ID of the separate onboarding test build (`scripts/onboarding-test.sh`). It has its own
    /// preferences (a different bundle ID), its own permissions, and its own data folder, so a fresh-state run
    /// never touches the installed vypo.
    static let onboardingTestBundleID = "com.wilhelmtells.vypo.onboardingtest"

    /// Whether this is the separate onboarding test build.
    static var isOnboardingTestBuild: Bool { Bundle.main.bundleIdentifier == onboardingTestBundleID }

    /// The real folder, `~/Library/Application Support/vypo/`; the test build's is `vypo-onboardingtest/`.
    static var realDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(isOnboardingTestBuild ? "vypo-onboardingtest" : "vypo", isDirectory: true)
    }
}

/// The app's preferences: `UserDefaults.standard`, or under XCTest a suite of its own, empty at the start.
enum AppDefaults {
    static let suiteName: String = RunEnvironment.isTesting ? "vypo.tests.\(ProcessInfo.processInfo.processIdentifier)" : (Bundle.main.bundleIdentifier ?? "")

    nonisolated(unsafe) static let standard: UserDefaults = {
        guard RunEnvironment.isTesting, let suite = UserDefaults(suiteName: suiteName) else { return .standard }
        suite.removePersistentDomain(forName: suiteName)
        return suite
    }()
}
