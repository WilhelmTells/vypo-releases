import XCTest
@testable import vypo

final class StatsComparisonTests: XCTestCase {
    private func work(_ id: String, _ words: Int, soFar: Bool = false) -> Work {
        if soFar { return Work(id: id, words: words, title: { id }, soFar: { number in "\(number) of \(id)" }) }
        return Work(id: id, words: words, title: { id })
    }

    private func kind(_ words: Int, in works: [Work]) -> [WorkComparison.Kind] {
        StatsMath.comparisonCandidates(words: words, works: works).map(\.kind)
    }

    func testBoundariesOfTheFactor() {
        let w = [work("w", 1_000)]
        XCTAssertEqual(kind(299, in: w), [], "below 0.3")
        XCTAssertEqual(kind(300, in: w), [], "0.3 for a work without “so far”")
        XCTAssertEqual(kind(499, in: w), [])
        XCTAssertEqual(kind(500, in: w), [.moreThanHalf])
        XCTAssertEqual(kind(999, in: w), [.moreThanHalf])
        XCTAssertEqual(kind(1_000, in: w), [.longerThan])
        XCTAssertEqual(kind(1_999, in: w), [.longerThan])
        XCTAssertEqual(kind(2_000, in: w), [.timesOver(2)])
        XCTAssertEqual(kind(3_999, in: w), [.timesOver(3)], "rounded down")
        XCTAssertEqual(kind(20_000, in: w), [.timesOver(20)])
        XCTAssertEqual(kind(20_001, in: w), [], "above 20")
    }

    func testOnlyTheBigWorksGetTheSoFarForm() {
        let big = [work("big", 1_000, soFar: true)]
        XCTAssertEqual(kind(300, in: big), [.soFar(0.3)])
        XCTAssertEqual(kind(449, in: big), [.soFar(0.4)])
        XCTAssertEqual(kind(499, in: big), [.soFar(0.5)])
        XCTAssertEqual(kind(299, in: big), [])
        // The real list: only Bible, Shakespeare and all Harry Potter have it.
        XCTAssertEqual(Work.all.filter { $0.soFar != nil }.map(\.id), ["bible", "shakespeare", "harryPotterAll"])
        XCTAssertEqual(Work.all.count, 16)
        XCTAssertEqual(Work.all.map(\.words), Work.all.map(\.words).sorted())
    }

    /// No work fits below half of the shortest one (8,500 words): book pages until then.
    func testBelowTheFirstWorkItStaysAtBookPages() {
        XCTAssertNil(StatsMath.comparison(words: 499))
        for words in [500, 2_000, 5_100, 8_499] {
            let c = StatsMath.comparison(words: words)
            XCTAssertEqual(c?.pages, words / 250, "\(words)")
            XCTAssertEqual(c?.workID, "")
        }
        XCTAssertNil(StatsMath.comparison(words: 8_500)?.pages, "half of The Little Prince")
        XCTAssertEqual(StatsMath.comparison(words: 8_500)?.workID, "littlePrince")
        // Far beyond every work: pages again rather than nothing.
        XCTAssertEqual(StatsMath.comparison(words: 30_000_000)?.pages, 120_000)
    }

    func testTheDrawIsInjectableAndDoesNotRepeat() {
        let works = [work("a", 1_000), work("b", 1_000), work("c", 1_000)]
        XCTAssertEqual(StatsMath.comparison(words: 1_500, works: works, pick: { _ in 0 })?.workID, "a")
        XCTAssertEqual(StatsMath.comparison(words: 1_500, works: works, pick: { $0 - 1 })?.workID, "c")
        // Not the last one again, whatever the draw says.
        for last in ["a", "b", "c"] {
            for i in 0..<2 {
                XCTAssertNotEqual(StatsMath.comparison(words: 1_500, previous: last, works: works, pick: { _ in i })?.workID, last)
            }
        }
        // One candidate only: it may repeat.
        XCTAssertEqual(StatsMath.comparison(words: 1_500, previous: "a", works: [work("a", 1_000)], pick: { _ in 0 })?.workID, "a")
        // A draw out of range is held to the list.
        XCTAssertNotNil(StatsMath.comparison(words: 1_500, works: works, pick: { _ in 99 }))
    }

    func testEveryWordCountHasAnAnswerAndTheRealDrawCoversTheCandidates() {
        for words in stride(from: 500, through: 3_000_000, by: 7_919) {
            XCTAssertNotNil(StatsMath.comparison(words: words), "\(words)")
        }
        var seen = Set<String>()
        for _ in 0..<200 { if let c = StatsMath.comparison(words: 130_000) { seen.insert(c.workID) } }
        XCTAssertEqual(seen, Set(StatsMath.comparisonCandidates(words: 130_000).map(\.workID)))
        XCTAssertGreaterThan(seen.count, 3)
    }

    func testTheTextsAreWholeSentences() {
        let cases: [(WorkComparison, String)] = [
            (WorkComparison(workID: "hobbit", kind: .timesOver(3)), "That’s The Hobbit, 3 times over."),
            (WorkComparison(workID: "littlePrince", kind: .longerThan), "Longer than The Little Prince."),
            (WorkComparison(workID: "warAndPeace", kind: .moreThanHalf), "More than half of War and Peace."),
            (WorkComparison(workID: "bible", kind: .soFar(0.4)), "0.4 Bibles so far."),
            (WorkComparison(workID: "", kind: .longerThan, pages: 12), "About as long as 12 book pages."),
        ]
        for (c, expected) in cases {
            XCTAssertEqual(String(StatsMath.comparisonText(c).characters), expected)
        }
        // The title is italic.
        let attributed = StatsMath.comparisonText(cases[0].0)
        XCTAssertTrue(attributed.runs.contains { $0.inlinePresentationIntent?.contains(.emphasized) == true })
    }
}

/// The German sentences keep the title in the nominative (no “von dem Hobbit”).
final class ComparisonCatalogTests: XCTestCase {
    private func catalog() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("vypo/Localizable.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return try XCTUnwrap(json?["strings"] as? [String: Any])
    }

    private func german(_ key: String, in strings: [String: Any]) -> String? {
        let entry = strings[key] as? [String: Any]
        let de = (entry?["localizations"] as? [String: Any])?["de"] as? [String: Any]
        return (de?["stringUnit"] as? [String: Any])?["value"] as? String
    }

    func testGermanSentencesAreNominativeAndThereAreNoDativeKeys() throws {
        let strings = try catalog()
        XCTAssertTrue(strings.keys.filter { $0.hasPrefix("dative:") }.isEmpty)
        XCTAssertEqual(german("That’s *%@*, %lld times over.", in: strings), "Das ist %2$lld-mal *%1$@*.")
        XCTAssertEqual(german("Longer than *%@*.", in: strings), "Länger als *%@*.")
        XCTAssertEqual(german("More than half of *%@*.", in: strings), "Mehr als halb so lang wie *%@*.")
        XCTAssertEqual(german("%@ Bibles so far.", in: strings), "Schon %@-mal die Bibel.")
        XCTAssertEqual(german("%@ of Shakespeare’s complete works so far.", in: strings), "Schon %@-mal Shakespeares Gesamtwerk.")
        XCTAssertEqual(german("%@ of all seven Harry Potter books so far.", in: strings), "Schon %@-mal alle sieben Harry-Potter-Bände.")
        XCTAssertEqual(german("the Bible", in: strings), "die Bibel")
    }
}
