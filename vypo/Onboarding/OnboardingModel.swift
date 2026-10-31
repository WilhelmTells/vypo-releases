import Foundation
import Observation

/// The seven steps (0.3.0): the path bar shows steps 2 to 6; Welcome and Done stand alone.
enum OnboardingStep: Int, CaseIterable {
    case welcome, permissions, microphone, languages, key, tryIt, done
}

/// What the path bar shows besides the model: one item per step 2 to 6.
enum PathItem: Int, CaseIterable, Identifiable {
    case model = 0, permissions, microphone, languages, key, tryIt

    var id: Int { rawValue }

    /// The step this item belongs to; the model has none.
    var step: OnboardingStep? { OnboardingStep(rawValue: rawValue) }

    var title: String {
        switch self {
        case .model: String(localized: "Model")
        case .permissions: String(localized: "Permissions")
        case .microphone: String(localized: "Microphone")
        case .languages: String(localized: "Languages")
        case .key: String(localized: "Key")
        case .tryIt: String(localized: "Try it")
        }
    }
}

enum PathItemStatus: Equatable {
    case todo, current, done, attention
}

/// The model item of the path bar and its popover.
enum ModelProblem: Equatable {
    case downloadFailed, offline, couldntLoad
}

enum ModelBadge: Equatable {
    case notStarted
    case downloading(percent: Int)
    case preparing
    case ready
    case failed(ModelProblem)

    /// The speech model's state as the path bar shows it. The last 10 % of the download is the compile.
    static func make(state: ModelInstallState, loadFailed: Bool, failure: ModelProblem?) -> ModelBadge {
        switch state {
        case .notInstalled: .notStarted
        case .queued: .downloading(percent: 0)
        case .downloading(let p): p >= 0.9 ? .preparing : .downloading(percent: Int((p / 0.9 * 100).rounded(.down)))
        case .installed: loadFailed ? .failed(.couldntLoad) : .ready
        case .failed: .failed(failure ?? .downloadFailed)
        }
    }

    var isReady: Bool { self == .ready }
}

/// Which step may be left with Continue, and what the path bar shows. Pure, so it is tested.
enum OnboardingRules {
    /// Step 2 needs both permissions, step 3 sound (or Skip), step 4 a language, step 5 a key that
    /// macOS doesn't also use; step 6 always.
    static func canContinue(step: Int, micGranted: Bool, accessibilityTrusted: Bool, soundHeard: Bool, skipped: Bool,
                            languageCount: Int, key: DictationKey, globeKeyUsage: Int?) -> Bool {
        switch OnboardingStep(rawValue: step) {
        case .permissions: micGranted && accessibilityTrusted
        case .microphone: soundHeard || skipped
        case .languages: languageCount >= 1
        case .key: !globeWarningShown(key: key, globeKeyUsage: globeKeyUsage)
        default: true
        }
    }

    /// The Globe key warning: only while fn is the key and macOS does something else with it.
    /// `AppleFnUsageType` 0 is “Do Nothing”; a missing value is macOS's default, which is not.
    static func globeWarningShown(key: DictationKey, globeKeyUsage: Int?) -> Bool {
        key == .fn && globeKeyUsage != 0
    }

    /// The path bar item of a step 2 to 6. The current step keeps its capsule until Continue.
    static func status(of item: PathItem, step: Int, permissionsOK: Bool) -> PathItemStatus {
        guard let own = item.step else { return .todo }
        if step == own.rawValue { return .current }
        guard step > own.rawValue else { return .todo }
        if item == .permissions && !permissionsOK { return .attention }
        return .done
    }

    /// Steps without a path bar.
    static func showsPathBar(step: Int) -> Bool { (1...5).contains(step) }

    /// The window size of a step.
    static func windowSize(step: Int) -> CGSize {
        step == 0 ? CGSize(width: 400, height: 370) : CGSize(width: 780, height: 520)
    }
}

// MARK: Microphone step

/// Listens to the level of step 3. A phrase is confirmed at its end, so the sound and the green line don't
/// come while the tester is still talking: it needs `minSound` of sound above the threshold in total (short
/// gaps between words don't reset it) and then `confirmQuiet` of quiet. If the sound goes on, it is confirmed
/// after `maxPhrase` anyway, and the next phrase needs a quiet first. Pure over (level, time), so it is tested.
struct MicHeardDetector {
    static let threshold: Float = 0.3
    /// Sound above the threshold a phrase needs in total.
    static let minSound: TimeInterval = 0.6
    /// Quiet after such a phrase that confirms it (also the longest gap inside a phrase).
    static let confirmQuiet: TimeInterval = 0.5
    /// A phrase that doesn't stop is confirmed after this long.
    static let maxPhrase: TimeInterval = 3
    static let skipAfter: TimeInterval = 10

