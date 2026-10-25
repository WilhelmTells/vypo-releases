import XCTest
@testable import vypo

final class ContextFormatterTests: XCTestCase {
    private func fmt(_ text: String, before: String, after: Character? = nil, _ lang: Lang = .en, terms: Set<String> = []) -> String {
        ContextFormatter.format(text, context: InsertionContext(before: before, after: after), language: lang,
                                glossaryTerms: terms, germanLowercase: ContextFormatter.germanLowercaseStarters)
    }

    func testLetterBefore() { XCTAssertEqual(fmt("hello", before: "a"), " hello") }
    func testPeriodBefore() { XCTAssertEqual(fmt("hello", before: "."), " Hello") }
    func testCommaEnglish() { XCTAssertEqual(fmt("Hello", before: ","), " hello") }
    func testCommaGermanNoun() { XCTAssertEqual(fmt("Haus", before: ",", .de), " Haus") }
    func testCommaGermanArticle() { XCTAssertEqual(fmt("Die", before: ",", .de), " die") }
    func testAcronymKept() { XCTAssertEqual(fmt("NASA said", before: "a "), "NASA said") }
    func testIKept() { XCTAssertEqual(fmt("I think", before: ","), " I think") }
    func testGlossaryTermKept() { XCTAssertEqual(fmt("Kubernetes runs", before: ",", terms: ["Kubernetes"]), " Kubernetes runs") }
    func testTrailingPeriodRemovedBeforeLetter() { XCTAssertEqual(fmt("hello.", before: "a ", after: "w"), "hello") }
    func testStartOfFieldCapitalizes() { XCTAssertEqual(fmt("hello", before: ""), "Hello") }
    func testNoSpaceAfterOpeningParen() { XCTAssertEqual(fmt("hello", before: "("), "hello") }
    func testNewlineCapitalizes() { XCTAssertEqual(fmt("hello", before: "\n"), "Hello") }

    func testAXUnavailableLeavesTextUnchanged() {
        XCTAssertEqual(ContextFormatter.format("Hello.", context: nil, language: .en, glossaryTerms: []), "Hello.")
    }

    func testStartersListIsBundled() {
        let s = ContextFormatter.germanLowercaseStarters
        XCTAssertGreaterThan(s.count, 200)
        XCTAssertTrue(s.contains("die"))
        XCTAssertFalse(s.contains("haus"))
    }
}

final class FillerRemoverTests: XCTestCase {
    func testLeadingFillerWithComma() {
        XCTAssertEqual(FillerRemover.remove("um, I think so", words: FillerRemover.defaultWords(.en)), "I think so")
    }

    func testGermanFillerBetweenCommas() {
        XCTAssertEqual(FillerRemover.remove("Das ist, äh, gut", words: FillerRemover.defaultWords(.de)), "Das ist, gut")
    }

    func testLikeIsNeverRemoved() {
        XCTAssertEqual(FillerRemover.remove("it was like, really good", words: FillerRemover.defaultWords(.en)), "it was like, really good")
        XCTAssertFalse(FillerRemover.defaultWords(.en).contains("like"))
        XCTAssertFalse(FillerRemover.defaultWords(.de).contains("halt"))
    }

    func testCapitalizesAfterRemovedSentenceStart() {
        XCTAssertEqual(FillerRemover.remove("Um so we start. Uh then we stop", words: FillerRemover.defaultWords(.en)), "So we start. Then we stop")
    }
}

final class SpokenPunctuationTests: XCTestCase {
    func testEnglish() {
        XCTAssertEqual(SpokenPunctuation.apply("hello comma world period", language: .en), "hello, world.")
    }

    func testGerman() {
        XCTAssertEqual(SpokenPunctuation.apply("Hallo Komma wie geht's Fragezeichen neuer Absatz danke", language: .de),
                       "Hallo, wie geht's?\n\nDanke")
    }

    func testModelPunctuationIsNotDuplicated() {
        XCTAssertEqual(SpokenPunctuation.apply("done. period", language: .en), "done.")
        XCTAssertEqual(SpokenPunctuation.apply("hello, comma, world", language: .en), "hello, world")
    }

    func testSpokenQuotesGerman() {
        XCTAssertEqual(SpokenPunctuation.apply("er sagte Anführungszeichen auf hallo Anführungszeichen zu", language: .de),
                       "er sagte „hallo“")
    }

    func testTypographicQuotesGerman() {
        XCTAssertEqual(TypographicQuotes.apply("Er sagte \"hallo\" und geht's", language: .de), "Er sagte „hallo“ und geht’s")
    }

    func testTypographicQuotesEnglish() {
        XCTAssertEqual(TypographicQuotes.apply("\"Hi\" there", language: .en), "“Hi” there")
    }

    func testPipelineAppliesOnlyInWritingApps() {
        var ctx = PipelineContext(language: .en)
        ctx.mode = .standard
        XCTAssertEqual(TextPipeline.process("hello comma world", ctx), "hello comma world")
        ctx.mode = .writing
        XCTAssertEqual(TextPipeline.process("hello comma world", ctx), "hello, world")
    }
}
