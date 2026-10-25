import XCTest
@testable import vypo

final class ParakeetMergeTests: XCTestCase {
    func testSpanAlreadyContainingTermIsSkipped() {
        let out = ParakeetEngine.merge("We run everything on Kubernetes now", replacements: [("on Kubernetes now", "Kubernetes")])
        XCTAssertEqual(out, "We run everything on Kubernetes now")
    }

    func testOnlyBestMatchingPartIsReplaced() {
        let out = ParakeetEngine.merge("deploy it on cooper netties now.", replacements: [("on cooper netties now.", "Kubernetes")],
                                       aliases: ["Kubernetes": ["cooper netties"]])
        XCTAssertEqual(out, "deploy it on Kubernetes now.")
    }

    func testTrailingPunctuationIsKept() {
        let out = ParakeetEngine.merge("I use swift you eye.", replacements: [("swift you eye.", "SwiftUI")])
        XCTAssertEqual(out, "I use SwiftUI.")
    }

    func testUnrelatedSpanIsNotReplaced() {
        let text = "Was hältst du davon? Vielleicht, dass die ein bisschen heller wird."
        let out = ParakeetEngine.merge(text, replacements: [("hältst du davon?", "Claus"), ("dass die ein bisschen", "Claus"), ("heller", "Claus")],
                                       aliases: ["Claus": ["Klot", "Cloot"]])
        XCTAssertEqual(out, text)
    }

    func testOrdinaryWordsThatOnlyResembleTheTermStay() {
        let text = "Den haben wir, glaube ich, schon. Bleiben wir bei Blau?"
        let out = ParakeetEngine.merge(text, replacements: [("glaube", "Claus"), ("Blau?", "Claus")],
                                       aliases: ["Claus": ["Klod"]], isWord: { _ in true })
        XCTAssertEqual(out, text)
    }

    func testSingleRealWordThatOnlySoundsTheSameStays() {
        // Accepted limit: a misheard “Cloud” stays, so that names and ordinary words aren't swapped for terms.
        XCTAssertEqual(ParakeetEngine.merge("I asked Cloud to help.", replacements: [("Cloud", "Claus")], isWord: { _ in true }),
                       "I asked Cloud to help.")
        XCTAssertEqual(ParakeetEngine.merge("Claudia kommt heute etwas später.", replacements: [("Claudia", "Claus")], isWord: { _ in true }),
                       "Claudia kommt heute etwas später.")
        XCTAssertEqual(ParakeetEngine.merge("Sie studiert Jura in Hamburg.", replacements: [("Jura", "Jira")], isWord: { _ in true }),
                       "Sie studiert Jura in Hamburg.")
    }

    func testRealWordNextToPartOfTheTermIsReplaced() {
        XCTAssertEqual(ParakeetEngine.merge("Ich hab das gestern mit Claus Kot gebaut.", replacements: [("Claus Kot", "Claus Code")],
                                            isWord: { _ in true }),
                       "Ich hab das gestern mit Claus Code gebaut.")
    }

    func testMisheardNonWordIsReplaced() {
        let out = ParakeetEngine.merge("mit Klaas Design", replacements: [("Klaas", "Claus")], isWord: { _ in false })
        XCTAssertEqual(out, "mit Claus Design")
    }

    func testOrdinaryWordAfterAnArticleStays() {
        let text = "We store all backups in the cloud."
        XCTAssertEqual(ParakeetEngine.merge(text, replacements: [("cloud.", "Claus")], aliases: ["Claus": ["Klod"]], isWord: { _ in true }), text)
        // Listed as a spelling, it's replaced anyway.
        XCTAssertEqual(ParakeetEngine.merge(text, replacements: [("cloud.", "Claus")], aliases: ["Claus": ["cloud"]], isWord: { _ in true }),
                       "We store all backups in the Claus.")
    }

    func testTheAllowedOccurrenceIsReplaced() {
        let text = "We store all backups in the cloud. I asked Cloud to review the code."
        // “Cloud” listed as a spelling of Claus, so the replacement is allowed; the occurrence spelled exactly wins.
        XCTAssertEqual(ParakeetEngine.merge(text, replacements: [("Cloud", "Claus")], aliases: ["Claus": ["cloud"]], isWord: { _ in true }),
                       "We store all backups in the cloud. I asked Claus to review the code.")
    }

    func testTextPassLeavesSoundAlikeRealWords() {
        let entry = GlossaryEntry(term: "Vypo", soundsLike: ["vipo"])
        let text = "Das gibt dem Ganzen noch einen unfertigen Vibe."
        XCTAssertEqual(GlossaryCorrector.correct(text, entries: [entry], language: .de, strength: .normal, isWord: { _ in true }), text)
        XCTAssertEqual(GlossaryCorrector.correct("Ich nutze vipo.", entries: [entry], language: .de, strength: .normal, isWord: { _ in true }),
                       "Ich nutze Vypo.")
    }

    @MainActor
    func testSpellCheckerKnowsEverydayWords() {
        XCTAssertFalse(TermExtractor.spellCheckerUnknown("glaube"))
        XCTAssertFalse(TermExtractor.spellCheckerUnknown("Blau"))
        XCTAssertTrue(TermExtractor.spellCheckerUnknown("Klod"))
    }

    func testSimilarSpanIsStillReplaced() {
        let out = ParakeetEngine.merge("I asked Cloud to help.", replacements: [("Cloud", "Claus")])
        XCTAssertEqual(out, "I asked Claus to help.")
    }
}