    private(set) var attempts = 0
    private var startedAt: TimeInterval
    private var phraseStart: TimeInterval?
    private var soundTotal: TimeInterval = 0
    private var lastLoud: TimeInterval = 0
    private var lastFeed: TimeInterval?
    /// After a phrase confirmed by `maxPhrase` while still loud: wait for quiet before a new one begins.
    private var needsQuiet = false

    init(now: TimeInterval) { startedAt = now }

    var heard: Bool { attempts > 0 }

    /// `.phrase(number: 1)` is the first phrase (the confirmation sound plays once).
    enum Event: Equatable { case phrase(number: Int) }

    mutating func feed(level: Float, now: TimeInterval) -> Event? {
        let dt = min(max(now - (lastFeed ?? now), 0), 0.1)
        lastFeed = now
        let loud = level >= Self.threshold
        if loud {
            if needsQuiet { lastLoud = now; return nil }
            if phraseStart == nil { phraseStart = now; soundTotal = 0 }
            soundTotal += dt
            lastLoud = now
        } else if needsQuiet {
            if now - lastLoud >= Self.confirmQuiet { needsQuiet = false }
            return nil
        }
        guard let start = phraseStart else { return nil }
        if loud {
            if now - start >= Self.maxPhrase && soundTotal >= Self.minSound {
                needsQuiet = true
                return confirm()
            }
        } else if now - lastLoud >= Self.confirmQuiet {
            return soundTotal >= Self.minSound ? confirm() : discard()
        }
        return nil
    }

    private mutating func confirm() -> Event {
        phraseStart = nil
        soundTotal = 0
        attempts += 1
        return .phrase(number: attempts)
    }

    private mutating func discard() -> Event? {
        phraseStart = nil
        soundTotal = 0
        return nil
    }

    /// Nothing heard for about ten seconds since the step opened.
    func showsSkip(now: TimeInterval) -> Bool { !heard && now - startedAt >= Self.skipAfter }

    /// One of the playful lines per phrase, in turn.
    static func playfulLine(forPhrase number: Int) -> String {
        let lines = [String(localized: "Loud and clear."), String(localized: "Nice voice."),
                     String(localized: "We hear you."), String(localized: "Crystal clear.")]
        return lines[(max(number, 1) - 1) % lines.count]
    }
}

// MARK: Try it

/// How one dictation ended, as the Try it step reports it.
enum TryItOutcome: Equatable {
    case inserted(String)
    case notInYourLanguages(heard: String)
    case nothingHeard
    /// `heard` is nil when no text was produced (Accessibility is off).
    case couldntPaste(heard: String?)
    /// Accessibility is on, but the text did not arrive in the field.
    case didntArrive(heard: String)
    /// Another window stayed in front and vypo could not get there, so nothing was pasted (the text is on the clipboard).
    case anotherWindowInFront(heard: String)
    case modelFailed
}

/// What the dictation flow reports to the app after each attempt.
enum DictationOutcome: Equatable, Sendable {
    /// ⌘V was posted into a text field; whether the text arrived is for the caller to check.
    case pasted(String)
    /// The text stayed on the clipboard (no text field in front).
    case clipboardOnly(String)
    /// Try it was open, another window stayed in front and vypo could not come forward: no ⌘V was posted.
    case anotherWindowInFront(String)
    case notInYourLanguages(heard: String)
    case nothingHeard
    case modelFailed
}

/// The Try it step's state: the area, the pill and the result line follow from these four inputs.
struct TryItState: Equatable {
    enum ModelStatus: Equatable { case loading(percent: Int), ready, failed }
    enum Activity: Equatable { case idle, recording, processing }
    enum Area: Equatable { case locked(percent: Int?), notFocused, ready, recording, processing }

    var model: ModelStatus
    var focused = false
    var activity: Activity = .idle
    var outcome: TryItOutcome?
    var accessibilityTrusted = true

    var area: Area {
        switch model {
        case .loading(let p): return .locked(percent: p)
        case .failed: return .locked(percent: nil)
        case .ready: break
        }
        switch activity {
        case .recording: return .recording
        case .processing: return .processing
        case .idle: return focused ? .ready : .notFocused
        }
    }

