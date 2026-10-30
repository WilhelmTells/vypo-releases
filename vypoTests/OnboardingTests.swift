import XCTest
@testable import vypo

/// The onboarding's rules: which step may be left, what the path bar shows, how the microphone step hears
/// you, and how the Try it step reports each outcome.
@MainActor
final class OnboardingTests: XCTestCase {
    // MARK: Continue rules

    private func can(_ step: OnboardingStep, mic: Bool = true, ax: Bool = true, heard: Bool = false, skipped: Bool = false,
                     languages: Int = 1, key: DictationKey = .fn, globe: Int? = 0) -> Bool {
        OnboardingRules.canContinue(step: step.rawValue, micGranted: mic, accessibilityTrusted: ax, soundHeard: heard,
                                    skipped: skipped, languageCount: languages, key: key, globeKeyUsage: globe)
    }

    func testPermissionsNeedBoth() {
        XCTAssertTrue(can(.permissions))
        XCTAssertFalse(can(.permissions, mic: false))
        XCTAssertFalse(can(.permissions, ax: false))
        XCTAssertFalse(can(.permissions, mic: false, ax: false))
    }

    func testMicrophoneNeedsSoundOrSkip() {
        XCTAssertFalse(can(.microphone))
        XCTAssertTrue(can(.microphone, heard: true))
        XCTAssertTrue(can(.microphone, skipped: true))
    }

    func testLanguagesNeedOne() {
        XCTAssertTrue(can(.languages, languages: 1))
        XCTAssertFalse(can(.languages, languages: 0))
    }

    func testKeyStepBlocksOnlyWhenFnAndGlobeKeyIsUsed() {
        XCTAssertTrue(can(.key, key: .fn, globe: 0))
        // Anything but “Do Nothing”, and a missing value (macOS's default), keeps fn blocked.
        for usage in [1, 2, 3, nil] as [Int?] { XCTAssertFalse(can(.key, key: .fn, globe: usage), "usage \(String(describing: usage))") }
        // Another key doesn't care about the Globe setting.
        XCTAssertTrue(can(.key, key: .rightOption, globe: 2))
        XCTAssertTrue(can(.key, key: .custom, globe: nil))
    }

    func testTryItAndWelcomeAndDoneAlwaysContinue() {
        XCTAssertTrue(can(.tryIt, mic: false, ax: false, languages: 0, key: .fn, globe: nil))
        XCTAssertTrue(can(.welcome))
        XCTAssertTrue(can(.done))
    }

    func testGlobeWarningFixedDisappears() {
        XCTAssertTrue(OnboardingRules.globeWarningShown(key: .fn, globeKeyUsage: 2))
        XCTAssertFalse(OnboardingRules.globeWarningShown(key: .fn, globeKeyUsage: 0))
        XCTAssertFalse(OnboardingRules.globeWarningShown(key: .rightOption, globeKeyUsage: 2))
    }

    // MARK: Window and path bar

    func testWindowSizes() {
        XCTAssertEqual(OnboardingRules.windowSize(step: 0), CGSize(width: 400, height: 370))
        for step in 1...6 { XCTAssertEqual(OnboardingRules.windowSize(step: step), CGSize(width: 780, height: 520)) }
    }

    func testPathBarOnlyOnStepsTwoToSix() {
        XCTAssertEqual((0...6).filter(OnboardingRules.showsPathBar), [1, 2, 3, 4, 5])
    }

    func testCurrentStepKeepsItsCapsuleUntilContinue() {
        // On Try it the capsule stays on Try it, whatever the outcome; the step before is done.
        XCTAssertEqual(OnboardingRules.status(of: .tryIt, step: 5, permissionsOK: true), .current)
        XCTAssertEqual(OnboardingRules.status(of: .key, step: 5, permissionsOK: true), .done)
        XCTAssertEqual(OnboardingRules.status(of: .tryIt, step: 3, permissionsOK: true), .todo)
        XCTAssertEqual(OnboardingRules.status(of: .permissions, step: 1, permissionsOK: false), .current)
    }

    func testPermissionsTurnToAttentionWhenLostLater() {
        XCTAssertEqual(OnboardingRules.status(of: .permissions, step: 3, permissionsOK: false), .attention)
        XCTAssertEqual(OnboardingRules.status(of: .permissions, step: 3, permissionsOK: true), .done)
    }

    func testPathLabels() {
        XCTAssertEqual(PathItem.allCases.map(\.title), ["Model", "Permissions", "Microphone", "Languages", "Key", "Try it"])
    }

    // MARK: Model badge

