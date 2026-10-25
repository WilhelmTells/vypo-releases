import Foundation
import Observation

/// One day of dictation (§23.12).
struct StatsDay: Codable, Equatable, Identifiable, Sendable {
    /// Start of the day.
    var date: Date
    var words: Int
    var recordingSeconds: Double
    /// Words per language code. Before the language choice there were only English and German
    /// (`wordsEN`, `wordsDE`); those are read once and written back in this form.
    var wordsByLanguage: [String: Int] = [:]
    /// Words per app bundle ID; counted since the Stats redesign, so older days have none.
    var apps: [String: Int]?

    var id: Date { date }

    init(date: Date, words: Int = 0, recordingSeconds: Double = 0) {
        self.date = date
        self.words = words
        self.recordingSeconds = recordingSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case date, words, recordingSeconds, wordsByLanguage, apps, wordsEN, wordsDE
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(Date.self, forKey: .date)
        words = try c.decode(Int.self, forKey: .words)
        recordingSeconds = try c.decode(Double.self, forKey: .recordingSeconds)
        apps = try c.decodeIfPresent([String: Int].self, forKey: .apps)
        if let byLanguage = try c.decodeIfPresent([String: Int].self, forKey: .wordsByLanguage) {
            wordsByLanguage = byLanguage
        } else {
            let legacy = ["en": try c.decodeIfPresent(Int.self, forKey: .wordsEN) ?? 0,
                          "de": try c.decodeIfPresent(Int.self, forKey: .wordsDE) ?? 0]
            wordsByLanguage = legacy.filter { $0.value > 0 }
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(date, forKey: .date)
        try c.encode(words, forKey: .words)
        try c.encode(recordingSeconds, forKey: .recordingSeconds)
        try c.encode(wordsByLanguage, forKey: .wordsByLanguage)
        try c.encodeIfPresent(apps, forKey: .apps)
    }
}

/// One language's part of all words; `lang` nil is “Other”.
struct LanguageShare: Equatable {
    let lang: Lang?
    let words: Int
    let percent: Int
}

/// `stats.json`, kept independently of history.
@MainActor
@Observable
final class StatsStore {
    private(set) var days: [StatsDay]
    @ObservationIgnored private let store: Store
    @ObservationIgnored private let calendar = Calendar.current
    private static let file = "stats.json"

    init(store: Store = .shared) {
        self.store = store
        days = store.load([StatsDay].self, from: Self.file) ?? []
    }

    /// Adds a dictation; a negative sign subtracts an undone one.
    func record(words: Int, seconds: Double, language: Lang, app: String? = nil, at date: Date = Date(), sign: Int = 1) {
        let day = calendar.startOfDay(for: date)
        var entry = days.first { $0.date == day } ?? StatsDay(date: day)
        entry.words = max(0, entry.words + sign * words)
        entry.recordingSeconds = max(0, entry.recordingSeconds + Double(sign) * seconds)
        let count = max(0, (entry.wordsByLanguage[language.rawValue] ?? 0) + sign * words)
        entry.wordsByLanguage[language.rawValue] = count > 0 ? count : nil
        if let app {
            var apps = entry.apps ?? [:]
            apps[app] = max(0, (apps[app] ?? 0) + sign * words)
            entry.apps = apps
        }
        days.removeAll { $0.date == day }
        days.append(entry)
        days.sort { $0.date < $1.date }
        save()
    }

    func reset() {
        days = []
        save()
    }

    private func save() { store.save(days, to: Self.file) }

    // MARK: Summaries

    func words(since start: Date) -> Int { days.filter { $0.date >= start }.reduce(0) { $0 + $1.words } }

    var today: Int { words(since: calendar.startOfDay(for: Date())) }

    var allTime: Int { days.reduce(0) { $0 + $1.words } }
    var allSeconds: Double { days.reduce(0) { $0 + $1.recordingSeconds } }

    /// Words per day for the last 14 days, oldest first.
    func lastDays(_ n: Int = 14, now: Date = Date()) -> [(date: Date, words: Int)] {
        let today = calendar.startOfDay(for: now)
        return (0..<n).reversed().compactMap { offset in
            guard let d = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (d, days.first { $0.date == d }?.words ?? 0)
        }
    }

    /// Words per app, most used first.
    var apps: [(app: String, words: Int)] {
        var total: [String: Int] = [:]
        for day in days { for (app, n) in day.apps ?? [:] { total[app, default: 0] += n } }
        return total.filter { $0.value > 0 }.map { ($0.key, $0.value) }.sorted { $0.words > $1.words }
    }

    /// Days in a row with words, ending today, or yesterday while today has none yet.
    func currentStreak(now: Date = Date()) -> Int {
        var day = calendar.startOfDay(for: now)
        if !hasWords(on: day) { day = calendar.date(byAdding: .day, value: -1, to: day) ?? day }
        var n = 0
        while hasWords(on: day), let prev = calendar.date(byAdding: .day, value: -1, to: day) {
            n += 1
            day = prev
        }
        return n
    }

