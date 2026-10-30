import AppKit
import Observation

/// Root UI state, injected via `.environment` (§4).
@MainActor
@Observable
final class AppState {
    let prefs: Preferences
    let levelMeter = LevelMeter()
    let pillAdd = PillAddModel()
    let glossary: GlossaryStore
    /// Decided once, before `replacements` reads its file.
    let wordsLayout: WordsLayout
    let replacements: ReplacementStore
    /// Only in the `spokenCharacters` layout.
    let spokenCharacters: SpokenCharacterStore?
    let history: HistoryStore
    let profiles: AppProfileStore
    let stats: StatsStore
    let level: LevelStore
    /// `achievements.json`; filled once from the existing data on the first launch with it.
    let achievements: AchievementStore
    let levelPreview = LevelPreview()
    let permissions = PermissionMonitor()

    /// `AppleFnUsageType` as last polled.
    var globeKeyUsage: Int? { permissions.globeKeyUsage }

    /// The text of the last dictation, in memory.
    var lastDictation: String?
    /// Counts text pasted or copied by a dictation or ⌃⌥V; the menu bar mark plays its star on each.
    private(set) var insertions = 0
    /// The last insertion that undo can act on (mirrors `DictationMemory`).
    var lastInsertion: LastInsertion?

    /// The pill state requested by the dictation flow. The controller derives what is shown.
    var pillBase: PillMode = .ready
    /// A permission error that stays until fixed.
    var persistentError: PillError?
    /// False until onboarding is done.
    var pillVisible = true
    /// The selected Settings pane.
    var settingsPane: SettingsPane = .general

    @ObservationIgnored var pill: PillController?
    /// Set at launch (nil in unit tests).
    var models: ModelService?
    /// Sparkle; nil under tests, which must not look for updates.
    var updates: Updates?
    @ObservationIgnored private var transientToken = 0
    @ObservationIgnored private var appBeforeAdd: NSRunningApplication?

    /// Called with the confirmed term of the pill's glossary field.
    @ObservationIgnored var onAddTerm: (String) -> Void = { _ in }
    @ObservationIgnored var onStopTapped: () -> Void = {}
    @ObservationIgnored var onCopyLast: () -> Void = {}
    @ObservationIgnored var onCopyDiagnostics: () -> Void = {}
    @ObservationIgnored var onUndo: () -> Void = {}
    #if DEBUG
    // Debug builds only: the two places that write audio to disk (Debug menu). A Release build has neither.
    @ObservationIgnored var onSaveLastRecording: () -> Void = {}
    /// Debug: also write every recording to Benchmark/recordings. Not saved, so it is off after a relaunch.
    var keepBenchmarkRecordings = false
    #endif

    /// How the last dictation ended, with a counter so the same outcome twice still changes (the onboarding's Try it
    /// step reports it).
    private(set) var lastOutcome: (id: Int, outcome: DictationOutcome)?
    /// While onboarding is on a step before Try it, the dictation key only shows that it was pressed.
    var dictationBlocked = false
    /// The dictation key went down or up (step 5 of onboarding shows the press), whatever `dictationBlocked` says.
    @ObservationIgnored var onKeyChange: (Bool) -> Void = { _ in }

    func report(_ outcome: DictationOutcome) {
        lastOutcome = ((lastOutcome?.id ?? 0) + 1, outcome)
    }

    @ObservationIgnored var onOpenSettings: (SettingsPane?) -> Void = { _ in }
    @ObservationIgnored var onOpenOnboarding: (Int?) -> Void = { _ in }

    init(prefs: Preferences = Preferences(), store: Store = .shared, calendar: Calendar = .current) {
        self.prefs = prefs
        let glossary = GlossaryStore(store: store)
        self.glossary = glossary
        let wordsLayout = WordsLayout.resolve(store: store, defaults: prefs.defaults)
        self.wordsLayout = wordsLayout
        let replacements = ReplacementStore(store: store, defaults: prefs.defaults, layout: wordsLayout)
        self.replacements = replacements
        spokenCharacters = wordsLayout == .spokenCharacters ? SpokenCharacterStore(store: store) : nil
        let history = HistoryStore(store: store)
        self.history = history
        let profiles = AppProfileStore(store: store)
        self.profiles = profiles
        let stats = StatsStore(store: store)
        self.stats = stats
        let level = LevelStore(store: store, seedWords: stats.allTime)
        self.level = level
        achievements = AchievementStore(store: store, calendar: calendar, collecting: prefs.collectStats) {
            AchievementSeed.state(stats: stats.days, xpWords: level.xpWords, glossaryCount: glossary.entries.count,
                                  replacements: replacements.items, layout: wordsLayout, profiles: profiles.profiles,
                                  history: history.items, calendar: calendar)
        }
        glossary.onEntriesChanged = { [weak self] n in
            guard let self, self.prefs.collectStats else { return }
            self.achievements.glossaryCount(n)
        }
        replacements.onNewEntry = { [weak self] in self?.achievementReached(.ownReplacement) }
        profiles.onModeChanged = { [weak self] mode in
            if mode == .prompt || mode == .writing { self?.achievementReached(.promptOrWritingApp) }
        }
    }

    // MARK: Transient pill states