    func testModelBadge() {
        func badge(_ s: ModelInstallState, loadFailed: Bool = false, failure: ModelProblem? = nil) -> ModelBadge {
            .make(state: s, loadFailed: loadFailed, failure: failure)
        }
        XCTAssertEqual(badge(.notInstalled), .notStarted)
        XCTAssertEqual(badge(.queued), .downloading(percent: 0))
        // The download fills 90 % of the bar; its percent is of the download.
        XCTAssertEqual(badge(.downloading(0.45)), .downloading(percent: 50))
        XCTAssertEqual(badge(.downloading(0.9)), .preparing)
        XCTAssertEqual(badge(.downloading(0.99)), .preparing)
        XCTAssertEqual(badge(.installed), .ready)
        XCTAssertEqual(badge(.installed, loadFailed: true), .failed(.couldntLoad))
        XCTAssertEqual(badge(.failed), .failed(.downloadFailed))
        XCTAssertEqual(badge(.failed, failure: .offline), .failed(.offline))
    }

    func testOfflineErrorsAreRecognizedAlsoWhenWrapped() {
        XCTAssertTrue(ModelManager.isOffline(URLError(.notConnectedToInternet)))
        let wrapped = NSError(domain: "FluidAudio", code: 1, userInfo: [NSUnderlyingErrorKey: URLError(.networkConnectionLost)])
        XCTAssertTrue(ModelManager.isOffline(wrapped))
        XCTAssertFalse(ModelManager.isOffline(URLError(.badServerResponse)))
        XCTAssertFalse(ModelManager.isOffline(NSError(domain: "x", code: 3)))
    }

    func testProgressText() {
        XCTAssertEqual(ModelPopover.progressText(percent: 30), "184 of 613 MB (30 %)")
    }

    // MARK: Microphone step

    func testSilenceNeverCountsAndSkipComesAfterTenSeconds() {
        var d = MicHeardDetector(now: 0)
        for i in 0..<300 { XCTAssertNil(d.feed(level: 0.05, now: Double(i) * 0.033)) }
        XCTAssertFalse(d.heard)
        XCTAssertFalse(d.showsSkip(now: 9.9))
        XCTAssertTrue(d.showsSkip(now: 10))
    }

    /// Feeds a constant level at about 30 fps and collects the events with their times.
    private func run(_ d: inout MicHeardDetector, from: Double, to: Double, level: Float) -> [(Double, MicHeardDetector.Event)] {
        var out: [(Double, MicHeardDetector.Event)] = []
        var t = from
        while t < to { if let e = d.feed(level: level, now: t) { out.append((t, e)) }; t += 0.033 }
        return out
    }

    func testAShortBlipIsNotAPhrase() {
        var d = MicHeardDetector(now: 0)
        XCTAssertTrue(run(&d, from: 1, to: 1.3, level: 0.8).isEmpty)
        XCTAssertTrue(run(&d, from: 1.3, to: 4, level: 0).isEmpty)
        XCTAssertFalse(d.heard)
    }

    func testAPhraseIsConfirmedHalfASecondAfterItEnds() {
        var d = MicHeardDetector(now: 0)
        XCTAssertTrue(run(&d, from: 1, to: 2, level: 0.7).isEmpty)      // still talking: nothing yet
        let events = run(&d, from: 2, to: 3, level: 0)
        XCTAssertEqual(events.map(\.1), [.phrase(number: 1)])
        XCTAssertEqual(events[0].0, 2.5, accuracy: 0.1)                  // 0.5 s of quiet after the last sound
        XCTAssertTrue(d.heard)
    }

    func testShortGapsBetweenWordsDoNotSplitThePhrase() {
        var d = MicHeardDetector(now: 0)
        var events = run(&d, from: 1, to: 1.4, level: 0.7)               // 0.4 s of sound, too short alone
        events += run(&d, from: 1.4, to: 1.8, level: 0)                  // gap below 0.5 s
        events += run(&d, from: 1.8, to: 2.2, level: 0.7)                // 0.8 s of sound in total
        XCTAssertTrue(events.isEmpty)
        events = run(&d, from: 2.2, to: 3, level: 0)
        XCTAssertEqual(events.map(\.1), [.phrase(number: 1)])
    }

