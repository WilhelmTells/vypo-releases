import XCTest
@testable import vypo

@MainActor
final class LanguageRouterTests: XCTestCase {
    func testDriftIntoAnotherLanguageIsCaught() {
        let both: [Lang] = [.en, .de]
        XCTAssertTrue(LanguageRouter.isForeign("Hvor er vi gætte, og hvad skal vi gøre nu?", among: both))
        // The real case from 2026-10-21.
        XCTAssertTrue(LanguageRouter.isForeign("Hvor er vi gætte", among: both))
        XCTAssertFalse(LanguageRouter.isForeign("Wo sind wir gerade, und was machen wir jetzt?", among: both))
        XCTAssertFalse(LanguageRouter.isForeign("Let's meet at five pm. Passt dir das?", among: both))
        XCTAssertFalse(LanguageRouter.isForeign("Ich habe das Deployment im Kubernetes Cluster neu gestartet.", among: both))
    }

    /// Nothing is lost silently: a dictation the filter keeps out of the field says it is in History
    /// (and says nothing about a language), unless History is off.
    @MainActor
    func testFilteredDictationShowsSavedToHistory() {
        XCTAssertTrue(LanguageRouter.isForeign("Hello, this is a test of the dictation.", among: [.de]))
        XCTAssertEqual(AppCoordinator.filteredPillMode(savedToHistory: true), .added(.savedToHistory))
        XCTAssertEqual(AppCoordinator.filteredPillMode(savedToHistory: false), .error(.notUnderstood))
        XCTAssertEqual(PillMode.added(.savedToHistory).accessibilityLabel, String(localized: "Saved to History"))
    }

    func testOneOrTwoWordsAreNeverForeign() {
        let both: [Lang] = [.en, .de]
        // The real cases from 2026-10-22: Czech and Catalan to the recognizer.
        XCTAssertFalse(LanguageRouter.isForeign("Vypo", among: both))
        XCTAssertFalse(LanguageRouter.isForeign("Hi", among: both))
        XCTAssertFalse(LanguageRouter.isForeign("Hi, Vypo.", among: both))
    }

    func testDetectsTheLanguageOfTheTranscript() {
        let both: [Lang] = [.en, .de]
        XCTAssertEqual(LanguageRouter.detect("Can you send me the report before the meeting tomorrow?", among: both, fallback: .de), .en)
        XCTAssertEqual(LanguageRouter.detect("Kannst du mir das Angebot vor dem Termin morgen schicken?", among: both, fallback: .en), .de)
        // German with English terms is still German.
        XCTAssertEqual(LanguageRouter.detect("Ich habe das Deployment im Kubernetes Cluster heute Morgen neu gestartet.", among: both, fallback: .en), .de)
    }

    func testFallsBackWhenItCannotTell() {
        XCTAssertEqual(LanguageRouter.detect("OK", among: [.en, .de], fallback: .de), .de)
        XCTAssertEqual(LanguageRouter.detect("Thank you", among: [.en, .de], fallback: .de), .de)
        XCTAssertEqual(LanguageRouter.detect("Guten Morgen", among: [.en], fallback: .en), .en)
    }

    func testEnglishAloneBlocksGerman() {
        let german = "Kannst du mir das Angebot vor dem Termin morgen schicken?"
        XCTAssertTrue(LanguageRouter.isForeign(german, among: [.en]))
        XCTAssertFalse(LanguageRouter.isForeign(german, among: [.en, .de]))
    }

    func testOneLanguageNeedsNoDetection() {
        XCTAssertEqual(LanguageRouter.detect("Kannst du mir das Angebot vor dem Termin morgen schicken?", among: [.en], fallback: .en), .en)
    }

    func testDetectsAmongChosenOnly() {
        let french = "Peux-tu m'envoyer le rapport avant la réunion de demain ?"
        XCTAssertEqual(LanguageRouter.detect(french, among: [.en, .fr], fallback: .en), .fr)
        XCTAssertNotEqual(LanguageRouter.detect(french, among: [.en, .de], fallback: .en), .fr)
    }

    /// The previous dictation's language may have been unchosen since.
    func testFallbackIgnoresUnchosenLast() {
        XCTAssertEqual(LanguageRouter.fallback(last: .de, chosen: [.en, .fr], preferred: ["fr-FR"]), .fr)
        XCTAssertEqual(LanguageRouter.fallback(last: .de, chosen: [.en, .de], preferred: []), .de)
        XCTAssertEqual(LanguageRouter.fallback(last: nil, chosen: [.it], preferred: ["en-US"]), .it)
    }

    /// Apple read this correctly transcribed Russian sentence as Ukrainian (0.99) in the round trip, 2026-10-23.
    func testNeighbourLanguagesDontBlockEachOther() {
        let russian = "Завтра утром я пришлю тебе отчёт о встрече."
        XCTAssertFalse(LanguageRouter.isForeign(russian, among: [.ru]))
        XCTAssertFalse(LanguageRouter.isForeign("Zajtra ráno ti pošlem správu zo stretnutia.", among: [.cs]))
        // Not neighbours: drift into Danish is still caught for German, Russian for English.
        XCTAssertTrue(LanguageRouter.isForeign("Hvor er vi gætte, og hvad skal vi gøre nu?", among: [.de]))
        XCTAssertTrue(LanguageRouter.isForeign(russian, among: [.en]))
    }
}

/// The script hint for Parakeet: the first chosen language decides which script it writes when several share one.
final class ScriptHintTests: XCTestCase {
    func testSharedScriptGivesTheFirstChosenLanguage() {
        XCTAssertEqual(LanguageRouter.scriptHint(for: [.de, .en]), .de)
        XCTAssertEqual(LanguageRouter.scriptHint(for: [.en]), .en)
        XCTAssertEqual(LanguageRouter.scriptHint(for: [.ru, .uk]), .ru)
        XCTAssertEqual(LanguageRouter.scriptHint(for: [.el]), .el)
    }

    func testMixedScriptsGiveNoHint() {
        XCTAssertNil(LanguageRouter.scriptHint(for: [.en, .ru]))
        XCTAssertNil(LanguageRouter.scriptHint(for: [.el, .de]))
        XCTAssertNil(LanguageRouter.scriptHint(for: []))
    }

    func testEveryLanguageMapsToFluidAudioWithTheSameScript() {
        for lang in Lang.allCases {
            let fluid = ParakeetEngine.fluidLanguage(lang)
            XCTAssertEqual(fluid.rawValue, lang.rawValue, lang.rawValue)
            switch fluid.script {
            case .latin: XCTAssertEqual(lang.script, .latin, lang.rawValue)
            case .cyrillic: XCTAssertEqual(lang.script, .cyrillic, lang.rawValue)
            case .greek: XCTAssertEqual(lang.script, .greek, lang.rawValue)
            }
        }
    }
}
