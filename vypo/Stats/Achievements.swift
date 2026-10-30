import Foundation
import Observation

// Achievements: local fun, like the level. They unlock nothing and never sink. A reached achievement (or a new tier of
// one) is *ready* until the user stamps it. The card on the Stats pane comes later; this is the data it will read.

enum AchievementKind: String, Sendable {
    case discover, milestone, habit
    /// Hidden until reached; the card only tells how many are left.
    case curious
}

enum AchievementID: String, CaseIterable, Codable, Sendable {
    case firstWords, wordKeeper, bookworm, swapArtist, rightTool, handsFree, secondThoughts, polyglot
    case tales, timeBack, longBreath, wordCollector, bookshelf
    case regular
    case nightOwl, earlyBird, threeTongues, chatterbox, sayMyName, wellTravelled
}

/// One achievement: its kind and the thresholds of its tiers, in the unit of `Achievements.value`.
struct AchievementDefinition: Sendable {
    let id: AchievementID
    let kind: AchievementKind
    let thresholds: [Double]
    /// The value must be above the threshold, not just reach it (“longer than 1 min”).
    var above = false

    var tiers: Int { thresholds.count }

    /// How many tiers `value` has reached.
    func level(for value: Double) -> Int {
        thresholds.filter { above ? value > $0 : value >= $0 }.count
    }
}

/// Things that are either done or not; stored by name.
enum AchievementFlag: String, Codable, CaseIterable, Sendable {
    case documentImport, ownReplacement, promptOrWritingApp, handsFree, undo, nightOwl, earlyBird, threeLanguagesInADay, sayMyName
}

enum Achievements {
    private static func words(_ work: String) -> Double { Double(Work.all.first { $0.id == work }?.words ?? 0) }

    static let definitions: [AchievementDefinition] = [
        AchievementDefinition(id: .firstWords, kind: .discover, thresholds: [1]),
        AchievementDefinition(id: .wordKeeper, kind: .discover, thresholds: [1]),
        AchievementDefinition(id: .bookworm, kind: .discover, thresholds: [1]),
        AchievementDefinition(id: .swapArtist, kind: .discover, thresholds: [1]),
        AchievementDefinition(id: .rightTool, kind: .discover, thresholds: [1]),
        AchievementDefinition(id: .handsFree, kind: .discover, thresholds: [1]),
        AchievementDefinition(id: .secondThoughts, kind: .discover, thresholds: [1]),
        AchievementDefinition(id: .polyglot, kind: .discover, thresholds: [2]),
        AchievementDefinition(id: .tales, kind: .milestone, thresholds: [10, 100, 1_000, 10_000]),
        // Minutes saved (as on the Stats pane, typing at 40 WPM): 1, 10, 24, 50, 100 hours.
        AchievementDefinition(id: .timeBack, kind: .milestone, thresholds: [60, 600, 1_440, 3_000, 6_000]),
        // Seconds of one dictation: longer than 1, 3, 5 minutes.
        AchievementDefinition(id: .longBreath, kind: .milestone, thresholds: [60, 180, 300], above: true),
        AchievementDefinition(id: .wordCollector, kind: .milestone, thresholds: [10, 50, 100]),
        // The Little Prince, The Hobbit, the Bible (`StatsComparison`).
        AchievementDefinition(id: .bookshelf, kind: .milestone, thresholds: [words("littlePrince"), words("hobbit"), words("bible")]),
        // Regular, Familiar Voice, Old Friend.
        AchievementDefinition(id: .regular, kind: .habit, thresholds: [7, 30, 100]),
        AchievementDefinition(id: .nightOwl, kind: .curious, thresholds: [1]),
        AchievementDefinition(id: .earlyBird, kind: .curious, thresholds: [1]),
        AchievementDefinition(id: .threeTongues, kind: .curious, thresholds: [1]),
        AchievementDefinition(id: .chatterbox, kind: .curious, thresholds: [50, 100, 200]),
        AchievementDefinition(id: .sayMyName, kind: .curious, thresholds: [1]),
        AchievementDefinition(id: .wellTravelled, kind: .curious, thresholds: [3, 5, 10]),
    ]

    static func definition(_ id: AchievementID) -> AchievementDefinition { definitions.first { $0.id == id }! }

    /// Night Owl 0:00–3:59, Early Bird 4:00–5:59, local time.
    static let nightOwlHours = 0..<4
    static let earlyBirdHours = 4..<6
    /// A dictation counts for its language from this many words: short ones fall back to the last language.
    static let wordsForLanguage = 4

