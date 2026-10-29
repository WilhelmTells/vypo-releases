import Foundation
import KeyboardShortcuts
import Observation

/// The key used to start dictation (§7.1).
enum DictationKey: String, Codable, CaseIterable, Sendable, Identifiable {
    /// `custom` is any shortcut recorded under `KeyboardShortcuts.Name.dictation`.
    case fn, rightOption, rightCommand, rightControl, custom

    var id: String { rawValue }

    /// The single keys, for places without a shortcut recorder (onboarding).
    static let singleKeys: [DictationKey] = [.fn, .rightOption, .rightCommand, .rightControl]

    /// "fn", "Right Option", …, "Custom shortcut"
    var name: String {
        switch self {
        case .fn: "fn"
        case .rightOption: String(localized: "Right Option")
        case .rightCommand: String(localized: "Right Command")
        case .rightControl: String(localized: "Right Control")
        case .custom: String(localized: "Custom shortcut")
        }
    }

    /// The key as it reads in a sentence: the name, or the recorded shortcut, e.g. "⌃⌥D".
    @MainActor var spoken: String {
        guard self == .custom else { return name }
        return KeyboardShortcuts.getShortcut(for: .dictation)?.description ?? name
    }

    /// Key cap glyphs.
    @MainActor var keyCaps: [String] {
        switch self {
        case .fn: ["fn"]
        case .rightOption: ["⌥"]
        case .rightCommand: ["⌘"]
        case .rightControl: ["⌃"]
        case .custom: KeyboardShortcuts.getShortcut(for: .dictation)?.keyCaps ?? []
        }
    }
}

/// The colour of the pill's voice bars (Settings → Appearance → Pill). `white` is the neutral ink: white on dark, black on light.
/// `orange` is vypo's vermilion; `custom` uses `pillCustomColor`.
enum PillColor: String, Codable, CaseIterable, Sendable {
    case white, orange, blue, purple, pink, green, custom
}

/// The Settings window (Settings → Appearance → Window): solid and following macOS, solid light,
/// solid dark, or translucent glass.
enum WindowStyle: String, Codable, CaseIterable, Sendable {
    case automatic, light, dark, glass
}

/// The pill's surface (Settings → Appearance → Pill). `automatic` follows the system appearance.
enum PillBackground: String, Codable, CaseIterable, Sendable {
    case automatic, dark, light, glass
}

enum CorrectionStrength: String, Codable, CaseIterable, Sendable {
    case careful, normal, strong

    var threshold: Double {
        switch self {
        case .careful: 0.92
        case .normal: 0.85
        case .strong: 0.78
        }
    }
}

enum HistoryRetention: String, Codable, CaseIterable, Sendable {
    case days7 = "7", days30 = "30", forever

    var days: Int? {
        switch self {
        case .days7: 7
        case .days30: 30
        case .forever: nil
        }
    }
}

/// UserDefaults keys (§17, §23.11).
enum DefaultsKey {
    static let onboardingCompleted = "onboardingCompleted"
    static let dictationEnabled = "dictationEnabled"
    static let dictationKey = "dictationKey"
    static let holdToTalk = "holdToTalk"
    static let doubleTapHandsFree = "doubleTapHandsFree"
    static let inputDeviceUID = "inputDeviceUID"
    /// vypo’s own start/stop sound (replaces the former on/off switch for the system Tink/Pop).
    static let recordingSound = "recordingSound"
    static let muteWhileRecording = "muteWhileRecording"
    static let pendingAudioRestore = "pendingAudioRestore"
    static let pasteAutomatically = "pasteAutomatically"
    static let restoreClipboard = "restoreClipboard"
    /// Set once the symbol words (slash, semicolon …) have become entries of the replacements list. The two
    /// switches before that (`spokenSymbols`, `spokenSymbolsAlone`) are read by that move once and then removed.
    static let symbolsAreReplacements = "symbolsAreReplacements"
    static let replacementVariantsSplit = "replacementVariantsSplit"
    static let correctionStrength = "correctionStrength"
    static let saveHistory = "saveHistory"
    static let historyRetention = "historyRetention"
    // §23.11
    static let smartSpacing = "smartSpacing"
    static let removeFillers = "removeFillers"
    static let spellingsEnabled = "spellingsEnabled"
    static let spellingsList = "spellings.list"
    static let fillerWordsEN = "fillerWords.en"
    static let fillerWordsDE = "fillerWords.de"
    static let spokenPunctuation = "spokenPunctuation"
    static let spokenSymbols = "spokenSymbols"
    static let spokenSymbolsAlone = "spokenSymbolsAlone"
    static let typographicQuotes = "typographicQuotes"
    static let preferBuiltInMic = "preferBuiltInMic"
    static let hideFromCapture = "hideFromCapture"
    static let pillColor = "pillColor"
    static let pillCustomColor = "pillCustomColor"
    static let windowStyle = "windowStyle"
    static let pillBackground = "pillBackground"
    static let collectStats = "collectStats"
    static let showLevel = "showLevel"
    static let languages = "languages"
    static let menuBarTintWhileDictating = "menuBarTintWhileDictating"
    static let showPill = "showPill"
    static let showInDock = "showInDock"

}