    func testNonStopTalkingIsConfirmedAfterThreeSecondsOnce() {
        var d = MicHeardDetector(now: 0)
        let events = run(&d, from: 1, to: 9, level: 0.7)
        XCTAssertEqual(events.map(\.1), [.phrase(number: 1)])
        XCTAssertEqual(events[0].0, 4, accuracy: 0.1)                    // 3 s after the phrase began
        // The next phrase needs a quiet first.
        XCTAssertTrue(run(&d, from: 9, to: 9.3, level: 0).isEmpty)       // too short a quiet
        XCTAssertTrue(run(&d, from: 9.3, to: 10.5, level: 0.7).isEmpty)
        XCTAssertTrue(run(&d, from: 10.5, to: 11.5, level: 0).isEmpty)   // that sound belonged to the old phrase
        XCTAssertTrue(run(&d, from: 11.5, to: 12.5, level: 0.7).isEmpty)
        XCTAssertEqual(run(&d, from: 12.5, to: 13.5, level: 0).map(\.1), [.phrase(number: 2)])
    }

    func testASecondPhraseCountsAfterQuiet() {
        var d = MicHeardDetector(now: 0)
        var events = run(&d, from: 1, to: 2, level: 0.7)
        events += run(&d, from: 2, to: 3.2, level: 0)
        events += run(&d, from: 3.2, to: 4.2, level: 0.7)
        XCTAssertEqual(events.map(\.1), [.phrase(number: 1)])           // the second is still being said
        events += run(&d, from: 4.2, to: 5.2, level: 0)
        XCTAssertEqual(events.map(\.1), [.phrase(number: 1), .phrase(number: 2)])
        XCTAssertFalse(d.showsSkip(now: 60))                             // Skip is for silence only
    }

    func testPlayfulLinesTakeTurns() {
        let lines = (1...5).map(MicHeardDetector.playfulLine(forPhrase:))
        XCTAssertEqual(Array(lines.prefix(4)), ["Loud and clear.", "Nice voice.", "We hear you.", "Crystal clear."])
        XCTAssertEqual(lines[4], lines[0])
    }

    // MARK: Try it state machine

    private func state(model: TryItState.ModelStatus = .ready, focused: Bool = true, activity: TryItState.Activity = .idle,
                       outcome: TryItOutcome? = nil, ax: Bool = true) -> TryItState {
        TryItState(model: model, focused: focused, activity: activity, outcome: outcome, accessibilityTrusted: ax)
    }

    func testAreaFollowsModelFocusAndActivity() {
        XCTAssertEqual(state(model: .loading(percent: 64)).area, .locked(percent: 64))
        XCTAssertEqual(state(model: .failed).area, .locked(percent: nil))
        XCTAssertEqual(state(focused: false).area, .notFocused)
        XCTAssertEqual(state(focused: true).area, .ready)
        XCTAssertEqual(state(activity: .recording).area, .recording)
        XCTAssertEqual(state(activity: .processing).area, .processing)
        // The model wins over everything while it isn't ready.
        XCTAssertEqual(state(model: .loading(percent: 3), activity: .recording).area, .locked(percent: 3))
    }

    func testResultLineIsEmptyWhileWaitingAndWhileDictating() {
        XCTAssertNil(state(model: .loading(percent: 10), outcome: .nothingHeard).resultLine)
        XCTAssertNil(state(activity: .recording, outcome: .nothingHeard).resultLine)
        XCTAssertNil(state(activity: .processing, outcome: .inserted("x")).resultLine)
        XCTAssertEqual(state(outcome: .nothingHeard).resultLine, .nothingHeard)
    }

    func testResultStaysUntilTheNextAttemptStarts() {
        var s = state(outcome: .inserted("Hello"))
        XCTAssertEqual(s.resultLine, .inserted("Hello"))
        s.focused = false
        XCTAssertEqual(s.resultLine, .inserted("Hello"))
        s.attemptStarted()
        XCTAssertNil(s.resultLine)
    }

    func testModelFailureAlwaysShowsItsLine() {
        XCTAssertEqual(state(model: .failed).resultLine, .modelFailed)
    }

    func testRevokedAccessibilityIsReportedWhenNothingElseIs() {
        XCTAssertEqual(state(ax: false).resultLine, .couldntPaste(heard: nil))
        XCTAssertEqual(state(outcome: .nothingHeard, ax: false).resultLine, .nothingHeard)
    }

    func testEveryDictationOutcomeMapsToAResult() {
        func map(_ o: DictationOutcome, inField: Bool = false) -> TryItOutcome {
            TryItState.outcome(for: o) { _ in inField }
        }
        XCTAssertEqual(map(.pasted("Hi"), inField: true), .inserted("Hi"))
        // Pasted into vypo's own window but the text never arrived: reported, never silent.
        XCTAssertEqual(map(.pasted("Hi"), inField: false), .couldntPaste(heard: "Hi"))
        XCTAssertEqual(map(.clipboardOnly("Hi")), .couldntPaste(heard: "Hi"))
        XCTAssertEqual(map(.notInYourLanguages(heard: "Hallo")), .notInYourLanguages(heard: "Hallo"))
        XCTAssertEqual(map(.nothingHeard), .nothingHeard)
        XCTAssertEqual(map(.modelFailed), .modelFailed)
    }

