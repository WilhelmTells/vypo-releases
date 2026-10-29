import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts
import Observation
import SwiftUI

/// Runs `body` now and again whenever an observable value it read changes.
/// `body` must not write the values it reads.
@MainActor
func observeChanges(_ body: @escaping @MainActor () -> Void) {
    withObservationTracking {
        body()
    } onChange: {
        Task { @MainActor in observeChanges(body) }
    }
}

/// Wires the controllers together at launch.
@MainActor
final class AppCoordinator {
    let app: AppState
    let positioner = PillPositioner()
    var permissions: PermissionMonitor { app.permissions }
    let windows: WindowManager
    let memory = DictationMemory()
    /// The language of the previous dictation; short ones that can't be told apart keep it.
    private var lastLanguage: Lang?
    /// When the previous dictation was processed, for the pause in the timing log.
    private var lastProcessed: Date?
    private var memoryTimer: Timer?
    let muter = AudioMuter()
    let models: ModelService
    private(set) var pill: PillController!
    private(set) var recorder: AudioRecorder!
    private(set) var hotkey: HotkeyMonitor!
    /// Holds a dictation that found no text field on the clipboard until you paste it.
    private let clipboard = ClipboardKeeper()
    private(set) var dictation: DictationController!

    init(app: AppState) {
        self.app = app
        models = ModelService()
        windows = WindowManager(app: app)
        app.models = models
    }

    func start() {
        muter.restorePendingFromLastRun()
        #if DEBUG
        // For screenshots: `-VYPOOpenSettingsPane about` opens Settings on that pane at launch.
        if let name = UserDefaults.standard.string(forKey: "VYPOOpenSettingsPane"), let pane = SettingsPane(rawValue: name) {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.windows.showSettings(pane)
            }
        }
        #endif

        pill = PillController(app: app, positioner: positioner)
        app.pill = pill

        recorder = AudioRecorder(meter: app.levelMeter)
        hotkey = HotkeyMonitor()
        hotkey.onPaste = { [weak self] in self?.clipboard.userPasted() }
        hotkey.onKeyChange = { [weak self] down in self?.app.onKeyChange(down) }
        dictation = DictationController(app: app, recorder: recorder, muter: muter, hotkey: hotkey)
        dictation.inputDevice = { [prefs = app.prefs] in
            AudioDevices.resolveInputDevice(selectedUID: prefs.inputDeviceUID, preferBuiltIn: prefs.preferBuiltInMic)
        }
        dictation.onRecordingStarted = { [weak self] ctx in
            guard let self else { return }
            self.memory.recordingStarted()
            self.pill.reevaluateScreen()
            // Early, so an Electron app has its accessibility tree ready by the time of the paste.
            if let pid = ctx.pid { Task.detached { TextFieldProbe.enableAccessibility(pid: pid) } }
            // Load the model while the user is still talking.
            if let id = self.models.effectiveModel {
                Task { try? await self.models.engines.load(id) }
            }
        }
        dictation.modeForApp = { [weak app] bundleID in app?.profiles.mode(for: bundleID) ?? .standard }
        dictation.preflight = { [weak self] ctx in
            guard let self else { return nil }
            return self.models.effectiveModel == nil ? .modelMissing : nil
        }
        dictation.process = { [weak self] samples, ctx in
            await self?.transcribeAndPaste(samples, ctx)
        }

        observeChanges { [weak self] in
            guard let self else { return }
            let prefs = self.app.prefs
            self.hotkey.key = prefs.dictationKey
            self.hotkey.enabled = prefs.dictationEnabled && !self.app.dictationBlocked
            self.hotkey.holdToTalk = prefs.holdToTalk
            self.hotkey.doubleTapHandsFree = prefs.doubleTapHandsFree
        }
        hotkey.customShortcut = KeyboardShortcuts.getShortcut(for: .dictation)
        // KeyboardShortcuts posts this (internal) notification for every change made through its API.
        NotificationCenter.default.addObserver(forName: Notification.Name("KeyboardShortcuts_shortcutByNameDidChange"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.hotkey.customShortcut = KeyboardShortcuts.getShortcut(for: .dictation)
            }
        }
        observeChanges { [weak self] in
            guard let self else { return }
            let error = self.permissions.persistentError(dictationKey: self.app.prefs.dictationKey)
            if self.app.persistentError != error {
                Task { @MainActor in self.app.persistentError = error }
            }
        }

