import XCTest
@testable import vypo

/// Writing apps: a capital after every line break, and a noun is not a mark (“ein wichtiger Punkt”).
@MainActor
final class WritingPunctuationTests: XCTestCase {
    private func writing(_ raw: String, _ lang: Lang = .de, glossary: [GlossaryEntry] = [], spellings: [String] = [],
                         replacements: [Replacement]? = nil, smartSpacing: Bool = false) -> String {
        var text = TextPipeline.process(raw, PipelineContext(language: lang, glossary: glossary,
                                                             replacements: replacements ?? Replacements.defaults,
                                                             spellings: spellings, mode: .writing))
        if smartSpacing {
            // The paste-time pass with the cursor at the start of an empty field.
            text = ContextFormatter.format(text, context: InsertionContext(before: "", after: nil), language: lang,
                                           glossaryTerms: Set(glossary.map(\.term)).union(spellings))
        }
        return text.replacingOccurrences(of: "\n", with: "⏎")
    }

    // MARK: Error 1: capital after a line break

    func testACapitalAfterASpokenNewLine() {
        XCTAssertEqual(writing("Erste Zeile neue Zeile zweite Zeile"), "Erste Zeile⏎Zweite Zeile")
        XCTAssertEqual(writing("First line new line second line", .en), "First line⏎Second line")
    }

    func testSmartSpacingDoesNotFixItInTheMiddle() {
        // The paste-time formatter only looks at the start of the text: the capital after the break must come from the pipeline.
        XCTAssertEqual(writing("Erste Zeile neue Zeile zweite Zeile", smartSpacing: true), "Erste Zeile⏎Zweite Zeile")
    }

    func testACapitalAfterANewParagraph() {
        XCTAssertEqual(writing("Fertig Punkt neuer Absatz nächster Satz"), "Fertig.⏎⏎Nächster Satz")
    }

    func testTheSameWithAnEmptyReplacementsList() {
        XCTAssertEqual(writing("Erste Zeile neue Zeile zweite Zeile", replacements: []), "Erste Zeile⏎Zweite Zeile")
    }

    func testATermsOwnSpellingWinsAfterABreak() {
        XCTAssertEqual(writing("neue Zeile macOS ist da", spellings: ["macOS"]), "⏎macOS ist da")
        XCTAssertEqual(writing("Hallo neue Zeile iPhone ist da", spellings: ["iPhone"]), "Hallo⏎iPhone ist da")
        let term = GlossaryEntry(term: "vypo")
        XCTAssertEqual(writing("Hallo neue Zeile vypo läuft", glossary: [term]), "Hallo⏎vypo läuft")
    }

    func testATermsOwnSpellingWinsAfterAPeriodToo() {
        XCTAssertEqual(writing("Fertig Punkt macOS läuft", spellings: ["macOS"]), "Fertig. macOS läuft")
    }

    func testOtherModesAreNotTouched() {
        func run(_ mode: AppMode) -> String {
            TextPipeline.process("Erste Zeile neue Zeile zweite Zeile", PipelineContext(language: .de, replacements: Replacements.defaults, mode: mode))
                .replacingOccurrences(of: "\n", with: "⏎")
        }
        XCTAssertEqual(run(.standard), "Erste Zeile⏎zweite Zeile")
        XCTAssertEqual(run(.prompt), "Erste Zeile⏎zweite Zeile")
    }

    func testCapitalsAfterBreaksSkipOpeningQuotesAndDigits() {
        XCTAssertEqual(SpokenPunctuation.capitalizeAfterLineBreaks("a\n„b“\n\n  c\n3 d"), "a\n„B“\n\n  C\n3 d")
        XCTAssertEqual(SpokenPunctuation.capitalizeAfterLineBreaks("no break here"), "no break here")
    }

    // MARK: Error 2: a noun is not a mark

    func testNounsStay() {
        XCTAssertEqual(writing("Das ist ein wichtiger Punkt"), "Das ist ein wichtiger Punkt")
        XCTAssertEqual(writing("Der Punkt ist klar"), "Der Punkt ist klar")
        XCTAssertEqual(writing("Da fehlt ein Komma"), "Da fehlt ein Komma")
        XCTAssertEqual(writing("Das ist ein großes Fragezeichen"), "Das ist ein großes Fragezeichen")
        XCTAssertEqual(writing("It took a long period of time", .en), "It took a long period of time")
        XCTAssertEqual(writing("In that period we shipped", .en), "In that period we shipped")
        XCTAssertEqual(writing("That was an important period", .en), "That was an important period")
        XCTAssertEqual(writing("Damit du meinen Punkt verstehst"), "Damit du meinen Punkt verstehst")
        XCTAssertEqual(writing("Ich glaube beim dritten Punkt"), "Ich glaube beim dritten Punkt")
        XCTAssertEqual(writing("Das ist kein Komma"), "Das ist kein Komma")
    }

    func testMarksStay() {
        XCTAssertEqual(writing("Das ist gut Punkt"), "Das ist gut.")
        XCTAssertEqual(writing("Hallo Komma wie geht es dir Punkt"), "Hallo, wie geht es dir.")
        XCTAssertEqual(writing("Hello comma how are you period", .en), "Hello, how are you.")
        XCTAssertEqual(writing("Ich habe das gemacht Punkt"), "Ich habe das gemacht.")
        XCTAssertEqual(writing("Ich habe das alles verstanden Punkt"), "Ich habe das alles verstanden.")
        XCTAssertEqual(writing("Wirklich Fragezeichen"), "Wirklich?")
    }

    func testTheRuleCoversEveryTableWord() {
        XCTAssertEqual(writing("Das ist ein Doppelpunkt"), "Das ist ein Doppelpunkt")
        XCTAssertEqual(writing("Ein neues Semikolon"), "Ein neues Semikolon")
        // With the Replacements entry too since 0.4.0: `SpokenCharactersTests.testTheNewLineAsANounStaysInBothLayouts`.
        XCTAssertEqual(writing("Die neue Zeile gefällt mir", replacements: []), "Die neue Zeile gefällt mir")
    }

    func testAComputedSentenceBoundaryStopsTheRule() {
        // An article before a sentence end does not reach over it.
        XCTAssertEqual(writing("Ich nehme das. Punkt"), "Ich nehme das.")
    }

    func testIsNounDirectly() {
        let w = { (s: String) in Tokenized(s).words }
        XCTAssertTrue(SpokenPunctuation.isNoun(w("ein wichtiger Punkt"), at: 2, language: .de))
        XCTAssertFalse(SpokenPunctuation.isNoun(w("ein wichtiger, Punkt"), at: 2, language: .de))
        XCTAssertFalse(SpokenPunctuation.isNoun(w("Punkt"), at: 0, language: .de))
        XCTAssertFalse(SpokenPunctuation.isNoun(w("an important period"), at: 2, language: .de), "“an” is a German preposition")
        XCTAssertTrue(SpokenPunctuation.isNoun(w("an important period"), at: 2, language: .en))
    }
}