    func testLanguageSentenceNamesTheLanguageOrStaysNeutral() {
        XCTAssertEqual(TryItStep.languageSentence("Hello, this is a test of the dictation."),
                       "This looks like English, which isn’t in your languages.")
        XCTAssertEqual(TryItStep.languageSentence("x"), "This doesn’t look like one of your languages.")
    }

    func testAppReportsOutcomesWithACounter() {
        let app = AppState(prefs: Preferences(defaults: UserDefaults(suiteName: "vypo.tests.outcome.\(UUID().uuidString)")!),
                           store: Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent("vypo-oc-\(UUID().uuidString)")))
        XCTAssertNil(app.lastOutcome)
        app.report(.nothingHeard)
        app.report(.nothingHeard)
        XCTAssertEqual(app.lastOutcome?.id, 2)
        XCTAssertEqual(app.lastOutcome?.outcome, .nothingHeard)
    }

    // MARK: Defaults of a first run

    func testFirstRunLanguagesAreTheMacsPlusEnglish() {
        XCTAssertEqual(Lang.firstRunSelection(preferred: ["de-DE", "en-US"]), [.de, .en])
        XCTAssertEqual(Lang.firstRunSelection(preferred: ["en-US"]), [.en])
        XCTAssertEqual(Lang.firstRunSelection(preferred: ["de-DE"]), [.de, .en])
        XCTAssertEqual(Lang.firstRunSelection(preferred: ["ja-JP"]), [.en])
        XCTAssertEqual(Lang.macLanguage(preferred: ["de-DE"]), .de)
        XCTAssertNil(Lang.macLanguage(preferred: ["ja-JP"]))
    }

    func testAtLeastOneLanguageStaysChosen() {
        let prefs = Preferences(defaults: UserDefaults(suiteName: "vypo.tests.lang.\(UUID().uuidString)")!, preferredLanguages: ["de-DE"])
        XCTAssertEqual(prefs.languages, [.de, .en])
        prefs.setChosen(.de, false)
        prefs.setChosen(.en, false)
        XCTAssertEqual(prefs.languages, [.en])
    }

    func testGlassIsTheDefaultPillAndAChoiceStays() {
        let fresh = UserDefaults(suiteName: "vypo.tests.pill.\(UUID().uuidString)")!
        XCTAssertEqual(Preferences(defaults: fresh).pillBackground, .glass)
        let chosen = UserDefaults(suiteName: "vypo.tests.pill.\(UUID().uuidString)")!
        chosen.set(PillBackground.dark.rawValue, forKey: DefaultsKey.pillBackground)
        XCTAssertEqual(Preferences(defaults: chosen).pillBackground, .dark)
    }

    // MARK: Back to vypo panel

    func testPanelShowsForSystemSettingsOnlyWhenWantedAndHidesForVypo() {
        let own = "com.wilhelmtells.vypo"
        XCTAssertEqual(BackToVypoPanel.action(activatedBundleID: "com.apple.systempreferences", ownBundleID: own, wanted: true), .show)
        XCTAssertEqual(BackToVypoPanel.action(activatedBundleID: "com.apple.systempreferences", ownBundleID: own, wanted: false), .none)
        XCTAssertEqual(BackToVypoPanel.action(activatedBundleID: own, ownBundleID: own, wanted: true), .hide)
        XCTAssertEqual(BackToVypoPanel.action(activatedBundleID: "com.apple.finder", ownBundleID: own, wanted: true), .none)
    }

    // MARK: Test build isolation

    func testTheTestBuildHasItsOwnIdentity() {
        XCTAssertNotEqual(RunEnvironment.testAppBundleID, "com.wilhelmtells.vypo")
        // Under XCTest the host is the real bundle, so the real folder is used for models only.
        XCTAssertFalse(RunEnvironment.isTestApp)
        XCTAssertEqual(RunEnvironment.realDirectory.lastPathComponent, "vypo")
    }

    // MARK: Done story

    func testDoneStoryFinalStillHasEverythingSettled() {
        let f = DoneStoryLayout.frame(DoneStoryLayout.lastFrame, animated: false)
        XCTAssertNil(f.mason)
        XCTAssertTrue(f.blowing)
        XCTAssertTrue(f.textVisible)
        XCTAssertEqual(f.boyOffset, CGPoint(x: 218.5, y: 13.8))
        XCTAssertEqual(f.pieces.count, 8)
        XCTAssertTrue(f.stars.isEmpty)
        XCTAssertTrue(f.puffs.isEmpty)
    }

    func testDoneStoryOrder() {
        func f(_ n: Int) -> DoneStoryLayout.Frame { DoneStoryLayout.frame(n, animated: true) }
        XCTAssertEqual(f(0).mason?.index, 0)
        XCTAssertEqual(f(17).mason?.index, 17)
        XCTAssertNotNil(f(18).crackPoints)
        XCTAssertEqual(f(18).crackPoints?.count, 4)
        XCTAssertEqual(f(19).crackPoints?.count, 7)
        XCTAssertNil(f(20).crackPoints)
        // The tablet breaks at frame 20 and the pieces fall and stay.
        XCTAssertTrue(f(19).pieces.allSatisfy { $0.offset == .zero })
        XCTAssertTrue(f(30).pieces.contains { $0.offset.height != 0 })
        XCTAssertEqual(f(60).pieces, f(90).pieces)
        // He looks down, turns away, leaves to the left, and is gone.
        XCTAssertEqual(f(23).mason?.index, 19)
        XCTAssertEqual(f(36).mason?.index, 22)
        XCTAssertEqual(f(37).mason?.mirrored, true)
        XCTAssertLessThan(f(45).mason?.offset.x ?? 0, f(40).mason?.offset.x ?? 0)
        XCTAssertNil(f(50).mason)
        // The boy enters from the right, sits at 54, the text appears with him, the fanfare at 58.
        XCTAssertGreaterThan(f(43).boyOffset.x, 520)
        XCTAssertLessThan(f(44).boyOffset.x, 600)
        XCTAssertFalse(f(53).textVisible)
        XCTAssertTrue(f(54).textVisible)
        XCTAssertFalse(f(57).blowing)
        XCTAssertTrue(f(58).blowing)
        XCTAssertEqual(f(61).stars.count, 2)
        XCTAssertTrue(f(90).stars.isEmpty)
    }

    func testDustOnlyOnEveryOtherPiece() {
        let landed = (20...40).map { DoneStoryLayout.frame($0, animated: true).puffs.count }
        XCTAssertGreaterThan(landed.max() ?? 0, 0)
        XCTAssertTrue(landed.allSatisfy { $0 <= 4 })
    }

    // MARK: Globe warning wording

    /// macOS labels the setting “Press 🌐 key to” or, on Macs without a Globe key, “Press fn key to”. Whether this Mac
    /// shows the one or the other can't be read reliably, so the card names both, in English and German.
    func testGlobeWarningNamesBothMacOSLabels() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("vypo/Localizable.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let strings = try XCTUnwrap(json?["strings"] as? [String: Any])
        let key = try XCTUnwrap(strings.keys.first { $0.contains("Do Nothing") && $0.hasPrefix("Set ") })
        XCTAssertTrue(key.contains("Press 🌐 key to") && key.contains("Press fn key to"), key)
        let de = (((strings[key] as? [String: Any])?["localizations"] as? [String: Any])?["de"] as? [String: Any])?["stringUnit"] as? [String: Any]
        let german = try XCTUnwrap(de?["value"] as? String)
        XCTAssertTrue(german.contains("Beim Drücken der 🌐︎-Taste") && german.contains("Beim Drücken der fn-Taste") && german.contains("Keine Aktion"), german)
    }

    // MARK: Accessibility request

    /// “Allow Accessibility…” shows the system prompt only; opening the pane too put System Settings over the prompt.
    func testRequestAccessibilityOnlyPromptsAndOpensNoURL() {
        let saved = Permissions.openURL
        defer { Permissions.openURL = saved }
        var opened: [URL] = []
        Permissions.openURL = { opened.append($0) }
        var prompts = 0
        var asked: CFDictionary?
        Permissions.requestAccessibility(prompt: { prompts += 1; asked = $0 })
        XCTAssertEqual(prompts, 1)
        XCTAssertEqual((asked as? [String: Bool])?["AXTrustedCheckOptionPrompt"], true)
        XCTAssertTrue(opened.isEmpty, "opened \(opened)")
        // The fallback button is the only way to the pane.
        Permissions.openAccessibilitySettings()
        XCTAssertEqual(opened, [Permissions.accessibilityPane])
    }
}
