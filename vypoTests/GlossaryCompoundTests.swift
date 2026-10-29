import XCTest
@testable import vypo

/// Hyphen compounds and the term's own spelling (0.3.0). Made-up sentences; no real glossary.
final class GlossaryCompoundTests: XCTestCase {
    private let entries = [
        GlossaryEntry(term: "vypo", soundsLike: ["vipo"]),
        GlossaryEntry(term: "Final Cut", soundsLike: ["final cat"]),
        GlossaryEntry(term: "Logic Pro", soundsLike: ["logic bro"]),
        GlossaryEntry(term: "GitHub"),
        GlossaryEntry(term: "Stand-up"),
    ]
    /// Ordinary words of the made-up sentences, as the spell checker would say.
    private let words: Set<String> = ["cat", "bro", "session", "viper", "daten", "downloadseite", "app", "code", "design"]

    private func fix(_ text: String, _ lang: Lang = .de, entries: [GlossaryEntry]? = nil) -> String {
        GlossaryCorrector.correct(text, entries: entries ?? self.entries, language: lang, strength: .normal,
                                  isWord: { self.words.contains($0.lowercased()) })
    }

    func testPartOfAHyphenCompound() {
        XCTAssertEqual(fix("Ich habe die Vipo-App geöffnet."), "Ich habe die vypo-App geöffnet.")
        XCTAssertEqual(fix("Die Vipo-Releases sind da, die Vipo-Karte auch."), "Die vypo-Releases sind da, die vypo-Karte auch.")
    }

    func testMultiWordTermBeforeTheHyphen() {
        XCTAssertEqual(fix("Die andere Final Cat-Session läuft noch."), "Die andere Final Cut-Session läuft noch.")
        XCTAssertEqual(fix("Ich starte eine Logic Bro-Session."), "Ich starte eine Logic Pro-Session.")
    }

    func testTheOtherPartsAndTheHyphenStayAsTheyAre() {
        XCTAssertEqual(fix("Die VIPO-app (Vipo-Icon), dann Vipo-Ordner!"), "Die vypo-app (vypo-Icon), dann vypo-Ordner!")
        XCTAssertEqual(fix("Mein Final Cat-SESSION."), "Mein Final Cut-SESSION.")
    }

    func testTheTermAfterTheHyphen() {
        XCTAssertEqual(fix("Die App-Vipo läuft."), "Die App-vypo läuft.")
    }

    func testACompoundThatIsATermStaysWhole() {
        XCTAssertEqual(fix("Das Stand-up ist heute."), "Das Stand-up ist heute.")
        XCTAssertEqual(fix("Das stand-up ist heute."), "Das Stand-up ist heute.")
    }

    func testNegativesStayUnchanged() {
        XCTAssertEqual(fix("Wir nutzen eine Cat-Session."), "Wir nutzen eine Cat-Session.")
        XCTAssertEqual(fix("Die Daten liegen beim Bro."), "Die Daten liegen beim Bro.")
        XCTAssertEqual(fix("Das ist ein Viper."), "Das ist ein Viper.")
        XCTAssertEqual(fix("Das ist eine Pro-Version, kein Aus-Schalter."), "Das ist eine Pro-Version, kein Aus-Schalter.")
    }

    func testCanonicalSpellingWinsMidSentence() {
        XCTAssertEqual(fix("Das ist die Downloadseite vom Vypo."), "Das ist die Downloadseite vom vypo.")
        XCTAssertEqual(fix("Das Release über Vypo, VYPO und vypo."), "Das Release über vypo, vypo und vypo.")
        XCTAssertEqual(fix("push to github now", .en), "push to GitHub now")
        XCTAssertEqual(fix("Die Github-Seite.", .de), "Die GitHub-Seite.")
    }

    func testCanonicalSpellingForTheStartOfTheText() {
        XCTAssertEqual(fix("Vypo läuft."), "vypo läuft.")
    }

    func testNormalWordsAreNotTouched() {
        XCTAssertEqual(fix("Code und Design sind gut."), "Code und Design sind gut.")
        XCTAssertEqual(fix("Das ist eine Daten-Sache."), "Das ist eine Daten-Sache.")
    }

    // MARK: Smart capitalization at paste time

    private func paste(_ text: String, before: String, terms: Set<String> = ["vypo", "GitHub"]) -> String {
        ContextFormatter.format(text, context: InsertionContext(before: before, after: nil), language: .de, glossaryTerms: terms)
    }

    func testATermsOwnSpellingBeatsTheCapitalAtTheStartOfASentence() {
        XCTAssertEqual(paste("vypo läuft.", before: ""), "vypo läuft.")
        XCTAssertEqual(paste("vypo läuft.", before: "\n"), "vypo läuft.")
        XCTAssertEqual(paste("vypo-App läuft.", before: ""), "vypo-App läuft.")
        XCTAssertEqual(paste("vypo läuft.", before: "x."), " vypo läuft.")
        XCTAssertEqual(paste("vypo läuft.", before: ". "), "vypo läuft.")
    }

    func testOtherWordsStillGetTheCapitalAtTheStart() {
        XCTAssertEqual(paste("das läuft.", before: ""), "Das läuft.")
        XCTAssertEqual(paste("github läuft.", before: ""), "Github läuft.", "only a term that starts lowercase beats the capital")
        XCTAssertEqual(paste("GitHub läuft.", before: ""), "GitHub läuft.")
    }
}