    /// What an achievement is measured by, from the stored state.
    static func value(_ id: AchievementID, _ s: AchievementState) -> Double {
        func flag(_ f: AchievementFlag) -> Double { s.flags.contains(f) ? 1 : 0 }
        switch id {
        case .firstWords, .tales: return Double(s.dictations)
        case .wordKeeper, .wordCollector: return Double(s.maxGlossaryEntries)
        case .bookworm: return flag(.documentImport)
        case .swapArtist: return flag(.ownReplacement)
        case .rightTool: return flag(.promptOrWritingApp)
        case .handsFree: return flag(.handsFree)
        case .secondThoughts: return flag(.undo)
        case .polyglot: return Double(s.languages.count)
        case .timeBack: return s.maxSavedMinutes
        case .longBreath: return s.maxRecordingSeconds
        case .bookshelf: return Double(s.maxWords)
        case .regular: return Double(s.days.count)
        case .nightOwl: return flag(.nightOwl)
        case .earlyBird: return flag(.earlyBird)
        case .threeTongues: return flag(.threeLanguagesInADay)
        case .chatterbox: return Double(s.maxDayDictations)
        case .sayMyName: return flag(.sayMyName)
        case .wellTravelled: return Double(s.apps.count)
        }
    }

    /// The local calendar day as “yyyy-MM-dd”: a day stays the day the Mac's clock showed, whatever the time zone later.
    static func day(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Whether the final text has the word “vypo” (also “vypo-App”). Only the answer is kept.
    static func mentionsVypo(_ text: String) -> Bool {
        text.range(of: "(?<![\\p{L}\\p{N}])vypo(?![\\p{L}\\p{N}])", options: [.regularExpression, .caseInsensitive]) != nil
    }
}

/// One counted dictation, as the achievements see it: no text, only what follows from it.
struct DictationFacts: Sendable {
    var date: Date
    var words: Int
    var seconds: Double
    var language: Lang
    var bundleID: String?
    var handsFree = false
    var mentionsVypo = false
}

/// `achievements.json`. Counters and sets only grow; `levels` never sink; `stamps` holds the day each tier was stamped.
struct AchievementState: Codable, Equatable, Sendable {
    static let currentVersion = 1

    struct Today: Codable, Equatable, Sendable {
        var day: String
        var dictations = 0
        var languages: Set<String> = []
    }

    var version = Self.currentVersion
    /// False until the first fill from the existing data; stays false while “Collect stats” is off.
    var seeded = false
    /// The tier reached per achievement; 0 or missing = locked.
    var levels: [AchievementID: Int] = [:]
    /// The day (“yyyy-MM-dd”) each tier was stamped, in order: the count is the stamped tier.
    var stamps: [AchievementID: [String]] = [:]
    var dictations = 0
    var maxRecordingSeconds: Double = 0
    var maxSavedMinutes: Double = 0
    var maxWords = 0
    var maxGlossaryEntries = 0
    var maxDayDictations = 0
    var days: Set<String> = []
    /// Language codes of dictations with at least `Achievements.wordsForLanguage` words.
    var languages: Set<String> = []
    /// Bundle IDs, as in `stats.json`.
    var apps: Set<String> = []
    var today: Today?
    var flags: Set<AchievementFlag> = []

    init() {}

    private enum CodingKeys: String, CodingKey {
        case version, seeded, levels, stamps, dictations, maxRecordingSeconds, maxSavedMinutes, maxWords, maxGlossaryEntries,
             maxDayDictations, days, languages, apps, today, flags
    }

    /// Every field is optional: a missing one takes its default (an older or newer file). Unknown achievement ids and
    /// flags are dropped.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        seeded = try c.decodeIfPresent(Bool.self, forKey: .seeded) ?? false
        let rawLevels = try c.decodeIfPresent([String: Int].self, forKey: .levels) ?? [:]
        levels = Dictionary(uniqueKeysWithValues: rawLevels.compactMap { k, v in AchievementID(rawValue: k).map { ($0, v) } })
        let rawStamps = try c.decodeIfPresent([String: [String]].self, forKey: .stamps) ?? [:]
        stamps = Dictionary(uniqueKeysWithValues: rawStamps.compactMap { k, v in AchievementID(rawValue: k).map { ($0, v) } })
        dictations = try c.decodeIfPresent(Int.self, forKey: .dictations) ?? 0
        maxRecordingSeconds = try c.decodeIfPresent(Double.self, forKey: .maxRecordingSeconds) ?? 0
        maxSavedMinutes = try c.decodeIfPresent(Double.self, forKey: .maxSavedMinutes) ?? 0
        maxWords = try c.decodeIfPresent(Int.self, forKey: .maxWords) ?? 0
        maxGlossaryEntries = try c.decodeIfPresent(Int.self, forKey: .maxGlossaryEntries) ?? 0
        maxDayDictations = try c.decodeIfPresent(Int.self, forKey: .maxDayDictations) ?? 0
        days = try c.decodeIfPresent(Set<String>.self, forKey: .days) ?? []
        languages = try c.decodeIfPresent(Set<String>.self, forKey: .languages) ?? []
        apps = try c.decodeIfPresent(Set<String>.self, forKey: .apps) ?? []
        today = try c.decodeIfPresent(Today.self, forKey: .today)
        flags = Set((try c.decodeIfPresent([String].self, forKey: .flags) ?? []).compactMap(AchievementFlag.init(rawValue:)))
    }

