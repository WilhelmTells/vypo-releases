import AppKit
import XCTest
@testable import vypo

/// Filler words in every language: the built-in lists, removal, and what is stored.
@MainActor
final class FillerWordsTests: XCTestCase {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "vypo.fillers.\(UUID().uuidString)")! }

    // MARK: Built-in lists

    func testEveryListIsShortAndInTheLanguagesOwnLetters() {
        for lang in Lang.allCases where lang != .en && lang != .de {
            let words = FillerRemover.defaultWords(lang)
            XCTAssertLessThanOrEqual(words.count, lang == .nl ? 4 : 3, lang.rawValue)
            XCTAssertEqual(Set(words).count, words.count, lang.rawValue)
            for word in words {
                // Catches a Latin “e” typed into a Cyrillic list: it looks right and never matches.
                XCTAssertTrue(word.unicodeScalars.allSatisfy(lang.script.contains), "\(lang.rawValue): \(word)")
                XCTAssertEqual(word, word.lowercased(), "\(lang.rawValue): \(word)")
            }
        }
    }

    func testWordsTheBriefRuledOutStayOut() {
        XCTAssertFalse(FillerRemover.defaultWords(.it).contains("e"), "“and”")
        XCTAssertFalse(FillerRemover.defaultWords(.es).contains("eh"), "A tag question")
        XCTAssertFalse(FillerRemover.defaultWords(.pt).contains("é"), "“is”")
        XCTAssertFalse(FillerRemover.defaultWords(.es).contains("em"), "Removal ignores case, and “EM” is an abbreviation")
    }

    /// Known to the system dictionaries as interjections, read one by one (see the report). A checker can't tell an
    /// interjection from a normal word, so any new word it knows has to be looked at and added here.
    private static let reviewedInterjections: [Lang: Set<String>] = [
        .da: ["øh", "øhm", "hmm"], .es: ["mmm"], .fr: ["euh", "heu", "hum"], .hu: ["hmm"], .it: ["ehm", "uhm", "mmm"],
        .nl: ["uh", "eh", "ehm"], .pl: ["yyy", "eee", "hmm"], .pt: ["hum", "hmm"], .ru: ["ммм"], .sv: ["öh", "eh", "hmm"],
    ]

    private func known(_ word: String, _ lang: Lang) -> Bool {
        let code = lang == .pt ? "pt_PT" : lang.rawValue
        return NSSpellChecker.shared.checkSpelling(of: word, startingAt: 0, language: code, wrap: false,
                                                   inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound
    }

    /// Measured on macOS 26: Bulgarian, Croatian, Czech, Finnish, Greek, Romanian, Slovak and Ukrainian accept nonsense
    /// too, so the checker says nothing there. They are skipped by that same control, here and on any other Mac.
    func testNoBuiltInWordIsAnUnreviewedDictionaryWord() {
        for lang in Lang.allCases where lang != .en && lang != .de {
            let nonsense = lang.script == .latin ? "xqzvk" : lang.script == .greek ? "ξψζξ" : "щщщ"
            guard !known(nonsense, lang) else { continue }
            for word in FillerRemover.defaultWords(lang) where known(word, lang) {
                XCTAssertTrue(Self.reviewedInterjections[lang]?.contains(word) == true, "\(lang.rawValue): \(word)")
            }
        }
    }

    // MARK: Removal

    func testRemovalInFrench() {
        XCTAssertEqual(FillerRemover.remove("Euh, je pense que, hum, c'est bon", words: FillerRemover.defaultWords(.fr)),
                       "Je pense que, c'est bon")
    }

    func testRemovalInPolish() {
        XCTAssertEqual(FillerRemover.remove("Yyy, myślę, że, eee, to dobrze", words: FillerRemover.defaultWords(.pl)),
                       "Myślę, że, to dobrze")
    }

    func testAnEmptyListRemovesNothing() {
        let text = "Ovaj, mislim da je, hmm, dobro"
        XCTAssertEqual(FillerRemover.remove(text, words: FillerRemover.defaultWords(.hr)), text)
    }

    func testEveryBuiltInWordIsFoundBetweenWords() {
        for lang in Lang.allCases {
            for word in FillerRemover.defaultWords(lang) {
                XCTAssertEqual(FillerRemover.remove("Aa, \(word), bb", words: [word]), "Aa, bb", "\(lang.rawValue): \(word)")
                XCTAssertEqual(FillerRemover.remove("\(word.prefix(1).uppercased() + word.dropFirst()) aa", words: [word]), "Aa",
                               "\(lang.rawValue): \(word)")
            }
        }
    }

    // MARK: Storage

    func testUnchangedListsAreNotStored() {
        let d = defaults()
        let prefs = Preferences(defaults: d)
        for lang in Lang.allCases {
            XCTAssertEqual(prefs.fillerWords(for: lang), FillerRemover.defaultWords(lang))
            XCTAssertNil(d.object(forKey: DefaultsKey.fillerWords(lang)), lang.rawValue)
        }
    }

    func testAnEditIsStoredAndComesBack() {
        let d = defaults()
        Preferences(defaults: d).setFillerWords(["bah"], for: .fr)
        XCTAssertEqual(d.stringArray(forKey: "fillerWords.fr"), ["bah"])
        XCTAssertEqual(Preferences(defaults: d).fillerWords(for: .fr), ["bah"])
    }

    func testAnEditBackToTheBuiltInListIsRemoved() {
        let d = defaults()
        let prefs = Preferences(defaults: d)
        prefs.setFillerWords(["bah"], for: .fr)
        prefs.setFillerWords(FillerRemover.defaultWords(.fr), for: .fr)
        XCTAssertNil(d.object(forKey: "fillerWords.fr"))
        XCTAssertNil(prefs.fillerWordsEdited[.fr])
    }

    func testAnEmptiedListIsAnEdit() {
        let d = defaults()
        Preferences(defaults: d).setFillerWords([], for: .fr)
        XCTAssertEqual(Preferences(defaults: d).fillerWords(for: .fr), [])
    }

    func testWordsAddedToALanguageWithoutAListAreStored() {
        let d = defaults()
        let prefs = Preferences(defaults: d)
        prefs.setFillerWords(["ovaj"], for: .hr)
        XCTAssertEqual(Preferences(defaults: d).fillerWords(for: .hr), ["ovaj"])
        prefs.setFillerWords([], for: .hr)
        XCTAssertNil(d.object(forKey: "fillerWords.hr"))
    }

    func testOldStoredValuesLoad() {
        let d = defaults()
        d.set(["uh", "like"], forKey: "fillerWords.en")
        d.set(["halt"], forKey: "fillerWords.de")
        let prefs = Preferences(defaults: d)
        XCTAssertEqual(prefs.fillerWords(for: .en), ["uh", "like"])
        XCTAssertEqual(prefs.fillerWords(for: .de), ["halt"])
        XCTAssertEqual(d.stringArray(forKey: "fillerWords.en"), ["uh", "like"], "A real edit stays stored")
    }

    /// The old sheet's Save stored both lists even when unchanged. A later built-in word has to reach those users.
    func testAnOldStoredCopyOfTheBuiltInListIsDropped() {
        let d = defaults()
        d.set(FillerRemover.defaultWords(.en), forKey: "fillerWords.en")
        d.set(["halt"], forKey: "fillerWords.de")
        let prefs = Preferences(defaults: d)
        XCTAssertNil(d.object(forKey: "fillerWords.en"))
        XCTAssertEqual(prefs.fillerWords(for: .en), FillerRemover.defaultWords(.en))
        XCTAssertEqual(prefs.fillerWords(for: .de), ["halt"])
    }

    // MARK: The Words pane's description

    func testThePaneDescriptionComesFromTheChosenLanguages() {
        let prefs = Preferences(defaults: defaults())
        prefs.languages = [.en, .de]
        XCTAssertEqual(prefs.fillerPreview, "uh, um, äh, ähm …")
        prefs.languages = [.en, .de, .fr]
        XCTAssertEqual(prefs.fillerPreview, "uh, äh, euh …")
        prefs.languages = [.hr]
        XCTAssertNil(prefs.fillerPreview)
        prefs.setFillerWords(["ovaj"], for: .hr)
        XCTAssertEqual(prefs.fillerPreview, "ovaj …")
    }
}
