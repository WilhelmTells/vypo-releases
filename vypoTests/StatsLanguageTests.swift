import XCTest
@testable import vypo

@MainActor
final class StatsLanguageTests: XCTestCase {
    private func store() -> StatsStore {
        StatsStore(store: Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
    }

    /// `stats.json` as written before the language choice.
    func testLegacyDayDecodes() throws {
        let json = #"{"date":"2026-10-22T22:00:00Z","words":30,"recordingSeconds":12,"wordsEN":20,"wordsDE":10,"apps":{"com.apple.TextEdit":30}}"#
        let day = try Store.decoder.decode(StatsDay.self, from: Data(json.utf8))
        XCTAssertEqual(day.wordsByLanguage, ["en": 20, "de": 10])
        XCTAssertEqual(day.apps, ["com.apple.TextEdit": 30])
        let written = String(decoding: try Store.encoder.encode(day), as: UTF8.self)
        XCTAssertFalse(written.contains("wordsEN"), written)
        XCTAssertEqual(try Store.decoder.decode(StatsDay.self, from: Data(written.utf8)), day)
    }

    func testRecordsAnyLanguage() {
        let stats = store()
        stats.record(words: 5, seconds: 2, language: .fr)
        XCTAssertEqual(stats.days.first?.wordsByLanguage, ["fr": 5])
    }

    func testUndoNeverGoesNegative() {
        let stats = store()
        stats.record(words: 3, seconds: 1, language: .en)
        stats.record(words: 5, seconds: 2, language: .fr, sign: -1)
        XCTAssertEqual(stats.days.first?.wordsByLanguage, ["en": 3])
    }

    func testSharesTopThreeAndOther() {
        let shares = StatsMath.languageShares(["en": 50, "de": 30, "fr": 10, "es": 6, "it": 4])
        XCTAssertEqual(shares, [
            LanguageShare(lang: .en, words: 50, percent: 50),
            LanguageShare(lang: .de, words: 30, percent: 30),
            LanguageShare(lang: .fr, words: 10, percent: 10),
            LanguageShare(lang: nil, words: 10, percent: 10),
        ])
        XCTAssertEqual(StatsMath.languageShares(["en": 2, "de": 1]).map(\.percent), [67, 33])
        XCTAssertEqual(StatsMath.languageShares([:]), [])
    }
}