/// Typed, observable UserDefaults-backed settings.
@MainActor
@Observable
final class Preferences {
    @ObservationIgnored let defaults: UserDefaults

    init(defaults: UserDefaults = AppDefaults.standard, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.defaults = defaults
        defaults.register(defaults: [
            DefaultsKey.onboardingCompleted: false,
            DefaultsKey.dictationEnabled: true,
            DefaultsKey.dictationKey: DictationKey.fn.rawValue,
            DefaultsKey.holdToTalk: true,
            DefaultsKey.doubleTapHandsFree: true,
            DefaultsKey.recordingSound: RecordingSound.standard.rawValue,
            DefaultsKey.muteWhileRecording: true,
            DefaultsKey.pasteAutomatically: true,
            DefaultsKey.restoreClipboard: true,
            DefaultsKey.correctionStrength: CorrectionStrength.normal.rawValue,
            DefaultsKey.saveHistory: true,
            DefaultsKey.historyRetention: HistoryRetention.days30.rawValue,
            DefaultsKey.smartSpacing: true,
            DefaultsKey.removeFillers: true,
            DefaultsKey.spellingsEnabled: true,
            DefaultsKey.fillerWordsEN: FillerRemover.defaultWords(.en),
            DefaultsKey.fillerWordsDE: FillerRemover.defaultWords(.de),
            DefaultsKey.spokenPunctuation: true,
            DefaultsKey.typographicQuotes: true,
            DefaultsKey.preferBuiltInMic: true,
            DefaultsKey.hideFromCapture: true,
            DefaultsKey.collectStats: true,
            DefaultsKey.showLevel: true,
            DefaultsKey.menuBarTintWhileDictating: false,
            DefaultsKey.showPill: true,
            DefaultsKey.showInDock: false,
        ])

        onboardingCompleted = defaults.bool(forKey: DefaultsKey.onboardingCompleted)
        dictationEnabled = defaults.bool(forKey: DefaultsKey.dictationEnabled)
        dictationKey = DictationKey(rawValue: defaults.string(forKey: DefaultsKey.dictationKey) ?? "") ?? .fn
        holdToTalk = defaults.bool(forKey: DefaultsKey.holdToTalk)
        doubleTapHandsFree = defaults.bool(forKey: DefaultsKey.doubleTapHandsFree)
        inputDeviceUID = defaults.string(forKey: DefaultsKey.inputDeviceUID)
        recordingSound = RecordingSound(rawValue: defaults.string(forKey: DefaultsKey.recordingSound) ?? "") ?? .standard
        muteWhileRecording = defaults.bool(forKey: DefaultsKey.muteWhileRecording)
        pasteAutomatically = defaults.bool(forKey: DefaultsKey.pasteAutomatically)
        restoreClipboard = defaults.bool(forKey: DefaultsKey.restoreClipboard)
        correctionStrength = CorrectionStrength(rawValue: defaults.string(forKey: DefaultsKey.correctionStrength) ?? "") ?? .normal
        saveHistory = defaults.bool(forKey: DefaultsKey.saveHistory)
        historyRetention = HistoryRetention(rawValue: defaults.string(forKey: DefaultsKey.historyRetention) ?? "") ?? .days30
        smartSpacing = defaults.bool(forKey: DefaultsKey.smartSpacing)
        removeFillers = defaults.bool(forKey: DefaultsKey.removeFillers)
        spellingsEnabled = defaults.bool(forKey: DefaultsKey.spellingsEnabled)
        // Only a user's own edit is stored; nil means the built-in list (`Spellings.defaultList`).
        spellingsEdited = defaults.stringArray(forKey: DefaultsKey.spellingsList)
        fillerWordsEN = defaults.stringArray(forKey: DefaultsKey.fillerWordsEN) ?? FillerRemover.defaultWords(.en)
        fillerWordsDE = defaults.stringArray(forKey: DefaultsKey.fillerWordsDE) ?? FillerRemover.defaultWords(.de)
        spokenPunctuation = defaults.bool(forKey: DefaultsKey.spokenPunctuation)
        typographicQuotes = defaults.bool(forKey: DefaultsKey.typographicQuotes)
        preferBuiltInMic = defaults.bool(forKey: DefaultsKey.preferBuiltInMic)
        hideFromCapture = defaults.bool(forKey: DefaultsKey.hideFromCapture)
        // "accent" was the system accent colour, now vypo's own orange.
        let storedColor = defaults.string(forKey: DefaultsKey.pillColor)
        pillColor = storedColor == "accent" ? .orange : PillColor(rawValue: storedColor ?? "") ?? .white
        pillCustomColor = defaults.string(forKey: DefaultsKey.pillCustomColor) ?? Self.defaultCustomColor
        // Glass for everyone who hasn't chosen a pill background (0.3.0); a stored choice stays.
        pillBackground = PillBackground(rawValue: defaults.string(forKey: DefaultsKey.pillBackground) ?? "") ?? .glass
        windowStyle = WindowStyle(rawValue: defaults.string(forKey: DefaultsKey.windowStyle) ?? "") ?? .automatic
        collectStats = defaults.bool(forKey: DefaultsKey.collectStats)
        showLevel = defaults.bool(forKey: DefaultsKey.showLevel)
        menuBarTintWhileDictating = defaults.bool(forKey: DefaultsKey.menuBarTintWhileDictating)
        showPill = defaults.bool(forKey: DefaultsKey.showPill)
        showInDock = defaults.bool(forKey: DefaultsKey.showInDock)
        // Before the choice existed, vypo spoke English and German.
        let stored = (defaults.stringArray(forKey: DefaultsKey.languages) ?? []).compactMap(Lang.init(rawValue:))
        languages = !stored.isEmpty ? stored
            : defaults.bool(forKey: DefaultsKey.onboardingCompleted) ? [.en, .de] : Lang.firstRunSelection(preferred: preferredLanguages)
        // didSet doesn't run in init: store the starting choice, or a kept preselection would read as
        // English + German once onboarding is done.
        defaults.set(languages.map(\.rawValue), forKey: DefaultsKey.languages)
    }

