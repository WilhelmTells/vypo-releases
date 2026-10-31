import SwiftUI
import XCTest
@testable import vypo

/// Renders every onboarding state to PNGs (light and dark) for review. Runs only when `VYPO_SNAPSHOT_DIR` is set
/// (`TEST_RUNNER_VYPO_SNAPSHOT_DIR=… scripts/test.sh -only-testing:vypoTests/OnboardingSnapshotTests`); with
/// `-testLanguage de -testRegion DE` the same states render in German (file names get the `-de` suffix).
@MainActor
final class OnboardingSnapshotTests: XCTestCase {
    private var dir: URL? {
        ProcessInfo.processInfo.environment["VYPO_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    }

    private var suffix: String {
        (Bundle.main.preferredLocalizations.first ?? "en").hasPrefix("de") ? "-de" : ""
    }

    private func shoot<V: View>(_ name: String, size: CGSize, schemes: [Bool] = [false, true], @ViewBuilder _ view: () -> V) throws {
        guard let dir else { throw XCTSkip("No snapshot dir") }
        for dark in schemes {
            let host = NSHostingView(rootView: view().frame(width: size.width, height: size.height))
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.contentView = host
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { XCTFail("no rep"); return }
            host.cacheDisplay(in: host.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent("\(name)\(suffix)-\(dark ? "dark" : "light").png"))
            window.close()
        }
    }

    /// An app on a scratch store with the permissions and the model in the given state.
    private func app(mic: Bool = true, micDenied: Bool = false, ax: Bool = true, globe: Int? = 0, model: ModelInstallState = .installed,
                     failure: ModelProblem? = nil, loadFailed: Bool = false, languages: [Lang] = [.en],
                     key: DictationKey = .fn) -> AppState {
        let store = Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent("vypo-onb-\(UUID().uuidString)"))
        let prefs = Preferences(defaults: UserDefaults(suiteName: "vypo.snap.\(UUID().uuidString)")!)
        let app = AppState(prefs: prefs, store: store)
        prefs.languages = languages
        prefs.dictationKey = key
        let service = ModelService(manager: ModelManager(store: store))
        service.manager.setPreviewState(model, failure: failure)
        service.loadFailed = loadFailed
        app.models = service
        app.permissions.micGranted = mic
        app.permissions.micDenied = micDenied
        app.permissions.accessibilityTrusted = ax
        app.permissions.globeKeyUsage = globe
        return app
    }

    private func onboarding(_ app: AppState, step: Int, size: CGSize = CGSize(width: 780, height: 520),
                            preview: (inout OnboardingPreview, OnboardingModel) -> Void = { _, _ in }) -> some View {
        let model = OnboardingModel(step: step)
        var p = OnboardingPreview()
        preview(&p, model)
        model.preview = p
        return OnboardingView(model: model, finish: {}).environment(app).tint(Color.vyAccent)
    }

    private let big = CGSize(width: 780, height: 520)

    func testWelcome() throws {
        try shoot("s1-welcome", size: CGSize(width: 400, height: 370)) { onboarding(app(model: .notInstalled), step: 0) }
    }

    func testPermissions() throws {
        let none = app(mic: false, ax: false, model: .downloading(0.3))
        try shoot("s2-none", size: big) { onboarding(none, step: 1) }
        try shoot("s2-details", size: big) { onboarding(none, step: 1) { p, _ in p.permissionsDetails = true } }
        try shoot("s2-mic-only", size: big) { onboarding(app(mic: true, ax: false, model: .downloading(0.3)), step: 1) }
        try shoot("s2-waiting", size: big) { onboarding(app(mic: true, ax: false, model: .downloading(0.3)), step: 1) { p, _ in p.permissionsAsked = true } }
        try shoot("s2-both", size: big) { onboarding(app(model: .downloading(0.3)), step: 1) }
        try shoot("s2-mic-denied", size: big) { onboarding(app(mic: false, micDenied: true, ax: false, model: .downloading(0.3)), step: 1) }
        try shoot("s2-back-waiting", size: CGSize(width: 400, height: 100)) {
            let a = app(ax: false); return BackToVypoView(app: a, back: {}).environment(a).background(Color.vyBgWindow)
        }
        try shoot("s2-back-on", size: CGSize(width: 400, height: 100)) {
            let a = app(ax: true); return BackToVypoView(app: a, back: {}).environment(a).background(Color.vyBgWindow)
        }
    }

    func testMicrophone() throws {
        let a = app(model: .downloading(0.6))
        try shoot("s3-listening", size: big) { onboarding(a, step: 2) { p, _ in p.micLevel = 0 } }
        try shoot("s3-listening-level", size: big) { onboarding(a, step: 2) { p, _ in p.micLevel = 0.6 } }
        try shoot("s3-good", size: big) { onboarding(a, step: 2) { p, m in p.micLevel = 0.6; p.micLine = "Loud and clear."; m.micHeard = true } }
        try shoot("s3-silent", size: big) { onboarding(a, step: 2) { p, m in p.micLevel = 0; p.micSilent = true; m.micShowsSkip = true } }
    }

    func testLanguages() throws {
        try shoot("s4-default", size: big) { onboarding(app(model: .downloading(0.8), languages: [.de, .en]), step: 3) }
        try shoot("s4-english", size: big) { onboarding(app(model: .downloading(0.95)), step: 3) }
        try shoot("s4-many", size: big) { onboarding(app(model: .installed, languages: [.de, .en, .fr, .es, .it]), step: 3) }
        try shoot("s4-picker", size: CGSize(width: 300, height: 260)) {
            let a = app(languages: [.de, .en])
            return LanguageList(order: LanguagesStep.listOrder(chosen: [.de, .en])).environment(a).background(Color.vyBgGroup)
        }
    }

    func testKey() throws {
        let a = app()
        try shoot("s5-waiting", size: big) { onboarding(a, step: 4) }
        try shoot("s5-pressed", size: big) { onboarding(a, step: 4) { p, _ in p.keyPressed = true; p.keyDetected = true } }
        try shoot("s5-detected", size: big) { onboarding(a, step: 4) { p, _ in p.keyDetected = true } }
        try shoot("s5-fn-wrong", size: big) { onboarding(app(globe: 2), step: 4) { p, _ in p.keyDetected = true } }
        try shoot("s5-other", size: big) { onboarding(app(globe: 2, key: .rightOption), step: 4) { p, _ in p.keyDetected = true } }
        // A custom shortcut (⌥G) is two keycaps; shown here directly, since the recorded shortcut lives in the real preferences.
        try shoot("s5-custom", size: CGSize(width: 460, height: 200)) {
            HStack(spacing: 12) {
                Keycap(content: .modifier(symbol: "⌥", name: "option"), pressed: true)
                Keycap(content: .character("G"), pressed: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.vyBgWindow)
        }
    }

    func testTryIt() throws {
        func tryIt(_ name: String, _ a: AppState, outcome: TryItOutcome? = nil, text: String = "", focused: Bool? = true,
                   pill: PillMode = .ready) throws {
            a.pillBase = pill
            try shoot(name, size: big) { onboarding(a, step: 5) { p, _ in p.tryOutcome = outcome; p.tryText = text; p.tryFocused = focused } }
        }
        try tryIt("s6-locked", app(model: .downloading(0.576)), focused: false)
        try tryIt("s6-unfocused", app(), focused: false)
        try tryIt("s6-ready", app(), focused: true)
        try tryIt("s6-recording", app(), focused: true, pill: .listening)
        try tryIt("s6-processing", app(), focused: true, pill: .processing)
        try tryIt("s6-success", app(), outcome: .inserted("vypo turns my voice into text on my own Mac."),
                  text: "vypo turns my voice into text on my own Mac.")
        try tryIt("s6-not-in-languages", app(languages: [.de]), outcome: .notInYourLanguages(heard: "Hello, this is a test of the dictation."))
        try tryIt("s6-long", app(languages: [.de]), outcome: .notInYourLanguages(heard: "Hello, this is a rather long test of the dictation to see how the wrong language hint behaves when the heard text keeps going and going."))
        try tryIt("s6-too-quiet", app(), outcome: .nothingHeard)
        try tryIt("s6-couldnt-paste", app(ax: false), outcome: .couldntPaste(heard: "Hello, this is a test."))
        try tryIt("s6-didnt-arrive", app(), outcome: .didntArrive(heard: "Hello, this is a test."))
        try tryIt("s6-another-window", app(), outcome: .anotherWindowInFront(heard: "vypo turns my voice into text on my own Mac."))
        try tryIt("s6-ax-revoked", app(ax: false), focused: true)
        try tryIt("s6-model-failed", app(model: .installed, loadFailed: true), focused: false)
    }

    func testDone() throws {
        try shoot("s7-done", size: big) { onboarding(app(), step: 6) }
        // The text appears only at the end of the story; show it at once.
        try shoot("s7-done-text", size: big) { DoneStep(start: {}, showTextAtOnce: true).environment(app()).background(Color.vyBgWindow).tint(Color.vyAccent) }
        for f in [0, 12, 18, 19, 22, 30, 40, 47, 56, 62, 66] {
            try shoot("s7-frame-\(f)", size: CGSize(width: 520, height: 180), schemes: [false]) {
                DoneStage(frameNumber: f, animated: true)
            }
        }
    }

    func testPathBarStates() throws {
        let a = app(mic: true, ax: true, model: .downloading(0.45))
        try shoot("pathbar-downloading", size: big) { onboarding(a, step: 3) }
        try shoot("pathbar-popover-downloading", size: CGSize(width: 260, height: 120)) {
            ModelPopover(badge: .downloading(percent: 30)).environment(a).background(Color.vyBgGroup)
        }
        try shoot("pathbar-preparing", size: big) { onboarding(app(model: .downloading(0.93)), step: 3) }
        try shoot("pathbar-ready", size: big) { onboarding(app(model: .installed), step: 3) }
        try shoot("pathbar-failed", size: big) { onboarding(app(model: .failed, failure: .downloadFailed), step: 3) }
        try shoot("pathbar-offline", size: big) { onboarding(app(mic: false, ax: false, model: .failed, failure: .offline), step: 4) }
        try shoot("pathbar-popover-offline", size: CGSize(width: 260, height: 120)) {
            ModelPopover(badge: .failed(.offline)).environment(a).background(Color.vyBgGroup)
        }
    }
}
