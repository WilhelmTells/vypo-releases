import Foundation

/// What the widget knows: one small file the app writes into the App Group and the widget reads. It holds no dictated
/// text; the only word from a dictation is the glossary suggestion's term. Names and the saved time arrive finished, in
/// the app's language, so the widget never works out anything the app already has.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    struct Achievement: Codable, Equatable, Sendable {
        var id: String
        var name: String
        /// The day it was stamped, “yyyy-MM-dd”; nil for one still to stamp.
        var day: String?
    }

    struct Suggestion: Codable, Equatable, Sendable {
        var id: String
        var term: String
    }

    static let currentVersion = 1

    var version = Self.currentVersion
    var writtenAt = Date(timeIntervalSince1970: 0)
    /// “Collect stats”. While it is off the snapshot carries no numbers, and the widget says so.
    var collecting = true
    var level = 1
    var rankName = ""
    /// nil at the highest rank.
    var nextRankName: String?
    var words = 0
    /// The words at which the rank starts and the next one starts (nil at the highest).
    var rankStart = 0
    var nextStart: Int?
    /// Within the rank, 0…1.
    var progress = 0.0
    /// The day `wordsToday` belongs to. A day later the widget shows 0 until the app writes again.
    var today = Date(timeIntervalSince1970: 0)
    var wordsToday = 0
    var minutesSaved = 0.0
    var savedText = ""
    /// Words per day: one array per week, oldest first, seven days each from the week's first day; nil after today.
    var activity: [[Int?]] = []
    /// The latest stamped achievement.
    var latest: Achievement?
    /// The first one ready to stamp, in the order of the Stats page.
    var ready: Achievement?
    /// The newest suggestion still waiting for an answer.
    var suggestion: Suggestion?
    var uiLanguage = "en"
    var numberLocale = "en_US"
    /// The name of the first achievement, for the new user's pre-print.
    var firstAchievementName = "First Words"

    init() {}

    private enum CodingKeys: String, CodingKey {
        case version, writtenAt, collecting, level, rankName, nextRankName, words, rankStart, nextStart, progress, today, wordsToday,
             minutesSaved, savedText, activity, latest, ready, suggestion, uiLanguage, numberLocale, firstAchievementName
    }

    /// Every field may be missing: the widget can meet a file from an older or newer app.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WidgetSnapshot()
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? d.version
        writtenAt = try c.decodeIfPresent(Date.self, forKey: .writtenAt) ?? d.writtenAt
        collecting = try c.decodeIfPresent(Bool.self, forKey: .collecting) ?? d.collecting
        level = try c.decodeIfPresent(Int.self, forKey: .level) ?? d.level
        rankName = try c.decodeIfPresent(String.self, forKey: .rankName) ?? d.rankName
        nextRankName = try c.decodeIfPresent(String.self, forKey: .nextRankName)
        words = try c.decodeIfPresent(Int.self, forKey: .words) ?? d.words
        rankStart = try c.decodeIfPresent(Int.self, forKey: .rankStart) ?? d.rankStart
        nextStart = try c.decodeIfPresent(Int.self, forKey: .nextStart)
        progress = try c.decodeIfPresent(Double.self, forKey: .progress) ?? d.progress
        today = try c.decodeIfPresent(Date.self, forKey: .today) ?? d.today
        wordsToday = try c.decodeIfPresent(Int.self, forKey: .wordsToday) ?? d.wordsToday
        minutesSaved = try c.decodeIfPresent(Double.self, forKey: .minutesSaved) ?? d.minutesSaved
        savedText = try c.decodeIfPresent(String.self, forKey: .savedText) ?? d.savedText
        activity = try c.decodeIfPresent([[Int?]].self, forKey: .activity) ?? d.activity
        latest = try c.decodeIfPresent(Achievement.self, forKey: .latest)
        ready = try c.decodeIfPresent(Achievement.self, forKey: .ready)
        suggestion = try c.decodeIfPresent(Suggestion.self, forKey: .suggestion)
        uiLanguage = try c.decodeIfPresent(String.self, forKey: .uiLanguage) ?? d.uiLanguage
        numberLocale = try c.decodeIfPresent(String.self, forKey: .numberLocale) ?? d.numberLocale
        firstAchievementName = try c.decodeIfPresent(String.self, forKey: .firstAchievementName) ?? d.firstAchievementName
    }

    /// The same content, whenever it was written.
    func sameContent(as other: WidgetSnapshot) -> Bool {
        var a = self, b = other
        a.writtenAt = b.writtenAt
        return a == b
    }

    /// The words of `day`: 0 once the snapshot's day has passed.
    func wordsToday(on day: Date, calendar: Calendar = .current) -> Int {
        calendar.isDate(today, inSameDayAs: day) ? wordsToday : 0
    }

    /// How a day's words read in the activity squares: 0, or 1…4 of the busiest day. The Stats heatmap uses it too.
    static func activityLevel(_ words: Int, peak: Int) -> Int {
        guard words > 0 else { return 0 }
        return min(4, 1 + Int(Double(words) / Double(peak) * 3.999))
    }
}

/// The snapshot's file in the App Group. The group's name comes from `Info.plist`, where it is built from the team
/// (the test app's copy has its own). A build without a team has no group: then nothing is written or read.
enum WidgetStore {
    static let fileName = "widget-snapshot.json"

    static var groupName: String? { Bundle.main.object(forInfoDictionaryKey: "VYPOAppGroup") as? String }

    static var url: URL? {
        guard let groupName, !groupName.hasPrefix(".") else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupName)?.appendingPathComponent(fileName)
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func write(_ snapshot: WidgetSnapshot, to url: URL) throws {
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }

    static func read(from url: URL) -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }
}