    var onboardingCompleted: Bool { didSet { defaults.set(onboardingCompleted, forKey: DefaultsKey.onboardingCompleted) } }
    var dictationEnabled: Bool { didSet { defaults.set(dictationEnabled, forKey: DefaultsKey.dictationEnabled) } }
    var dictationKey: DictationKey { didSet { defaults.set(dictationKey.rawValue, forKey: DefaultsKey.dictationKey) } }
    var holdToTalk: Bool { didSet { defaults.set(holdToTalk, forKey: DefaultsKey.holdToTalk) } }
    var doubleTapHandsFree: Bool { didSet { defaults.set(doubleTapHandsFree, forKey: DefaultsKey.doubleTapHandsFree) } }
    var inputDeviceUID: String? { didSet { defaults.set(inputDeviceUID, forKey: DefaultsKey.inputDeviceUID) } }
    var recordingSound: RecordingSound { didSet { defaults.set(recordingSound.rawValue, forKey: DefaultsKey.recordingSound) } }
    var muteWhileRecording: Bool { didSet { defaults.set(muteWhileRecording, forKey: DefaultsKey.muteWhileRecording) } }
    var pasteAutomatically: Bool { didSet { defaults.set(pasteAutomatically, forKey: DefaultsKey.pasteAutomatically) } }
    var restoreClipboard: Bool { didSet { defaults.set(restoreClipboard, forKey: DefaultsKey.restoreClipboard) } }
    var correctionStrength: CorrectionStrength { didSet { defaults.set(correctionStrength.rawValue, forKey: DefaultsKey.correctionStrength) } }
    var saveHistory: Bool { didSet { defaults.set(saveHistory, forKey: DefaultsKey.saveHistory) } }
    var historyRetention: HistoryRetention { didSet { defaults.set(historyRetention.rawValue, forKey: DefaultsKey.historyRetention) } }
    var smartSpacing: Bool { didSet { defaults.set(smartSpacing, forKey: DefaultsKey.smartSpacing) } }
    var removeFillers: Bool { didSet { defaults.set(removeFillers, forKey: DefaultsKey.removeFillers) } }
    var spellingsEnabled: Bool { didSet { defaults.set(spellingsEnabled, forKey: DefaultsKey.spellingsEnabled) } }
    /// The user's edited spellings; nil while the list is the built-in one, which is never stored.
    private(set) var spellingsEdited: [String]?
    var spellings: [String] { spellingsEdited ?? Spellings.defaultList }

