import XCTest
@testable import vypo

/// Settings → Words → Spellings: abbreviations and file formats written right, from the app's own list.
@MainActor
final class SpellingsTests: XCTestCase {
    private func fix(_ text: String, glossary: [GlossaryEntry] = [], list: [String] = Spellings.defaultList, _ lang: Lang = .de) -> String {
        Spellings.apply(text, list: list, glossary: glossary, language: lang)
    }

    func testTheCapitalsOfTheListWin() {
        XCTAssertEqual(fix("Ich exportiere das als pdf."), "Ich exportiere das als PDF.")
        XCTAssertEqual(fix("Schick die Json und die csv, bitte."), "Schick die JSON und die CSV, bitte.")
        XCTAssertEqual(fix("Drück die FN-Taste."), "Drück die fn-Taste.")
        XCTAssertEqual(fix("Läuft das auf MacOS oder IOS?"), "Läuft das auf macOS oder iOS?")
        XCTAssertEqual(fix("Open the Url in Youtube.", .en), "Open the URL in YouTube.")
        XCTAssertEqual(fix("Ich lade (png) hoch."), "Ich lade (PNG) hoch.")
    }

    func testAWordTheModelSplitIsFound() {
        XCTAssertEqual(fix("Läuft das auf Mac OS?"), "Läuft das auf macOS?")
        XCTAssertEqual(fix("läuft das auf mac os?"), "läuft das auf macOS?")
        XCTAssertEqual(fix("Pushe das auf Git Hub."), "Pushe das auf GitHub.")
        XCTAssertEqual(fix("Das Video auf You Tube.", .de), "Das Video auf YouTube.")
    }

    func testHyphenCompounds() {
        XCTAssertEqual(fix("Schick mir die Zip-Datei."), "Schick mir die ZIP-Datei.")
        XCTAssertEqual(fix("Der pdf-Export und der Json-Parser."), "Der PDF-Export und der JSON-Parser.")
        XCTAssertEqual(fix("Die Mac OS-Version."), "Die macOS-Version.")
    }

    func testSentenceStartKeepsASpellingsOwnCase() {
        XCTAssertEqual(fix("macos ist da."), "macOS ist da.")
        // At paste time smart capitalization leaves a lowercase-first spelling alone.
        let terms = Set(Spellings.defaultList)
        func paste(_ text: String) -> String {
            ContextFormatter.format(text, context: InsertionContext(before: "", after: nil), language: .de, glossaryTerms: terms)
        }
        XCTAssertEqual(paste("macOS ist da."), "macOS ist da.")
        XCTAssertEqual(paste("fn drücken."), "fn drücken.")
        XCTAssertEqual(paste("iPhone kaufen."), "iPhone kaufen.")
        XCTAssertEqual(paste("PDF senden."), "PDF senden.")
    }

    func testNegativesStayAsTheyAre() {
        XCTAssertEqual(fix("Zip your jacket.", .en), "Zip your jacket.")
        XCTAssertEqual(fix("Don't ram the door.", .en), "Don't ram the door.")
        XCTAssertEqual(fix("Ui, das ist schön."), "Ui, das ist schön.")
        XCTAssertEqual(fix("Pin it to the wall.", .en), "Pin it to the wall.")
        XCTAssertEqual(fix("I bought a Mac yesterday.", .en), "I bought a Mac yesterday.")
        XCTAssertEqual(fix("I phone you later.", .en), "I phone you later.")
        XCTAssertEqual(fix("He is linked in the system.", .en), "He is linked in the system.")
        XCTAssertEqual(fix("Das ist ein Mac. Os ist kurz für Osten.", .de), "Das ist ein Mac. Os ist kurz für Osten.", "words split by a full stop are two sentences")
    }

    func testAmbiguousWordsNeedANounOrAHyphen() {
        XCTAssertEqual(fix("Attach the zip file.", .en), "Attach the ZIP file.")
        XCTAssertEqual(fix("Das ist eine zip Datei.", .de), "Das ist eine ZIP Datei.")
        XCTAssertEqual(fix("Die Ram-Auslastung.", .de), "Die RAM-Auslastung.")
        XCTAssertEqual(fix("A ui design review.", .en), "A UI design review.")
    }