    /// The line under the area; it stays until the next attempt starts.
    var resultLine: TryItOutcome? {
        if model == .failed { return .modelFailed }
        if case .loading = model { return nil }
        if activity != .idle { return nil }
        if let outcome { return Self.matching(outcome, accessibilityTrusted: accessibilityTrusted) }
        return accessibilityTrusted ? nil : .couldntPaste(heard: nil)
    }

    /// The Accessibility hint only shows when Accessibility is really off, whatever it was when the paste failed.
    static func matching(_ outcome: TryItOutcome, accessibilityTrusted: Bool) -> TryItOutcome {
        switch outcome {
        case .couldntPaste(let heard?) where accessibilityTrusted: .didntArrive(heard: heard)
        case .didntArrive(let heard) where !accessibilityTrusted: .couldntPaste(heard: heard)
        default: outcome
        }
    }

    mutating func attemptStarted() { outcome = nil }

    /// Maps what the flow reported. `fieldText` is what the field holds right now: a paste into vypo's
    /// own window counts only if the text is there.
    static func outcome(for result: DictationOutcome, accessibilityTrusted: Bool = true,
                        fieldContains: (String) -> Bool) -> TryItOutcome {
        switch result {
        case .pasted(let text):
            fieldContains(text) ? .inserted(text) : matching(.couldntPaste(heard: text), accessibilityTrusted: accessibilityTrusted)
        case .clipboardOnly(let text): matching(.couldntPaste(heard: text), accessibilityTrusted: accessibilityTrusted)
        case .anotherWindowInFront(let text): .anotherWindowInFront(heard: text)
        case .notInYourLanguages(let heard): .notInYourLanguages(heard: heard)
        case .nothingHeard: .nothingHeard
        case .modelFailed: .modelFailed
        }
    }
}

// MARK: Model

/// States for snapshots and tests: what a step shows without a microphone, a key press or a permission dialog.
struct OnboardingPreview {
    var permissionsAsked = false
    var permissionsDetails = false
    var micLine: String?
    var micSilent = false
    var micLevel: Float?
    var keyPressed = false
    var keyDetected = false
    var languagesListOpen = false
    var tryOutcome: TryItOutcome?
    var tryText = ""
    var tryFocused: Bool?
}

/// Onboarding state shared by the steps.
@MainActor
@Observable
final class OnboardingModel {
    static let stepCount = OnboardingStep.allCases.count

    var step: Int {
        didSet { if step != oldValue { direction = step > oldValue ? 1 : -1 } }
    }
    /// 1 forward, -1 back, for the slide of the step change.
    private(set) var direction = 1
    /// Step 3: sound was heard, Skip is offered, Skip was taken.
    var micHeard = false
    var micShowsSkip = false
    var micSkipped = false
    /// Set by snapshots and tests only.
    @ObservationIgnored var preview = OnboardingPreview()
    /// Try it: the text field has the cursor and the window is key (set by the step).
    var tryItFieldFocused = false
    /// Try it: counts up when the dictation asks for the cursor in the field (the step answers it).
    var tryItFocusRequests = 0
    /// The window size follows the step; set by the window manager.
    @ObservationIgnored var onStepChanged: (Int) -> Void = { _ in }

    init(step: Int) {
        self.step = min(max(step, 0), Self.stepCount - 1)
    }
}

/// Try it: waits for the pasted text to show up in the field. Checks again and again until the text is there, and
/// at the latest when the clipboard restore is done (the app has read the paste, or the restore timed out).
@MainActor
enum TryItWatch {
    /// Longest wait for a paste that never settles (the restore is skipped when a new dictation starts).
    static let cap: Duration = .seconds(3)
    /// After the restore finished, one more look: the field may update a moment after the app read the paste.
    static let afterSettled: Duration = .milliseconds(100)

    static func textArrived(contains: () -> Bool, settled: () -> Bool, step: Duration = .milliseconds(25),
                            sleep: (Duration) async -> Void = { try? await Task.sleep(for: $0) }) async -> Bool {
        var waited = Duration.zero
        var settledAt: Duration?
        while true {
            if contains() { return true }
            if settledAt == nil, settled() { settledAt = waited }
            if let settledAt, waited - settledAt >= afterSettled { return false }
            if waited >= cap { return false }
            await sleep(step)
            waited += step
        }
    }
}