    /// Sorted, so the file only changes when the content does.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(seeded, forKey: .seeded)
        try c.encode(Dictionary(uniqueKeysWithValues: levels.filter { $0.value > 0 }.map { ($0.key.rawValue, $0.value) }), forKey: .levels)
        try c.encode(Dictionary(uniqueKeysWithValues: stamps.filter { !$0.value.isEmpty }.map { ($0.key.rawValue, $0.value) }), forKey: .stamps)
        try c.encode(dictations, forKey: .dictations)
        try c.encode(maxRecordingSeconds, forKey: .maxRecordingSeconds)
        try c.encode(maxSavedMinutes, forKey: .maxSavedMinutes)
        try c.encode(maxWords, forKey: .maxWords)
        try c.encode(maxGlossaryEntries, forKey: .maxGlossaryEntries)
        try c.encode(maxDayDictations, forKey: .maxDayDictations)
        try c.encode(days.sorted(), forKey: .days)
        try c.encode(languages.sorted(), forKey: .languages)
        try c.encode(apps.sorted(), forKey: .apps)
        try c.encodeIfPresent(today, forKey: .today)
        try c.encode(flags.map(\.rawValue).sorted(), forKey: .flags)
    }

    /// Takes everything `other` has that is more: the larger counters, the union of the sets.
    mutating func merge(_ other: AchievementState) {
        dictations = max(dictations, other.dictations)
        maxRecordingSeconds = max(maxRecordingSeconds, other.maxRecordingSeconds)
        maxSavedMinutes = max(maxSavedMinutes, other.maxSavedMinutes)
        maxWords = max(maxWords, other.maxWords)
        maxGlossaryEntries = max(maxGlossaryEntries, other.maxGlossaryEntries)
        maxDayDictations = max(maxDayDictations, other.maxDayDictations)
        days.formUnion(other.days)
        languages.formUnion(other.languages)
        apps.formUnion(other.apps)
        flags.formUnion(other.flags)
        if today == nil || (other.today.map { $0.day > today!.day } ?? false) { today = other.today ?? today }
    }
}

extension AchievementState.Today {
    private enum CodingKeys: String, CodingKey { case day, dictations, languages }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(String.self, forKey: .day)
        dictations = try c.decodeIfPresent(Int.self, forKey: .dictations) ?? 0
        languages = try c.decodeIfPresent(Set<String>.self, forKey: .languages) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(day, forKey: .day)
        try c.encode(dictations, forKey: .dictations)
        try c.encode(languages.sorted(), forKey: .languages)
    }
}

/// What the card shows for one achievement.
struct AchievementStatus: Equatable, Sendable {
    let id: AchievementID
    let kind: AchievementKind
    let tiers: Int
    /// Reached tier; 0 = locked.
    let level: Int
    let stampedLevel: Int
    /// The day the last tier was stamped.
    let stampedOn: String?
    let value: Double
    /// The threshold of the next tier; nil once all are reached.
    let next: Double?

    var isLocked: Bool { level == 0 }
    /// Reached and not yet stamped (a first tier, or a new one above the stamped).
    var isReady: Bool { level > stampedLevel }
    var isStamped: Bool { stampedLevel > 0 }
    /// Curious achievements stay hidden until reached.
    var isHidden: Bool { kind == .curious && level == 0 }
    /// Towards the next tier, 0…1; 1 once all are reached.
    var progress: Double { next.map { $0 > 0 ? min(1, value / $0) : 1 } ?? 1 }
}

