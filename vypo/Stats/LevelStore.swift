import Foundation
import Observation

/// The ten ranks on the Stats pane's level card. Pure fun: a rank unlocks nothing.
enum Rank: Int, CaseIterable, Sendable {
    case errandBoy = 1, messenger, page, scribe, herald, courtCoachman, chronicler, steward, chancellor, poetLaureate

    /// Words from which each rank holds, in order.
    static let thresholds = [0, 2_500, 10_000, 25_000, 50_000, 100_000, 200_000, 400_000, 700_000, 1_000_000]

    static var highest: Rank { allCases.last! }

    /// The rank for a word count.
    init(words: Int) {
        let level = Self.thresholds.lastIndex { words >= $0 } ?? 0
        self = Rank(rawValue: level + 1) ?? .errandBoy
    }

    var level: Int { rawValue }
    var threshold: Int { Self.thresholds[rawValue - 1] }
    var next: Rank? { Rank(rawValue: rawValue + 1) }
    var previous: Rank? { Rank(rawValue: rawValue - 1) }

    /// How far into this rank `words` are, 0…1; always 1 for the highest.
    func progress(words: Int) -> Double {
        guard let next else { return 1 }
        return min(1, max(0, Double(words - threshold) / Double(next.threshold - threshold)))
    }

    var name: String {
        switch self {
        case .errandBoy: String(localized: "Errand boy")
        case .messenger: String(localized: "Messenger")
        case .page: String(localized: "Page", comment: "Rank: a young servant at court")
        case .scribe: String(localized: "Scribe")
        case .herald: String(localized: "Herald")
        case .courtCoachman: String(localized: "Court coachman")
        case .chronicler: String(localized: "Chronicler")
        case .steward: String(localized: "Steward")
        case .chancellor: String(localized: "Chancellor")
        case .poetLaureate: String(localized: "Poet Laureate")
        }
    }

    /// The level number the six ranks of the first version had (before 2026-10-25), for the one-time move of `lastSeenLevel`.
    static func fromSixRankNumbering(_ level: Int) -> Rank {
        let old: [Rank] = [.errandBoy, .messenger, .page, .herald, .courtCoachman, .chancellor]
        return old.indices.contains(level - 1) ? old[level - 1] : .errandBoy
    }
}

/// `level.json`: the words that count towards the level. Unlike the stats this only grows:
/// undo doesn't subtract, so the level never sinks.
@MainActor
@Observable
final class LevelStore {
    private(set) var xpWords: Int
    /// The level and words the Stats pane last showed; a higher level plays the fanfare there.
    private(set) var lastSeenLevel: Int
    private(set) var lastSeenWords: Int
    @ObservationIgnored private let store: Store
    private static let file = "level.json"

    private struct State: Codable {
        var xpWords: Int
        var lastSeenLevel: Int
        var lastSeenWords: Int
        /// 2 = ten ranks. Missing in files of the six-rank version, whose `lastSeenLevel` is moved once.
        var ranks: Int?
    }

    static let rankVersion = 2

    /// The one-time move from six ranks to ten: `lastSeenLevel` was a number in the old list. The same rank in the
    /// new list, but never more than one level below the current one, so at most one fanfare plays (for the current
    /// level), not a chain; and never above it.
    static func movedLastSeenLevel(old: Int, words: Int) -> Int {
        let current = Rank(words: words).level
        let same = Rank.fromSixRankNumbering(old).level
        return min(current, max(max(1, current - 1), same))
    }

    /// Without `level.json`, all words counted so far (`seedWords`) start the count, already seen.
    init(store: Store = .shared, seedWords: @autoclosure () -> Int) {
        self.store = store
        if let state = store.load(State.self, from: Self.file) {
            xpWords = state.xpWords
            lastSeenWords = state.lastSeenWords
            if state.ranks == nil {
                lastSeenLevel = Self.movedLastSeenLevel(old: state.lastSeenLevel, words: state.xpWords)
                save()
            } else {
                lastSeenLevel = state.lastSeenLevel
            }
        } else {
            let words = max(0, seedWords())
            xpWords = words
            lastSeenLevel = Rank(words: words).level
            lastSeenWords = words
            save()
        }
    }

    var rank: Rank { Rank(words: xpWords) }
    var lastSeenRank: Rank { Rank(rawValue: lastSeenLevel) ?? .errandBoy }

    func add(words: Int) {
        guard words > 0 else { return }
        xpWords += words
        save()
    }

    /// The Stats pane showed the current level.
    func markSeen() {
        guard lastSeenLevel != rank.level || lastSeenWords != xpWords else { return }
        lastSeenLevel = rank.level
        lastSeenWords = xpWords
        save()
    }

    /// With “Reset stats”: back to the first rank, with nothing to celebrate.
    func reset() {
        xpWords = 0
        lastSeenLevel = Rank.errandBoy.level
        lastSeenWords = 0
        save()
    }

    private func save() {
        store.save(State(xpWords: xpWords, lastSeenLevel: lastSeenLevel, lastSeenWords: lastSeenWords, ranks: Self.rankVersion), to: Self.file)
    }
}

/// Debug → Mascot: what the level card shows instead of the real level. Only in memory, never saved;
/// the level, its words and `lastSeenLevel` stay untouched.
@MainActor
@Observable
final class LevelPreview {
    var rank: Rank?
    /// 0…1 within the rank.
    var progress: Double?
    /// “Play level-up”: the card plays it once it's on screen.
    var playRequested = false

    var isActive: Bool { rank != nil || progress != nil }

    func reset() {
        rank = nil
        progress = nil
        playRequested = false
    }
}
