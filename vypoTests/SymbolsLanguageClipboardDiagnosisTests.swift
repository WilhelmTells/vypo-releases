import AppKit
import XCTest
@testable import vypo

/// Diagnosis 2026-10-25: spoken symbols,
/// Cyrillic output with English and German chosen, the clipboard. Tests named `testRED_…` show a fault
/// and fail on purpose until it's fixed; the others pin down today's behaviour.
@MainActor
final class SymbolsLanguageClipboardDiagnosisTests: XCTestCase {
    /// The owner's symbol replacements as stored in `replacements.json` on 2026-10-25 (the glossary has no symbols).
    private let ownerSymbols = [
        Replacement(spoken: "Doppelpunkt", output: ":"),
        Replacement(spoken: "Semikolon, Semicolon", output: ";"),
        Replacement(spoken: "Slash", output: "/"),
        Replacement(spoken: "Dash", output: "-"),
    ]

    private var ownerReplacements: [Replacement] { Replacements.defaults + ownerSymbols }

    private func pipeline(_ raw: String, mode: AppMode = .standard, replacements: [Replacement]? = nil,
                          glossary: [GlossaryEntry] = []) -> String {
        TextPipeline.process(raw, PipelineContext(language: .de, glossary: glossary,
                                                  replacements: replacements ?? ownerReplacements, mode: mode))
    }

    // MARK: Part 2 – “Semikolon” (the entries, the migration and the symbol words: `ReplacementSymbolsTests`)

    func testVariantsAreSplitTrimmedAndDeduplicated() {
        XCTAssertEqual(Replacements.variants(" Semikolon ,Semicolon,, semikolon "), ["Semikolon", "Semicolon"])
        XCTAssertEqual(Replacements.variants("new line"), ["new line"])
        XCTAssertEqual(Replacements.variants(" , "), [])
    }

    /// H2: a glossary term made only of punctuation normalizes to "" and has no sound code.
    func testPunctuationOnlyTermHasNoNormalFormOrCode() {
        XCTAssertEqual(TextSimilarity.normalize(";"), "")
        XCTAssertEqual(DoubleMetaphone.primary(TextSimilarity.normalize(";")), "")
    }

    /// H2: such a term only ever matches through its Sounds-like spellings (exactly or fuzzily), and the
    /// symbol replaces the word with its spaces kept: “Wort ; weiter”.
    func testPunctuationOnlyGlossaryTerm() {
        let bare = [GlossaryEntry(term: ";")]
        XCTAssertEqual(GlossaryCorrector.correct("Wort Semikolon weiter", entries: bare, language: .de, strength: .normal), "Wort Semikolon weiter")
        let withAlias = [GlossaryEntry(term: ";", soundsLike: ["Semikolon"])]
        XCTAssertEqual(GlossaryCorrector.correct("Wort Semikolon weiter", entries: withAlias, language: .de, strength: .normal), "Wort ; weiter")
        XCTAssertEqual(GlossaryCorrector.correct("Semikolon.", entries: withAlias, language: .de, strength: .normal), ";.")
        // Fuzzy: one letter off is enough (similarity 0.89 ≥ 0.85), unlike Replacements.
        XCTAssertEqual(GlossaryCorrector.correct("Wort Semikolen weiter", entries: withAlias, language: .de, strength: .normal), "Wort ; weiter")
        XCTAssertEqual(GlossaryCorrector.correct("Wort Semikodon weiter", entries: withAlias, language: .de, strength: .normal), "Wort ; weiter")
    }

    /// H3: a typical glossary (Klaro, Vypo) doesn't take “Semikolon” before the replacements see it.
    func testOwnersGlossaryLeavesTheSymbolWordsAlone() {
        let glossary = [GlossaryEntry(term: "Klaro", soundsLike: ["Claro", "Klaru", "Klaroh"]),
                        GlossaryEntry(term: "Vypo", soundsLike: ["Waipo", "Viper"])]
        for word in ["Semikolon", "Semicolon", "Doppelpunkt", "Slash", "Dash", "Strich"] {
            XCTAssertEqual(GlossaryCorrector.correct(word, entries: glossary, language: .de, strength: .normal), word)
        }
    }

    /// H3: spoken punctuation knows “semikolon”, but only for apps set to Writing; since Fix 6 Prompt apps
    /// get the developer symbols (rule B), Default only a symbol word on its own (rule A).
    func testSpokenPunctuationAndSymbolsByMode() {
        XCTAssertEqual(pipeline("Wort Semikolon weiter", replacements: []), "Wort Semikolon weiter")
        XCTAssertEqual(pipeline("Wort Semikolon weiter", mode: .prompt, replacements: Replacements.defaults), "Wort; weiter")
        XCTAssertEqual(pipeline("Wort Semikolon weiter", mode: .writing, replacements: []), "Wort; weiter")
        // Writing has no slash (it is not punctuation); the Semi-Kolon spellings are in its table now.
        XCTAssertEqual(pipeline("Wort Slash weiter", mode: .writing, replacements: []), "Wort Slash weiter")
        XCTAssertEqual(pipeline("Wort Semi-Kolon weiter", mode: .writing, replacements: []), "Wort; weiter")
    }

    // MARK: Part 3 – Cyrillic with only Latin-script languages chosen

    /// The language guard needs 3 words, and even then the recognizer is unsure about nonsense Cyrillic
    /// (“юзо слэш влюм”: Russian 0.77 < 0.8): all seven Cyrillic dictations of 2026-10-25 were pasted.
    /// The script check (`isWrongScript`) is what stops them now.
    func testCyrillicPassesTheLanguageGuard() {
        let both: [Lang] = [.en, .de]
        for text in ["Слэш.", "Теж.", "юзо слэш влюм"] {
            XCTAssertFalse(LanguageRouter.isForeign(text, among: both), text)
        }
    }