/// What the first launch with achievements reads from the existing files, once.
@MainActor
enum AchievementSeed {
    /// - Tales starts with the history's entries (a lower bound: history keeps 30 days by default and can be off).
    /// - Days, languages and apps from `stats.json` (a language from a day with at least four of its words).
    /// - Night Owl, Early Bird, Second Thoughts, Say My Name and the busiest day from the history; its text is only
    ///   looked at, nothing of it is kept.
    /// - Swap Artist: an entry that is no default's version (legacy) or any entry (new layout). Right Tool: an app on
    ///   Prompt or Writing (vypo's own former profiles are gone by then).
    static func state(stats: [StatsDay], xpWords: Int, glossaryCount: Int, replacements: [Replacement], layout: WordsLayout,
                      profiles: [AppProfile], history: [HistoryItem], calendar: Calendar, now: Date = Date()) -> AchievementState {
        var s = AchievementState()
        let words = max(xpWords, stats.reduce(0) { $0 + $1.words })
        s.dictations = max(history.count, words > 0 ? 1 : 0)
        s.maxWords = words
        s.maxSavedMinutes = StatsMath.minutesSaved(words: stats.reduce(0) { $0 + $1.words },
                                                   seconds: stats.reduce(0) { $0 + $1.recordingSeconds })
        s.maxGlossaryEntries = glossaryCount
        for day in stats where day.words > 0 {
            s.days.insert(Achievements.day(day.date, calendar: calendar))
            let spoken = day.wordsByLanguage.filter { $0.value >= Achievements.wordsForLanguage }.map(\.key)
            s.languages.formUnion(spoken)
            if spoken.count >= 3 { s.flags.insert(.threeLanguagesInADay) }
        }
        for day in stats { s.apps.formUnion((day.apps ?? [:]).keys) }

        var perDay: [String: Int] = [:]
        for item in history {
            let day = Achievements.day(item.date, calendar: calendar)
            perDay[day, default: 0] += 1
            s.days.insert(day)
            let hour = calendar.component(.hour, from: item.date)
            if Achievements.nightOwlHours.contains(hour) { s.flags.insert(.nightOwl) }
            if Achievements.earlyBirdHours.contains(hour) { s.flags.insert(.earlyBird) }
            if item.undone { s.flags.insert(.undo) }
            if Achievements.mentionsVypo(item.text) { s.flags.insert(.sayMyName) }
        }
        s.maxDayDictations = perDay.values.max() ?? 0
        let today = Achievements.day(now, calendar: calendar)
        if let n = perDay[today] {
            let langs = history.filter { Achievements.day($0.date, calendar: calendar) == today
                && $0.text.split(whereSeparator: \.isWhitespace).count >= Achievements.wordsForLanguage }.map(\.language.rawValue)
            s.today = AchievementState.Today(day: today, dictations: n, languages: Set(langs))
        }
        s.merge(fromFiles(glossaryCount: glossaryCount, replacements: replacements, layout: layout, profiles: profiles))
        return s
    }

    /// Only what the files of glossary, replacements and apps tell: also read when “Collect stats” is switched on again.
    static func fromFiles(glossaryCount: Int, replacements: [Replacement], layout: WordsLayout, profiles: [AppProfile]) -> AchievementState {
        var s = AchievementState()
        s.maxGlossaryEntries = glossaryCount
        let own = replacements.contains { r in
            layout == .spokenCharacters || !Replacements.defaults.contains { Replacements.isVersion(r, of: $0) }
        }
        if own { s.flags.insert(.ownReplacement) }
        // `AppProfileStore` removed the profiles vypo itself used to add before this runs: what is left on Prompt or
        // Writing, the user set, even when it equals one of them (re-added later).
        if profiles.contains(where: { [.prompt, .writing].contains($0.mode) }) {
            s.flags.insert(.promptOrWritingApp)
        }
        return s
    }
}

/// Reads and writes `achievements.json` (next to `level.json`). Everything reached is ready until stamped.
@MainActor
@Observable
final class AchievementStore {
    nonisolated static let file = "achievements.json"

    private(set) var state: AchievementState
    @ObservationIgnored private let store: Store
    @ObservationIgnored private let calendar: Calendar

    /// Without a file, the first launch fills it once from `seed` (all ready, nothing stamped). A file that can't be read
    /// is kept under another name and the state is filled again. While `collecting` is off nothing is filled or saved.
    init(store: Store = .shared, calendar: Calendar = .current, collecting: Bool, seed: () -> AchievementState) {
        self.store = store
        self.calendar = calendar
        let url = store.url(Self.file)
        if let data = try? Data(contentsOf: url) {
            if let loaded = try? Store.decoder.decode(AchievementState.self, from: data) {
                state = loaded
            } else {
                let kept = store.url("achievements-unreadable-\(Achievements.day(Date(), calendar: calendar))-\(UUID().uuidString.prefix(8)).json")
                try? FileManager.default.moveItem(at: url, to: kept)
                Log.store.error("achievements.json could not be read; kept as \(kept.lastPathComponent, privacy: .public), filled again from the data")
                state = AchievementState()
            }
        } else {
            state = AchievementState()
        }
        if !state.seeded && collecting { fill(seed()) }
    }

