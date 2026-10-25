import SwiftUI
import XCTest
@testable import vypo

@MainActor
final class TermExtractorTests: XCTestCase {
    static let sample = """
    This paper looks at SwiftUI on macOS. Bounded rationality goes back to Herbert Simon and his work.
    Later, Herbert Simon described satisficing. The Container stores each Haus in a Container.
    We also tested it with the GPT-4 model and S4HANA systems.
    """

    func testFixedSample() {
        // Names are unknown to both dictionaries; ordinary words are known.
        let unknown: Set<String> = ["Herbert", "Simon"]
        var extractor = TermExtractor()
        extractor.isUnknownWord = { unknown.contains($0) }
        let terms = extractor.extract(from: Self.sample, existing: []).map(\.term)
        XCTAssertTrue(terms.contains("SwiftUI"), "\(terms)")
        XCTAssertTrue(terms.contains("macOS"), "\(terms)")
        XCTAssertTrue(terms.contains("Herbert Simon"), "\(terms)")
        XCTAssertFalse(terms.contains("Container"))
        XCTAssertFalse(terms.contains("Haus"))
        XCTAssertTrue(terms.contains("GPT-4"))
        XCTAssertTrue(terms.contains("S4HANA"))
    }

    func testExistingTermsAreSkipped() {
        var extractor = TermExtractor()
        extractor.isUnknownWord = { _ in false }
        XCTAssertFalse(extractor.extract(from: Self.sample, existing: ["SwiftUI"]).map(\.term).contains("SwiftUI"))
    }
}

@MainActor
final class StatsTests: XCTestCase {
    func testMath() {
        XCTAssertEqual(StatsMath.wordsPerMinute(words: 300, seconds: 120), 150)
        XCTAssertEqual(StatsMath.wordsPerMinute(words: 10, seconds: 0), 0)
        // 400 words typed at 40 wpm = 10 min; 2 min dictating → 8 min saved.
        XCTAssertEqual(StatsMath.minutesSaved(words: 400, seconds: 120), 8, accuracy: 0.001)
        XCTAssertEqual(StatsMath.minutesSaved(words: 10, seconds: 600), 0)
        XCTAssertEqual(StatsMath.savedText(minutes: 65), "1 h 5 min")
        XCTAssertEqual(StatsMath.savedText(minutes: 28), "28 min")
        XCTAssertEqual(StatsMath.languageShares(["en": 3, "de": 1]).first?.percent, 75)
    }

    func testUndoSubtracts() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let stats = StatsStore(store: Store(directory: dir))
        stats.record(words: 10, seconds: 5, language: .en)
        stats.record(words: 4, seconds: 2, language: .de)
        XCTAssertEqual(stats.today, 14)
        stats.record(words: 4, seconds: 2, language: .de, sign: -1)
        XCTAssertEqual(stats.today, 10)
        XCTAssertNil(stats.days.first?.wordsByLanguage["de"])
        XCTAssertEqual(stats.lastDays(14).count, 14)
        stats.reset()
        XCTAssertEqual(stats.allTime, 0)
    }

    func testStreaksAppsAndWeeks() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let stats = StatsStore(store: Store(directory: dir))
        let now = Date()
        // Yesterday and the two days before, a gap, then two more days: today is still empty.
        for back in [1, 2, 3, 6, 7] {
            stats.record(words: 10, seconds: 5, language: .en, app: back == 1 ? "com.apple.Notes" : "com.apple.mail",
                         at: now.addingTimeInterval(-Double(back) * 86_400))
        }
        XCTAssertEqual(stats.currentStreak(now: now), 3)
        XCTAssertEqual(stats.longestStreak, 3)
        XCTAssertEqual(stats.apps.first?.app, "com.apple.mail")
        XCTAssertEqual(stats.apps.first?.words, 40)
        stats.record(words: 10, seconds: 5, language: .en, app: "com.apple.Notes", at: now.addingTimeInterval(-86_400), sign: -1)
        XCTAssertEqual(stats.apps.count, 1)
        let weeks = stats.weeks(4, now: now)
        XCTAssertEqual(weeks.count, 4)
        XCTAssertTrue(weeks.allSatisfy { $0.count == 7 })
        XCTAssertNil(weeks.last?.last.flatMap { $0 }.map { $0.date > Calendar.current.startOfDay(for: now) ? $0 : nil } ?? nil)
        XCTAssertEqual(StatsMath.comparison(words: 400), nil)
        XCTAssertEqual(StatsMath.comparison(words: 12_000)?.workID, "littlePrince")
    }

    func testSearchMarksEveryMatch() {
        let marked = HistoryRow.marked("Claus, claus and CLAUS", "claus")
        let runs = marked.runs.filter { $0.backgroundColor != nil }
        XCTAssertEqual(runs.count, 3)
        XCTAssertEqual(HistoryRow.marked("abc", "").runs.filter { $0.backgroundColor != nil }.count, 0)
    }

    func testPillColorMigrationAndHex() {
        let defaults = UserDefaults(suiteName: "vypo.test.\(UUID().uuidString)")!
        defaults.set("accent", forKey: DefaultsKey.pillColor)
        let prefs = Preferences(defaults: defaults)
        XCTAssertEqual(prefs.pillColor, .orange)
        XCTAssertEqual(prefs.pillCustomColor, Preferences.defaultCustomColor)
        XCTAssertEqual(NSColor(Color(hex: "#3A7BD5")!).hex, "#3A7BD5")
        XCTAssertNil(Color(hex: "nope"))
    }

    func testHistoryGroupsByDay() {
        let now = Date()
        let items = [0.0, 60, 86_400 * 1.5].map {
            HistoryItem(date: now.addingTimeInterval(-$0), text: "x", rawText: "", language: .en, modelID: "m")
        }
        let groups = HistoryPane.byDay(items)
        XCTAssertEqual(groups.first?.items.count, Calendar.current.isDate(now.addingTimeInterval(-60), inSameDayAs: now) ? 2 : 1)
        XCTAssertEqual(groups.map(\.items.count).reduce(0, +), 3)
    }
}

@MainActor
final class GlossarySetTests: XCTestCase {
    func testActiveSetsOnlyAndDeleteRemovesTerms() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let g = GlossaryStore(store: Store(directory: dir))
        let work = g.addSet(named: "Work")
        g.add(term: "Kubernetes")
        g.add(term: "Jamf", setID: work.id)
        XCTAssertEqual(Set(g.entries(for: .en).map(\.term)), ["Kubernetes", "Jamf"])
        g.setActive(work.id, false)
        XCTAssertEqual(g.entries(for: .en).map(\.term), ["Kubernetes"])
        g.deleteSet(work.id)
        XCTAssertEqual(g.entries.map(\.term), ["Kubernetes"])
        g.deleteSet(GlossarySet.generalID)
        XCTAssertEqual(g.sets.count, 1)
    }

    func testExportImportMergesSetsByName() throws {
        let a = GlossaryStore(store: Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        let set = a.addSet(named: "Thesis")
        a.add(term: "Herbert Simon", setID: set.id)
        let data = try a.exportData()
        let b = GlossaryStore(store: Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        b.addSet(named: "Thesis")
        try b.importData(data)
        XCTAssertEqual(b.sets.filter { $0.name == "Thesis" }.count, 1)
        XCTAssertEqual(b.set(for: b.entries[0]).name, "Thesis")
    }
}