    /// With English and German only, Cyrillic output is drift whatever its length.
    func testCyrillicIsWrongScriptWhenOnlyLatinLanguagesAreChosen() {
        let both: [Lang] = [.en, .de]
        for text in ["Слэш.", "Теж.", "юзо слэш влюм", "Hallo Слэш"] {
            XCTAssertTrue(LanguageRouter.isWrongScript(text, among: both), text)
        }
    }

    func testWrongScriptRespectsTheChosenLanguages() {
        XCTAssertFalse(LanguageRouter.isWrongScript("Слэш.", among: [.en, .ru]))
        XCTAssertTrue(LanguageRouter.isWrongScript("Слэш.", among: [.de, .el]))
        XCTAssertTrue(LanguageRouter.isWrongScript("Καλημέρα", among: [.en, .de]))
        XCTAssertFalse(LanguageRouter.isWrongScript("Καλημέρα", among: [.de, .el]))
        XCTAssertTrue(LanguageRouter.isWrongScript("Hello, hello", among: [.ru]))
    }

    /// Digits, punctuation, symbols, emoji and accented Latin letters are no wrong script.
    func testNoLettersOfAnotherScriptIsFine() {
        let both: [Lang] = [.en, .de]
        for text in ["Vypo 2.0 🙂", "12:30 – 14:00 / €5", "Größe, café, naïve, ß, Æsir", "→ ; ~ _ /", ""] {
            XCTAssertFalse(LanguageRouter.isWrongScript(text, among: both), text)
        }
        XCTAssertTrue(LanguageRouter.isWrongScript("你好", among: both), "no chosen language is written in Han")
    }

    /// Variant b): transliterate and match. ICU's Latin–Cyrillic transform gives Czech-style letters, and
    /// none of the results is close enough to “Slash” or “Dash” for an exact or a fuzzy match.
    func testTransliterationDoesntReachTheOwnersEntries() {
        let expected = ["Слэш": "Sléš", "Слеш": "Sleš", "Теж": "Tež", "Дэш": "Déš", "Даш": "Daš", "Колон": "Kolon"]
        for (cyrillic, latin) in expected {
            XCTAssertEqual(cyrillic.applyingTransform(.latinToCyrillic, reverse: true), latin, cyrillic)
            XCTAssertEqual(Replacements.apply(ownerReplacements, to: latin), latin, "no exact hit for \(latin)")
        }
        func plain(_ s: String) -> String {
            TextSimilarity.normalize(s.applyingTransform(.latinToCyrillic, reverse: true)!.applyingTransform(.stripDiacritics, reverse: false)!)
        }
        XCTAssertEqual(plain("Слэш"), "sles")
        XCTAssertEqual(TextSimilarity.similarity(plain("Слэш"), "slash"), 0.6, accuracy: 0.001)
        XCTAssertNotEqual(DoubleMetaphone.primary(plain("Слэш")), DoubleMetaphone.primary("slash"))
        XCTAssertLessThan(TextSimilarity.similarity(plain("Теж"), "dash"), 0.5)
        XCTAssertLessThan(TextSimilarity.similarity(plain("Дэш"), "dash"), CorrectionStrength.strong.threshold)
        // Only where the Cyrillic is the German word spelled out does it hit.
        XCTAssertEqual(Replacements.apply([Replacement(spoken: "Semikolon", output: ";")], to: plain("Семиколон")), ";")
    }

    // MARK: Part 4 – clipboard

    /// Reading the pasteboard doesn't change its change count, so vypo can't see from it that the app has pasted.
    func testReadingThePasteboardLeavesTheChangeCount() {
        let pb = NSPasteboard(name: .init("vypo.test.\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        pb.clearContents()
        pb.setString("dictated", forType: .string)
        let count = pb.changeCount
        _ = pb.string(forType: .string)
        XCTAssertEqual(pb.changeCount, count)
    }

    /// Superseded by Fix 5 (`ClipboardAfterReadTests`): the restore no longer fires before a slow app has read.
    func testRestoreWaitsForTheReadNotForAGuess() {
        let pb = NSPasteboard(name: .init("vypo.test.\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        pb.clearContents()
        pb.setString("before", forType: .string)
        let keeper = ClipboardKeeper(pasteboard: pb, policy: RestorePolicy(afterPaste: .milliseconds(20), afterRead: .milliseconds(20), timeout: .seconds(5), fallback: .milliseconds(20)))
        keeper.keep("dictated", restoreAfterPaste: true, paste: false)
        keeper.userPasted()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        // A slow app reading now still gets the dictation.
        XCTAssertEqual(pb.string(forType: .string), "dictated")
        keeper.settle()
    }

    /// A promised item (data provider) tells vypo when an app reads it: the provider is asked once, on the first read.
    /// This could replace the fixed 250 ms.
    func testPromisedItemSignalsTheRead() {
        final class Provider: NSObject, NSPasteboardItemDataProvider {
            var reads = 0
            func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
                reads += 1
                item.setString("dictated", forType: type)
            }
        }
        let pb = NSPasteboard(name: .init("vypo.test.\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        pb.clearContents()
        let provider = Provider()
        let item = NSPasteboardItem()
        item.setDataProvider(provider, forTypes: [.string])
        pb.writeObjects([item])
        XCTAssertEqual(provider.reads, 0)
        // Another process reads off the main thread; the provider answers on the main thread.
        let read = expectation(description: "read")
        nonisolated(unsafe) var value: String?
        DispatchQueue.global().async {
            value = pb.string(forType: .string)
            read.fulfill()
        }
        wait(for: [read], timeout: 2)
        XCTAssertEqual(value, "dictated")
        XCTAssertEqual(provider.reads, 1)
    }
}