    private func fill(_ seeded: AchievementState) {
        state.merge(seeded)
        state.seeded = true
        update()
    }

    // MARK: Reading, for the card

    func status(_ id: AchievementID) -> AchievementStatus {
        let d = Achievements.definition(id)
        let level = state.levels[id] ?? 0
        let stamps = state.stamps[id] ?? []
        return AchievementStatus(id: id, kind: d.kind, tiers: d.tiers, level: level, stampedLevel: stamps.count,
                                 stampedOn: stamps.last, value: Achievements.value(id, state),
                                 next: level < d.tiers ? d.thresholds[level] : nil)
    }

    var all: [AchievementStatus] { AchievementID.allCases.map(status) }
    /// Achievements with at least one stamped tier, of `AchievementID.allCases.count`.
    var stampedCount: Int { all.filter(\.isStamped).count }
    var readyCount: Int { all.filter(\.isReady).count }
    /// Curious achievements not reached yet (“4 secrets left”).
    var hiddenCuriousLeft: Int { all.filter(\.isHidden).count }

    // MARK: Stamping

    /// Stamps every reached tier of `id` that isn't stamped yet, with today's date. False if nothing was ready.
    @discardableResult
    func stamp(_ id: AchievementID, now: Date = Date()) -> Bool {
        let level = state.levels[id] ?? 0
        var stamps = state.stamps[id] ?? []
        guard level > stamps.count else { return false }
        let day = Achievements.day(now, calendar: calendar)
        while stamps.count < level { stamps.append(day) }
        state.stamps[id] = stamps
        save()
        return true
    }

    // MARK: Events

    /// A counted dictation (also when only copied). `savedMinutes` and `words` are the totals after it (Stats and level).
    func dictated(_ f: DictationFacts, savedMinutes: Double, words: Int) {
        let day = Achievements.day(f.date, calendar: calendar)
        state.dictations += 1
        state.days.insert(day)
        state.maxRecordingSeconds = max(state.maxRecordingSeconds, f.seconds)
        state.maxSavedMinutes = max(state.maxSavedMinutes, savedMinutes)
        state.maxWords = max(state.maxWords, words)
        if let app = f.bundleID { state.apps.insert(app) }
        var today = state.today?.day == day ? state.today! : AchievementState.Today(day: day)
        today.dictations += 1
        if f.words >= Achievements.wordsForLanguage {
            state.languages.insert(f.language.rawValue)
            today.languages.insert(f.language.rawValue)
        }
        state.today = today
        state.maxDayDictations = max(state.maxDayDictations, today.dictations)
        if today.languages.count >= 3 { state.flags.insert(.threeLanguagesInADay) }
        let hour = calendar.component(.hour, from: f.date)
        if Achievements.nightOwlHours.contains(hour) { state.flags.insert(.nightOwl) }
        if Achievements.earlyBirdHours.contains(hour) { state.flags.insert(.earlyBird) }
        if f.handsFree { state.flags.insert(.handsFree) }
        if f.mentionsVypo { state.flags.insert(.sayMyName) }
        update()
    }

    func reached(_ flag: AchievementFlag) {
        guard !state.flags.contains(flag) else { return }
        state.flags.insert(flag)
        update()
    }

    func glossaryCount(_ n: Int) {
        guard n > state.maxGlossaryEntries else { return }
        state.maxGlossaryEntries = n
        update()
    }

    /// “Collect stats” is on again: fill once if never filled, otherwise take what the files tell.
    func collectingAgain(seed: () -> AchievementState, files: () -> AchievementState) {
        if !state.seeded { fill(seed()) } else { state.merge(files()); update() }
    }

    #if DEBUG
    /// Debug: the next tier of `id`, without the data for it.
    func debugReach(_ id: AchievementID) {
        let d = Achievements.definition(id)
        state.levels[id] = min(d.tiers, (state.levels[id] ?? 0) + 1)
        save()
    }

    /// Debug: forgets every stamp, so all reached tiers are ready again (to play the press once more).
    func debugClearStamps() {
        state.stamps = [:]
        save()
    }
    #endif

    /// Raises the levels to what the state now reaches; they never sink.
    private func update() {
        for d in Achievements.definitions {
            let reached = d.level(for: Achievements.value(d.id, state))
            if reached > (state.levels[d.id] ?? 0) { state.levels[d.id] = reached }
        }
        save()
    }

    private func save() {
        guard state.seeded else { return }
        store.save(state, to: Self.file)
    }
}