        RetiredGlossaryHelper.runAtLaunch()
        models.preload()
        app.onOpenSettings = { [weak self] pane in self?.windows.showSettings(pane) }
        app.onCopyLast = { [weak self] in self?.copyLastDictation() }
        app.onCopyDiagnostics = { [weak self] in self?.copyDiagnostics() }
        LoginItem.applyDefaultOnce()
        setUpOnboarding()

        KeyboardShortcuts.onKeyDown(for: .addToGlossary) { [weak self] in
            self?.addSelectedWord()
        }
        KeyboardShortcuts.onKeyDown(for: .copyLastDictation) { [weak self] in
            self?.copyLastDictation()
        }
        KeyboardShortcuts.onKeyDown(for: .undoDictation) { [weak self] in
            self?.undoLast()
        }
        app.onUndo = { [weak self] in self?.undoLast() }
        #if DEBUG
        app.onSaveLastRecording = { [weak self] in self?.saveLastRecording() }
        #endif

        // Samples and the last insertion live for 5 minutes, and never across sleep or quit.
        memoryTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.memory.expire()
                if self.app.lastInsertion != self.memory.last { self.app.lastInsertion = self.memory.last }
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.memory.clear()
                self?.app.lastInsertion = nil
            }
        }
        // ⌃⌥G adds for all languages, into General.
        app.onAddTerm = { [weak app] term in
            app?.glossary.add(term: term, scope: .all)
        }
        hotkey.onKeyPress = { [weak app] in
            if app?.pillBase == .add { app?.cancelAdd() }
        }

        app.history.startPruning { [prefs = app.prefs] in prefs.historyRetention }

        permissions.start()
        hotkey.start()
    }

    /// Transcribe → clean up → paste → history (§8).
    private func transcribeAndPaste(_ samples: [Float], _ ctx: RecordingContext) async {
        guard let modelID = models.effectiveModel else {
            app.showError(.modelMissing)
            app.report(.modelFailed)
            return
        }
        #if DEBUG
        // Debug builds only: the samples stay in memory for 5 minutes (Save last recording) or go to disk (benchmark).
        // A Release build keeps no audio once it is transcribed.
        memory.store(samples: samples)
        if app.keepBenchmarkRecordings { BenchmarkRecordings.keep(samples) }
        #endif
        guard let result = await transcribeAndInsert(samples, ctx, modelID: modelID) else { return }
        var historyID: UUID?
        if app.prefs.saveHistory {
            let item = HistoryItem(date: Date(), text: result.text, rawText: result.raw, appBundleID: ctx.bundleID,
                                   appName: ctx.appName, language: result.language, modelID: modelID.rawValue)
            app.history.add(item)
            historyID = item.id
        }
        remember(LastInsertion(text: result.text, pid: ctx.pid, date: Date(), language: result.language,
                               historyID: historyID, words: Self.wordCount(result.text), recordingSeconds: ctx.duration,
                               bundleID: ctx.bundleID))
        if let last = memory.last { app.count(last) }
    }

    /// Transcribes with `modelID`, detects the language, runs the text pipeline and inserts the result.
    /// Returns nil when nothing was inserted.
    private func transcribeAndInsert(_ samples: [Float], _ ctx: RecordingContext, modelID: ModelID)
        async -> (raw: String, text: String, language: Lang)? {
        let prefs = app.prefs
        let languages = prefs.languages
        let clock = ContinuousClock()
        let start = clock.now
        let memoryAtEnd = MemorySnapshot.current()
        let pause = lastProcessed.map { ctx.startedAt.timeIntervalSince($0) }
        defer { lastProcessed = Date() }
        let raw: String
        do {
            raw = try await models.transcribe(AudioPadding.padded(samples), with: modelID, hint: LanguageRouter.scriptHint(for: languages))
        } catch {
            guard !Task.isCancelled else { return nil }
            Log.asr.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
            app.showError(.modelError)
            app.report(.modelFailed)
            return nil
        }
        guard !Task.isCancelled else { return nil }
        let transcribed = clock.now
        let fallback = LanguageRouter.fallback(last: lastLanguage, chosen: languages)
        let wrongScript = LanguageRouter.isWrongScript(raw, among: languages)
        if wrongScript || LanguageRouter.isForeign(raw, among: languages) {
            // The model drifted into a neighbouring language (Danish for German) or another script (Cyrillic for
            // English and German, however short). Keep it in History, paste nothing.
            Log.asr.notice("Not pasted: \(wrongScript ? "wrong script" : "foreign language", privacy: .public), the transcript isn’t in a chosen language")
            if prefs.saveHistory {
                app.history.add(HistoryItem(date: Date(), text: raw, rawText: raw, appBundleID: ctx.bundleID,
                                            appName: ctx.appName, language: fallback, modelID: modelID.rawValue))
            }
            // “Didn’t catch that” would read as “nothing heard”; the text is in History, so say that.
            // No claim about the language: the detection can be wrong.
            app.showTransient(Self.filteredPillMode(savedToHistory: prefs.saveHistory), for: 4)
            app.report(.notInYourLanguages(heard: raw))
            return nil
        }
        let language = LanguageRouter.detect(raw, among: languages, fallback: fallback)
        lastLanguage = language
        let glossary = app.glossary.entries(for: language)
        let pipeline = PipelineContext(language: language, glossary: glossary,
                                       strength: prefs.correctionStrength, replacements: app.replacements.items,
                                       spellings: prefs.spellingsEnabled ? prefs.spellings : [],
                                       fillers: prefs.removeFillers ? prefs.fillerWords(for: language) : [],
                                       mode: ctx.mode, spokenPunctuation: prefs.spokenPunctuation,
                                       typographicQuotes: prefs.typographicQuotes)
        var text = TextPipeline.process(raw, pipeline) { word in
            MainActor.assumeIsolated { !TermExtractor.spellCheckerUnknown(word) }
        }
        guard !text.isEmpty else {
            Log.asr.notice("Nothing to insert: the transcript was \(raw.isEmpty ? "empty" : "removed by cleanup", privacy: .public)")
            app.report(.nothingHeard)
            return nil
        }
        // Smart spacing and capitalization, right before pasting (§23.1).
        if prefs.smartSpacing && prefs.pasteAutomatically {
            let context = if let read = ctx.insertion { await read.value } else { ContextReader.insertionContext() }
            text = ContextFormatter.format(text, context: context, language: language,
                                           glossaryTerms: Set(glossary.map(\.term)).union(prefs.spellingsEnabled ? prefs.spellings : []))
        }
        guard !Task.isCancelled else { return nil }
        let ready = clock.now
        Log.output.notice("Ready to paste \((ready - start).milliseconds) ms after recording ended (\(modelID.rawValue, privacy: .public), \(language.code, privacy: .public))")
        let asrTiming = await models.lastTiming(for: modelID)
        let timing = DictationTimingLog.line(audio: ctx.duration, pause: pause, transcribe: transcribed - start, asr: asrTiming,
                                             text: ready - transcribed, ready: ready - start, memory: memoryAtEnd)
        Log.asr.notice("\(timing, privacy: .public)")
        app.lastDictation = text
        if prefs.pasteAutomatically {
            // No text field: paste anyway (Accessibility may be wrong), but leave the text on the clipboard.
            // In the Finder, ⌘V would make a file of it, so only the clipboard.
            let front = NSWorkspace.shared.frontmostApplication
            let frontPID = front?.processIdentifier
            let probeStart = clock.now
            let probe = Task.detached {
                if let frontPID { TextFieldProbe.enableAccessibility(pid: frontPID) }
                return TextFieldProbe.focus()
            }
            let focus = await probe.value
            let probeTime = (clock.now - probeStart).milliseconds
            let frontApp = front?.bundleIdentifier
            let output = TextFieldProbe.output(for: focus, app: frontApp)
            let inTextField = output == .paste
            switch output {
            case .paste:
                clipboard.settle()
                Paster.paste(text, restoreClipboard: prefs.restoreClipboard)
            case .pasteAndKeep: clipboard.keep(text, restoreAfterPaste: prefs.restoreClipboard, paste: true)
            case .keep: clipboard.keep(text, restoreAfterPaste: prefs.restoreClipboard, paste: false)
            }
            Log.output.notice("Focus \(String(describing: focus), privacy: .public) in \(frontApp ?? "no app", privacy: .public) (\(probeTime) ms): \(String(describing: output), privacy: .public)")
            app.didInsertText()
            app.report(inTextField ? .pasted(text) : .clipboardOnly(text))
            if !inTextField { app.showNotice(.onClipboard) }
            // Prompt apps: Return 80 ms after the paste, if enabled.
            // Never after a lone symbol: "Slash" by itself must not send "/".
            if ProfileTweaks.sendsReturn(mode: ctx.mode, autoEnter: app.profiles.autoEnter(for: ctx.bundleID),
                                         inTextField: inTextField, text: text) {
                try? await Task.sleep(for: .milliseconds(80))
                Paster.postKey(kVK_Return)
            }
        } else {
            clipboard.settle()
            Paster.copy(text)
            app.didInsertText()
            app.report(.clipboardOnly(text))
            app.showNotice(.copied)
        }
        return (raw, text, language)
    }

    /// What the pill says when the language filter keeps a transcript out of the field. Without History
    /// nothing was kept, so it stays the plain error.
    static func filteredPillMode(savedToHistory: Bool) -> PillMode {
        savedToHistory ? .added(.savedToHistory) : .error(.notUnderstood)
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    private func remember(_ insertion: LastInsertion?) {
        if let insertion { memory.store(insertion) } else { memory.clear() }
        app.lastInsertion = memory.last
    }

    // MARK: Undo (§23.4)

    /// ⌃⌥Z
    func undoLast() {
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard dictation.phase == .idle, let last = memory.usable(frontPID: front) else { return }
        UndoPerformer.undo(last.text, access: AXInsertionAccess())
        app.showNotice(.undone)
        if let id = last.historyID { app.history.update(id) { $0.undone = true } }
        memory.forgetLast()
        app.lastInsertion = nil
        app.uncount(last)
    }

    #if DEBUG
    /// Debug: writes the last recording (kept for 5 minutes) to the Desktop as a WAV.
    private func saveLastRecording() {
        guard let samples = memory.samples, !samples.isEmpty else {
            app.showError(.noRecording)
            return
        }
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        let url = desktop.appendingPathComponent("vypo-last-recording.wav")
        do {
            try WAVFile.write(samples, to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            Log.audio.error("Saving the last recording failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    #endif

    /// The app's profile mode (§23.5).
    private func mode(for bundleID: String?) -> AppMode { app.profiles.mode(for: bundleID) }

    private var frontIsExcluded: Bool {
        mode(for: NSWorkspace.shared.frontmostApplication?.bundleIdentifier) == .excluded
    }

    // MARK: Onboarding (§16)

    private var onboarding: OnboardingModel?
    private(set) lazy var backPanel = BackToVypoPanel(app: app)

    private func setUpOnboarding() {
        windows.makeOnboarding = { [weak self] step in
            guard let self else { return AnyView(EmptyView()) }
            let model = OnboardingModel(step: step)
            model.onStepChanged = { [weak self] step in self?.windows.resizeOnboarding(forStep: step) }
            self.onboarding = model
            return AnyView(OnboardingView(model: model, finish: { [weak self] in self?.finishOnboarding() }).environment(self.app).tint(.vyAccent))
        }
        windows.onOnboardingClosed = { [weak self] in
            self?.onboarding = nil
            self?.app.pillVisible = true
            self?.app.dictationBlocked = false
            self?.backPanel.stop()
        }
        app.onOpenOnboarding = { [weak self] step in self?.showOnboarding(step: step ?? 0) }

        let prefs = app.prefs
        #if DEBUG
        // For screenshots of the live window: `-VYPOOnboardingStep 3` opens onboarding on that step (0 to 6).
        if let value = UserDefaults.standard.string(forKey: "VYPOOnboardingStep"), let step = Int(value) {
            showOnboarding(step: step)
            return
        }
        #endif
        if !prefs.onboardingCompleted {
            showOnboarding(step: 0)
        } else if !Permissions.micGranted || !Permissions.accessibilityTrusted {
            // A required permission went missing: start at the first incomplete step.
            showOnboarding(step: 1)
        }
    }

    func showOnboarding(step: Int) {
        app.pillVisible = false
        // The floating “Back to vypo” panel waits next to System Settings while step 2 asks for Accessibility.
        backPanel.isOnPermissionsStep = { [weak self] in self?.onboarding?.step == OnboardingStep.permissions.rawValue }
        backPanel.start()
        onboarding?.step = step
        windows.showOnboarding(step: step)
    }

    private func finishOnboarding() {
        app.prefs.onboardingCompleted = true
        windows.closeOnboarding()
        app.pillVisible = true
        app.dictationBlocked = false
        backPanel.stop()
    }

    /// ⌃⌥G: the pill opens with the selected word (§11.6).
    func addSelectedWord() {
        guard dictation.phase == .idle, app.pillBase != .add, !frontIsExcluded else { return }
        Task {
            let text = await SelectionReader.selectedText()
            app.beginAdd(prefill: text)
        }
    }

    /// ⌃⌥V: copies the last dictation; the pill shows “Copied”.
    private let diagnostics = DiagnosticsRun()

    /// Collects the diagnostics (the log takes a few seconds) and copies them: “Collecting diagnostics…”
    /// at once, “Copied” when done. Clicks while it runs are ignored.
    func copyDiagnostics() {
        guard !diagnostics.isRunning else { return }
        app.showTransient(.added(.collectingDiagnostics), for: 30)
        let snapshot = diagnosticsSnapshot()
        let speech = models.engines.engine(for: ModelCatalog.speech)
        // Never in the report: glossary terms and their spellings, app names and bundle IDs from the history.
        let words = app.glossary.entries.flatMap { [$0.term] + $0.soundsLike }
            + app.history.items.flatMap { [$0.appName, $0.appBundleID].compactMap { $0 } }
        diagnostics.start { [weak self] in
            guard let self else { return }
            var snapshot = snapshot
            if let speech, await speech.isLoaded { snapshot.speechModel += String(localized: ", loaded") }
            let log = await DiagnosticsLog.read(appPath: Bundle.main.bundlePath)
            let text = Diagnostics.report(snapshot, log: log, redacting: words, now: Date())
            clipboard.settle()
            Paster.copy(text)
            app.showNotice(.copied)
        }
    }

    private func diagnosticsSnapshot() -> DiagnosticsSnapshot {
        let info = Bundle.main.infoDictionary ?? [:]
        let active = Set(app.glossary.sets.filter(\.isActive).map(\.id))
        func state(_ id: ModelID) -> String {
            switch models.manager.state(id) {
            case .installed: String(localized: "installed")
            case .notInstalled: models.manager.isInstalled(id) ? String(localized: "installed") : String(localized: "not installed")
            case .queued: String(localized: "queued")
            case .downloading(let p): String(localized: "downloading \(Int(p * 100)) %")
            case .failed: String(localized: "download failed")
            }
        }
        return DiagnosticsSnapshot(
            version: info["CFBundleShortVersionString"] as? String ?? "?",
            build: info["CFBundleVersion"] as? String ?? "?",
            macOS: ProcessInfo.processInfo.operatingSystemVersionString,
            macModel: Diagnostics.sysctlString("hw.model"),
            chip: Diagnostics.sysctlString("machdep.cpu.brand_string"),
            memoryBytes: ProcessInfo.processInfo.physicalMemory,
            languages: app.prefs.languages.map(\.name),
            speechModel: state(ModelCatalog.speech),
            microphone: Permissions.micGranted,
            accessibility: Permissions.accessibilityTrusted,
            glossaryTerms: app.glossary.entries.count,
            activeGlossaryTerms: app.glossary.entries.filter { active.contains($0.setID ?? GlossarySet.generalID) }.count)
    }

    func copyLastDictation() {
        guard let text = app.history.items.first?.text ?? app.lastDictation else { return }
        clipboard.settle()
        Paster.copy(text)
        app.didInsertText()
        app.showNotice(.copied)
    }

    func shutdown() {
        memory.clear()
        dictation?.shutdown()
        muter.restore()
    }
}