    /// Saves an edited list. The built-in list (also after “Reset to defaults”) is not stored, so the app's own list can
    /// grow in an update; a list that is only different is stored as it is.
    func setSpellings(_ words: [String]) {
        if words == Spellings.defaultList {
            spellingsEdited = nil
            defaults.removeObject(forKey: DefaultsKey.spellingsList)
        } else {
            spellingsEdited = words
            defaults.set(words, forKey: DefaultsKey.spellingsList)
        }
    }
    var fillerWordsEN: [String] { didSet { defaults.set(fillerWordsEN, forKey: DefaultsKey.fillerWordsEN) } }
    var fillerWordsDE: [String] { didSet { defaults.set(fillerWordsDE, forKey: DefaultsKey.fillerWordsDE) } }
    var spokenPunctuation: Bool { didSet { defaults.set(spokenPunctuation, forKey: DefaultsKey.spokenPunctuation) } }
    var typographicQuotes: Bool { didSet { defaults.set(typographicQuotes, forKey: DefaultsKey.typographicQuotes) } }
    var preferBuiltInMic: Bool { didSet { defaults.set(preferBuiltInMic, forKey: DefaultsKey.preferBuiltInMic) } }
    var hideFromCapture: Bool { didSet { defaults.set(hideFromCapture, forKey: DefaultsKey.hideFromCapture) } }
    var pillColor: PillColor { didSet { defaults.set(pillColor.rawValue, forKey: DefaultsKey.pillColor) } }
    /// "#RRGGBB", picked in the colour panel.
    var pillCustomColor: String { didSet { defaults.set(pillCustomColor, forKey: DefaultsKey.pillCustomColor) } }
    static let defaultCustomColor = "#D4421F"
    var pillBackground: PillBackground { didSet { defaults.set(pillBackground.rawValue, forKey: DefaultsKey.pillBackground) } }
    var windowStyle: WindowStyle { didSet { defaults.set(windowStyle.rawValue, forKey: DefaultsKey.windowStyle) } }
    var collectStats: Bool { didSet { defaults.set(collectStats, forKey: DefaultsKey.collectStats) } }
    /// Settings → Stats: the level card; hidden too while stats are off.
    var showLevel: Bool { didSet { defaults.set(showLevel, forKey: DefaultsKey.showLevel) } }
    /// Settings → Appearance → Menu bar. The mark is animated either way.
    var menuBarTintWhileDictating: Bool { didSet { defaults.set(menuBarTintWhileDictating, forKey: DefaultsKey.menuBarTintWhileDictating) } }
    /// Settings → Appearance → Pill. Off: only states that need you show the pill (`PillVisibility`).
    var showPill: Bool { didSet { defaults.set(showPill, forKey: DefaultsKey.showPill) } }
    /// Settings → Appearance → Dock (`AppPresence`).
    var showInDock: Bool { didSet { defaults.set(showInDock, forKey: DefaultsKey.showInDock) } }

    /// The languages the user dictates in; never empty.
    var languages: [Lang] { didSet { defaults.set(languages.map(\.rawValue), forKey: DefaultsKey.languages) } }

    /// Adds or removes a language; the last one stays.
    func setChosen(_ lang: Lang, _ chosen: Bool) {
        if chosen {
            if !languages.contains(lang) { languages.append(lang) }
        } else if languages != [lang] {
            languages.removeAll { $0 == lang }
        }
    }

    func fillerWords(for lang: Lang) -> [String] {
        switch lang {
        case .en: fillerWordsEN
        case .de: fillerWordsDE
        default: []
        }
    }

    func setFillerWords(_ words: [String], for lang: Lang) {
        switch lang {
        case .en: fillerWordsEN = words
        case .de: fillerWordsDE = words
        default: break
        }
    }
}