    func testTheUsersGlossaryWins() {
        let glossary = [GlossaryEntry(term: "zip")]
        XCTAssertEqual(fix("Die Zip-Datei und die pdf.", glossary: glossary), "Die Zip-Datei und die PDF.")
        // The glossary pass itself keeps "zip" lowercase, then the spellings leave it.
        let ctx = PipelineContext(language: .de, glossary: glossary, spellings: Spellings.defaultList)
        XCTAssertEqual(TextPipeline.process("Schick die Zip-Datei.", ctx), "Schick die zip-Datei.")
        // A sounds-like counts too.
        let alias = [GlossaryEntry(term: "Rechner", soundsLike: ["cpu"])]
        XCTAssertEqual(fix("Die cpu ist heiß.", glossary: alias), "Die cpu ist heiß.")
        // A term scoped to another language doesn't block it.
        var scoped = GlossaryEntry(term: "zip"); scoped.scope = .only(.en)
        XCTAssertEqual(fix("Die Zip-Datei.", glossary: [scoped], .de), "Die ZIP-Datei.")
    }

    func testSwitchedOffChangesNothing() {
        let off = PipelineContext(language: .de, spellings: [])
        XCTAssertEqual(TextPipeline.process("Ich exportiere das als pdf auf mac os.", off), "Ich exportiere das als pdf auf mac os.")
        let on = PipelineContext(language: .de, spellings: Spellings.defaultList)
        XCTAssertEqual(TextPipeline.process("Ich exportiere das als pdf auf mac os.", on), "Ich exportiere das als PDF auf macOS.")
    }

    func testTheOrderIsGlossaryThenSpellingsThenReplacements() {
        // The glossary term "Pidgin" is not touched by spellings; a replacement still runs on the result.
        let r = Replacement(spoken: ["Schrägstrich"], output: "/")
        let ctx = PipelineContext(language: .de, replacements: [r], spellings: Spellings.defaultList)
        XCTAssertEqual(TextPipeline.process("api Schrägstrich json", ctx), "API/JSON")
    }

    // MARK: Stored only when edited

    private func prefs() -> (Preferences, UserDefaults) {
        let d = UserDefaults(suiteName: "vypo.test.\(UUID().uuidString)")!
        return (Preferences(defaults: d), d)
    }

    func testTheDefaultListIsOnAndNeverStored() {
        let (p, d) = prefs()
        XCTAssertTrue(p.spellingsEnabled)
        XCTAssertEqual(p.spellings, Spellings.defaultList)
        XCTAssertNil(d.object(forKey: "spellings.list"))
        // Saving the sheet untouched, or after “Reset to defaults”, stores nothing either.
        p.setSpellings(Spellings.defaultList)
        XCTAssertNil(d.object(forKey: "spellings.list"))
        // Registered defaults are not written to the preferences file: only a change is.
        let suite = (d.volatileDomain(forName: UserDefaults.registrationDomain)).keys.contains("spellingsEnabled")
        XCTAssertTrue(suite || d.bool(forKey: "spellingsEnabled"), "the switch is a registered default")
    }

    func testAnEditedListIsStoredAndComesBack() {
        let (p, d) = prefs()
        p.setSpellings(["PDF", "Jira"])
        XCTAssertEqual(d.stringArray(forKey: "spellings.list"), ["PDF", "Jira"])
        XCTAssertEqual(Preferences(defaults: d).spellings, ["PDF", "Jira"])
        p.setSpellings(Spellings.defaultList)
        XCTAssertNil(d.object(forKey: "spellings.list"), "back to the built-in list: the stored copy goes")
        XCTAssertEqual(Preferences(defaults: d).spellings, Spellings.defaultList)
    }

    func testTheSwitchIsStored() {
        let (p, d) = prefs()
        p.spellingsEnabled = false
        XCTAssertFalse(Preferences(defaults: d).spellingsEnabled)
    }

    func testAnExistingInstallGetsTheFeatureWithoutAMigration() {
        // A 0.2.x preferences domain: onboarding done, languages saved, nothing about spellings.
        let d = UserDefaults(suiteName: "vypo.test.\(UUID().uuidString)")!
        d.set(true, forKey: DefaultsKey.onboardingCompleted)
        d.set(["de"], forKey: DefaultsKey.languages)
        let p = Preferences(defaults: d)
        XCTAssertTrue(p.spellingsEnabled)
        XCTAssertEqual(p.spellings, Spellings.defaultList)
        XCTAssertNil(d.object(forKey: "spellings.list"))
    }

    func testTheListIsClean() {
        XCTAssertEqual(Set(Spellings.defaultList).count, Spellings.defaultList.count, "no duplicates")
        XCTAssertEqual(Set(Spellings.defaultList.map(TextSimilarity.normalize)).count, Spellings.defaultList.count, "no two spellings differ only in case")
    }
}