    var longestStreak: Int {
        var best = 0, run = 0
        var last: Date?
        for day in days where day.words > 0 {
            let follows = last.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) } == day.date
            run = follows ? run + 1 : 1
            best = max(best, run)
            last = day.date
        }
        return best
    }

    private func hasWords(on day: Date) -> Bool { (days.first { $0.date == day }?.words ?? 0) > 0 }

    /// The last `weeks` calendar weeks, oldest first, each with seven days from the week's first
    /// day; days after today are nil.
    func weeks(_ weeks: Int, now: Date = Date()) -> [[(date: Date, words: Int)?]] {
        let today = calendar.startOfDay(for: now)
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start else { return [] }
        let byDate = Dictionary(days.map { ($0.date, $0.words) }, uniquingKeysWith: +)
        return (0..<weeks).reversed().map { back in
            let start = calendar.date(byAdding: .weekOfYear, value: -back, to: thisWeek) ?? thisWeek
            return (0..<7).map { offset in
                guard let d = calendar.date(byAdding: .day, value: offset, to: start), d <= today else { return nil }
                return (d, byDate[d] ?? 0)
            }
        }
    }
}

/// Stats arithmetic (§23.12).
enum StatsMath {
    static let typingWPM = 40.0

    /// Words ÷ recording minutes.
    static func wordsPerMinute(words: Int, seconds: Double) -> Int {
        guard seconds > 0 else { return 0 }
        return Int((Double(words) / (seconds / 60)).rounded())
    }

    /// max(0, words ÷ 40 − recording minutes), in minutes.
    static func minutesSaved(words: Int, seconds: Double) -> Double {
        max(0, Double(words) / typingWPM - seconds / 60)
    }

    /// "1 h 5 min", or "28 min" under an hour.
    static func savedText(minutes: Double) -> String {
        let total = Int(minutes.rounded())
        if total < 60 { return String(localized: "\(total) min") }
        return String(localized: "\(total / 60) h \(total % 60) min")
    }

    /// The `top` languages by words, the rest as Other; percents rounded so they add up to 100.
    /// Codes vypo doesn't know count as Other.
    static func languageShares(_ words: [String: Int], top: Int = 3) -> [LanguageShare] {
        let total = words.values.reduce(0, +)
        guard total > 0 else { return [] }
        var known: [(lang: Lang, words: Int)] = []
        for (code, n) in words where n > 0 {
            if let lang = Lang(rawValue: code) { known.append((lang, n)) }
        }
        known.sort { $0.words != $1.words ? $0.words > $1.words : $0.lang.rawValue < $1.lang.rawValue }
        var shares: [(lang: Lang?, words: Int)] = known.prefix(top).map { ($0.lang, $0.words) }
        let other = total - shares.reduce(0) { $0 + $1.words }
        if other > 0 { shares.append((nil, other)) }
        var percents = shares.map { Int((Double($0.words) * 100 / Double(total)).rounded()) }
        if let largest = percents.indices.max(by: { shares[$0].words < shares[$1].words }) {
            percents[largest] += 100 - percents.reduce(0, +)
        }
        return zip(shares, percents).map { LanguageShare(lang: $0.lang, words: $0.words, percent: $1) }
    }

    /// The apps card: the `top` apps by words and, when there are two or more beyond that, the rest as one “Other” row. Percents are
    /// rounded so that all rows add up to 100.
    static func appShares(_ apps: [(app: String, words: Int)], top: Int = 5) -> AppShares {
        let used = apps.filter { $0.words > 0 }
        let total = used.reduce(0) { $0 + $1.words }
        guard total > 0 else { return AppShares(rows: [], other: nil) }
        // “Other (1 app)” would be the sixth app under another name: show it.
        let shown = used.count == top + 1 ? top + 1 : top
        let head = Array(used.prefix(shown))
        let rest = used.dropFirst(shown)
        var words = head.map(\.words)
        if !rest.isEmpty { words.append(rest.reduce(0) { $0 + $1.words }) }
        var percents = words.map { Int((Double($0) * 100 / Double(total)).rounded()) }
        if let largest = percents.indices.max(by: { words[$0] < words[$1] }) {
            percents[largest] += 100 - percents.reduce(0, +)
        }
        let rows = zip(head, percents).map { AppShare(app: $0.app, percent: $1) }
        let other = rest.isEmpty ? nil : OtherApps(count: rest.count, percent: percents[head.count])
        return AppShares(rows: rows, other: other)
    }
}

struct AppShare: Equatable { var app: String; var percent: Int }
struct OtherApps: Equatable { var count: Int; var percent: Int }
struct AppShares: Equatable { var rows: [AppShare]; var other: OtherApps? }