    /// Shows a mode for a while, then returns to `ready` if nothing else happened.
    func showTransient(_ mode: PillMode, for seconds: TimeInterval) {
        transientToken += 1
        let token = transientToken
        pillBase = mode
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.transientToken == token, self.pillBase == mode else { return }
            self.pillBase = .ready
        }
    }

    func showError(_ error: PillError) {
        showTransient(.error(error), for: error.duration)
    }

    func showNotice(_ notice: PillNotice) {
        showTransient(.added(notice), for: 1.6)
    }

    func didInsertText() { insertions += 1 }

    // MARK: Stats and level (§23.12)

    /// Stats, level and achievements count every successful paste. The text is only checked for “vypo”, never kept.
    func count(_ insertion: LastInsertion) {
        guard prefs.collectStats else { return }
        stats.record(words: insertion.words, seconds: insertion.recordingSeconds, language: insertion.language,
                     app: insertion.bundleID, at: insertion.date)
        level.add(words: insertion.words)
        achievements.dictated(DictationFacts(date: insertion.date, words: insertion.words, seconds: insertion.recordingSeconds,
                                             language: insertion.language, bundleID: insertion.bundleID,
                                             handsFree: insertion.handsFree, mentionsVypo: Achievements.mentionsVypo(insertion.text)),
                              savedMinutes: StatsMath.minutesSaved(words: stats.allTime, seconds: stats.allSeconds),
                              words: level.xpWords)
    }

    /// An undone dictation is subtracted from the stats; the level and the achievements never sink. The undo itself
    /// is Second Thoughts.
    func uncount(_ insertion: LastInsertion) {
        guard prefs.collectStats else { return }
        stats.record(words: insertion.words, seconds: insertion.recordingSeconds, language: insertion.language,
                     app: insertion.bundleID, at: insertion.date, sign: -1)
        achievements.reached(.undo)
    }

    /// Achievements stay: what was reached stays reached.
    func resetStats() {
        stats.reset()
        level.reset()
    }

    /// Nothing is collected while “Collect stats” is off.
    func achievementReached(_ flag: AchievementFlag) {
        guard prefs.collectStats else { return }
        achievements.reached(flag)
    }

    /// “Collect stats” switched on: what the glossary, replacements and app files tell is taken now; a store that was
    /// never filled is filled once.
    func collectStatsSwitchedOn() {
        let calendar = Calendar.current
        achievements.collectingAgain(seed: {
            AchievementSeed.state(stats: stats.days, xpWords: level.xpWords, glossaryCount: glossary.entries.count,
                                  replacements: replacements.items, layout: wordsLayout, profiles: profiles.profiles,
                                  history: history.items, calendar: calendar)
        }, files: {
            AchievementSeed.fromFiles(glossaryCount: glossary.entries.count, replacements: replacements.items,
                                      layout: wordsLayout, profiles: profiles.profiles)
        })
    }

    func setPill(_ mode: PillMode) {
        transientToken += 1
        pillBase = mode
    }

    // MARK: Glossary add flow (§6.5)

    func beginAdd(prefill: String) {
        appBeforeAdd = NSWorkspace.shared.frontmostApplication
        pillAdd.text = prefill
        setPill(.add)
    }

    func confirmAdd() {
        guard pillBase == .add else { return }
        let term = pillAdd.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { cancelAdd(); return }
        onAddTerm(term)
        showNotice(.termAdded(term))
        restoreFrontApp()
    }

    func cancelAdd() {
        guard pillBase == .add else { return }
        setPill(.ready)
        restoreFrontApp()
    }

    private func restoreFrontApp() {
        let app = appBeforeAdd
        appBeforeAdd = nil
        if let app, app != NSRunningApplication.current { app.activate() }
    }

    // MARK: Pill actions

    func pillStopTapped() { onStopTapped() }

    func openSettings(_ pane: SettingsPane? = nil) { onOpenSettings(pane) }
    func openAbout() { onOpenSettings(.about) }

    /// Click on an error opens the matching place (§18).
    func openErrorTarget(_ error: PillError) {
        switch error {
        case .noMicrophone, .globeKeyInUse, .tooQuiet: openSettings(.recording)
        case .micNotAllowed:
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
        case .noAccessibility: onOpenOnboarding(1)
        case .modelMissing, .modelError: openSettings(.general)
        case .secureInput, .offInThisApp, .noRecording, .notUnderstood: break
        }
    }
}

/// Settings sidebar panes (§15): how vypo works, speaking, how it looks, which words come out,
/// per-app behavior, and what you've dictated.
enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case general, recording, appearance, words, apps, history, stats, about

    var id: String { rawValue }

    /// Sidebar order (§15).
    static let visible: [SettingsPane] = allCases

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .recording: String(localized: "Recording")
        case .appearance: String(localized: "Appearance")
        case .words: String(localized: "Words")
        case .apps: String(localized: "Apps")
        case .history: String(localized: "History")
        case .stats: String(localized: "Stats")
        case .about: String(localized: "About")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .recording: "mic"
        case .appearance: "paintbrush"
        case .words: "book"
        case .apps: "app"
        case .history: "clock"
        case .stats: "chart.bar"
        case .about: "info.circle"
        }
    }

    var lead: String {
        switch self {
        case .general: String(localized: "How vypo starts, pastes and transcribes.")
        case .recording: String(localized: "How you start dictating, and what vypo listens with.")
        case .appearance: String(localized: "How vypo looks on your Mac.")
        case .words: String(localized: "Which words come out: your terms, replacements and filler words.")
        case .apps: String(localized: "What’s different in specific apps.")
        case .history: String(localized: "Your recent dictations, only on this Mac.")
        case .stats: String(localized: "How much you’ve dictated. Counted only on this Mac.")
        case .about: String(localized: "Version, updates, help, and what vypo is built on.")
        }
    }
}
