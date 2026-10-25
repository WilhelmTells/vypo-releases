import XCTest
@testable import vypo

final class GlossaryCorrectorTests: XCTestCase {
    private func fix(_ text: String, _ entries: [GlossaryEntry], _ lang: Lang = .en, _ strength: CorrectionStrength = .normal) -> String {
        GlossaryCorrector.correct(text, entries: entries, language: lang, strength: strength)
    }

    func testSoundsLikeMatch() {
        XCTAssertEqual(fix("deploy it on cooper netties", [GlossaryEntry(term: "Kubernetes", soundsLike: ["cooper netties"])]),
                       "deploy it on Kubernetes")
    }

    func testSoundsLikeKeepsPunctuation() {
        XCTAssertEqual(fix("I love swift you eye.", [GlossaryEntry(term: "SwiftUI", soundsLike: ["swift you eye"])]),
                       "I love SwiftUI.")
    }

    func testOrdinaryWordAfterArticleKeepsItsCase() {
        let words: Set<String> = ["cursor", "sprint"]
        let entries = [GlossaryEntry(term: "Cursor"), GlossaryEntry(term: "Sprint")]
        func fix(_ text: String) -> String {
            GlossaryCorrector.correct(text, entries: entries, language: .en, strength: .normal, isWord: words.contains)
        }
        XCTAssertEqual(fix("Move the cursor to the end of the line."), "Move the cursor to the end of the line.")
        XCTAssertEqual(fix("He won the sprint at the end of the race."), "He won the sprint at the end of the race.")
        XCTAssertEqual(fix("I opened it in cursor."), "I opened it in Cursor.")
    }

    func testCapitalizedNounAfterArticleIsStillCorrected() {
        XCTAssertEqual(GlossaryCorrector.correct("Schreib das bitte in die Readme.", entries: [GlossaryEntry(term: "README")],
                                                 language: .de, strength: .normal, isWord: { _ in true }),
                       "Schreib das bitte in die README.")
    }

    func testNonWordAfterArticleIsStillCorrected() {
        XCTAssertEqual(GlossaryCorrector.correct("Push it to the github repo.", entries: [GlossaryEntry(term: "GitHub")],
                                                 language: .en, strength: .normal, isWord: { _ in false }),
                       "Push it to the GitHub repo.")
    }

    func testSimilarityFixesCase() {
        XCTAssertEqual(fix("kubernetes", [GlossaryEntry(term: "Kubernetes")]), "Kubernetes")
    }

    func testPhoneticRule() {
        XCTAssertEqual(DoubleMetaphone.primary("coopernetties"), DoubleMetaphone.primary("Kubernetes"))
        let sim = TextSimilarity.similarity("coopernetties", "kubernetes")
        XCTAssertEqual(sim, 0.54, accuracy: 0.01)
        XCTAssertEqual(fix("deploy it on cooper netties", [GlossaryEntry(term: "Kubernetes")]), "deploy it on Kubernetes")
    }

    func testUnrelatedTextUnchanged() {
        XCTAssertEqual(fix("the cat sat", [GlossaryEntry(term: "Kubernetes")]), "the cat sat")
    }

    func testFewerThanThreeLettersUnchanged() {
        XCTAssertEqual(fix("a", [GlossaryEntry(term: "AI")]), "a")
    }

    func testScope() {
        let de = GlossaryEntry(term: "Kubernetes", soundsLike: ["cooper netties"], scope: .only(.de))
        XCTAssertEqual(fix("deploy it on cooper netties", [de], .en), "deploy it on cooper netties")
        XCTAssertEqual(fix("deploy it on cooper netties", [de], .de), "deploy it on Kubernetes")
    }

    func testCarefulRejectsWhatNormalAccepts() {
        // "swiftu" vs "swiftui": 1 − 1/7 ≈ 0.857
        let entry = GlossaryEntry(term: "SwiftUI")
        XCTAssertEqual(TextSimilarity.similarity("swiftu", "swiftui"), 0.857, accuracy: 0.001)
        XCTAssertEqual(fix("use swiftu here", [entry], .en, .normal), "use SwiftUI here")
        XCTAssertEqual(fix("use swiftu here", [entry], .en, .careful), "use swiftu here")
    }

    func testExactTermIsLeftAlone() {
        XCTAssertEqual(fix("Herbert Simon wrote", [GlossaryEntry(term: "Herbert Simon"), GlossaryEntry(term: "Simone")]),
                       "Herbert Simon wrote")
    }

    func testWhitespaceIsPreserved() {
        XCTAssertEqual(fix("one\ntwo  kubernetes", [GlossaryEntry(term: "Kubernetes")]), "one\ntwo  Kubernetes")
    }
}

final class DoubleMetaphoneTests: XCTestCase {
    func testCodes() {
        XCTAssertEqual(DoubleMetaphone.primary("Smith"), "SM0")
        XCTAssertEqual(DoubleMetaphone.primary("Schmidt"), "XMT")
        XCTAssertEqual(DoubleMetaphone.primary("Kubernetes"), "KPRNTS")
        XCTAssertEqual(DoubleMetaphone.primary("coopernetties"), "KPRNTS")
    }

    func testMaxLength() {
        XCTAssertLessThanOrEqual(DoubleMetaphone.primary("Containerisierung").count, 6)
    }
}

final class ReplacementTests: XCTestCase {
    func testNewLine() {
        XCTAssertEqual(Replacements.apply(Replacements.defaults, to: "first line new line second"), "first line\nsecond")
    }

    func testNewParagraphWithModelPunctuation() {
        XCTAssertEqual(Replacements.apply(Replacements.defaults, to: "new paragraph."), "\n\n")
    }

    func testDisabledIsSkipped() {
        var r = Replacements.defaults
        r[0].enabled = false
        XCTAssertEqual(Replacements.apply(r, to: "first line new line second"), "first line new line second")
    }

    func testCaseInsensitiveWholeWords() {
        let r = [Replacement(spoken: "brb", output: "be right back")]
        XCTAssertEqual(Replacements.apply(r, to: "BRB, see you"), "be right back see you")
        XCTAssertEqual(Replacements.apply(r, to: "brbx"), "brbx")
    }
}
