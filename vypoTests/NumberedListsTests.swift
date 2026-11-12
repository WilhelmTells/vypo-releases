import XCTest
@testable import vypo

/// Writing apps: ordinal words become a numbered list (`NumberedLists`, 0.6.0).
@MainActor
final class NumberedListsTests: XCTestCase {
    private func run(_ raw: String, _ lang: Lang = .de, mode: AppMode = .writing, on: Bool = true,
                     glossary: [GlossaryEntry] = [], spellings: [String] = [],
                     characters: [SpokenCharacter]? = SpokenCharacters.defaults) -> String {
        TextPipeline.process(raw, PipelineContext(language: lang, glossary: glossary, spellings: spellings, mode: mode,
                                                  spokenCharacters: characters, numberedLists: on))
            .replacingOccurrences(of: "\n", with: "⏎")
    }

    // MARK: Lists

    func testGermanList() {
        // As Parakeet writes it (`OrdinalASRProbeTests`): sentence ends often come out as commas.
        XCTAssertEqual(run("Erstens Milch, zweitens Eier, drittens Brot, viertens Butter."),
                       "1. Milch⏎2. Eier⏎3. Brot⏎4. Butter")
        XCTAssertEqual(run("Erstens, wir müssen pünktlich sein. Zweitens, wir bringen Kuchen mit."),
                       "1. Wir müssen pünktlich sein⏎2. Wir bringen Kuchen mit")
    }

    func testEnglishList() {
        XCTAssertEqual(run("First milk, second eggs, third bread.", .en), "1. Milk⏎2. Eggs⏎3. Bread")
        XCTAssertEqual(run("Firstly, we start early. Secondly, we bring lunch. Thirdly, we leave by six.", .en),
                       "1. We start early⏎2. We bring lunch⏎3. We leave by six")
    }

    func testAllTenGermanOrdinalsAndTheAsrSpellings() {
        let raw = "Erstens a, zweitens b, drittens c, viertens d, fünftens e, sechtens f, siebtens g, achtens h, neuntens i, zehntens j."
        XCTAssertEqual(run(raw), "1. A⏎2. B⏎3. C⏎4. D⏎5. E⏎6. F⏎7. G⏎8. H⏎9. I⏎10. J")
        XCTAssertEqual(run("Erstens a, zweitens b, drittens c, viertens d, fünftens e, sechstens f, siebentens g."),
                       "1. A⏎2. B⏎3. C⏎4. D⏎5. E⏎6. F⏎7. G")
    }

    func testAllTenEnglishOrdinals() {
        let raw = "First a, second b, third c, fourth d, fifth e, sixth f, seventh g, eighth h, ninth i, tenth j."
        XCTAssertEqual(run(raw, .en), "1. A⏎2. B⏎3. C⏎4. D⏎5. E⏎6. F⏎7. G⏎8. H⏎9. I⏎10. J")
        XCTAssertEqual(run("Fourthly x. Firstly a. Secondly b, thirdly c, fourthly d, fifthly e.", .en),
                       "Fourthly x.⏎1. A⏎2. B⏎3. C⏎4. D⏎5. E")
    }

    func testCaseAndAColonAfterTheOrdinal() {
        XCTAssertEqual(run("ERSTENS: Milch. zweitens: Eier"), "1. Milch⏎2. Eier")
        XCTAssertEqual(run("first milk, second eggs,", .en), "1. Milk⏎2. Eggs")
    }

    func testFirstOfAll() {
        XCTAssertEqual(run("First of all, we start early. Second, we bring lunch.", .en),
                       "1. We start early⏎2. We bring lunch")
    }

    // MARK: Intro

    func testIntroWithColon() {
        XCTAssertEqual(run("Einkaufsliste: erstens Milch, zweitens Eier."), "Einkaufsliste:⏎1. Milch⏎2. Eier")
    }

    func testIntroWithoutColonGetsOne() {
        XCTAssertEqual(run("Für den Einkauf, erstens Milch, zweitens Eier."), "Für den Einkauf:⏎1. Milch⏎2. Eier")
        XCTAssertEqual(run("We need three things. First milk, second eggs, third bread.", .en),
                       "We need three things.⏎1. Milk⏎2. Eggs⏎3. Bread")
        XCTAssertEqual(run("Wirklich? Erstens Milch, zweitens Eier."), "Wirklich?⏎1. Milch⏎2. Eier")
    }

    func testTextAfterTheLastItemStaysInIt() {
        XCTAssertEqual(run("Erstens Milch, zweitens Eier. Das war’s."), "1. Milch⏎2. Eier. Das war’s")
    }

    // MARK: Not a list

    func testALoneOrdinalStaysText() {
        XCTAssertEqual(run("First I went home.", .en), "First I went home.")
        XCTAssertEqual(run("Erstens war es zu laut."), "Erstens war es zu laut.")
    }

    func testASkippedOrdinalIsNoList() {
        XCTAssertEqual(run("First milk, third bread.", .en), "First milk, third bread.")
        XCTAssertEqual(run("Zweitens Eier, drittens Brot."), "Zweitens Eier, drittens Brot.")
    }

    func testAnOrdinalInTheMiddleOfASentenceDoesNotCount() {
        XCTAssertEqual(run("The second time I went there, first of all it was too loud.", .en),
                       "The second time I went there, first of all it was too loud.")
        XCTAssertEqual(run("Ich war zum zweiten Mal dort und erstens war es zu laut."),
                       "Ich war zum zweiten Mal dort und erstens war es zu laut.")
        XCTAssertEqual(run("I came first, second place went to Anna.", .en), "I came first, second place went to Anna.")
    }

    // MARK: Follow-up 12.11.: where an ordinal counts, connectors

    func testGermanOrdinalsCountAnywhere() {
        XCTAssertEqual(run("Ich brauche erstens Milch, zweitens Eier und drittens Brot"), "Ich brauche:⏎1. Milch⏎2. Eier⏎3. Brot")
        XCTAssertEqual(run("Das war erstens zu teuer und zweitens zu laut."), "Das war:⏎1. Zu teuer⏎2. Zu laut")
    }

    func testEnglishLyFormsCountAnywhere() {
        XCTAssertEqual(run("I need firstly milk, secondly eggs and thirdly bread", .en), "I need:⏎1. Milk⏎2. Eggs⏎3. Bread")
    }

    func testPlainEnglishOrdinalsAfterAndOrThen() {
        XCTAssertEqual(run("First milk, then second eggs and third bread", .en), "1. Milk⏎2. Eggs⏎3. Bread")
        XCTAssertEqual(run("First milk and then second eggs.", .en), "1. Milk⏎2. Eggs")
    }

    func testPlainEnglishOrdinalsAfterAWordDoNotCount() {
        XCTAssertEqual(run("I need first milk, second eggs.", .en), "I need first milk, second eggs.")
        XCTAssertEqual(run("the first time and the second time", .en), "the first time and the second time")
    }

    func testALoneGermanOrdinalStaysText() {
        XCTAssertEqual(run("Das war erstens zu teuer"), "Das war erstens zu teuer")
    }

    func testConnectorsInGerman() {
        XCTAssertEqual(run("Erstens Kaffee kochen, dann zweitens lesen, und dann drittens schreiben."),
                       "1. Kaffee kochen⏎2. Lesen⏎3. Schreiben")
    }

    func testAConnectorAtTheEndOfTheIntroGoes() {
        XCTAssertEqual(run("Ich war dort und erstens war es zu laut, zweitens zu voll."), "Ich war dort:⏎1. War es zu laut⏎2. Zu voll")
        XCTAssertEqual(run("Wir fangen an, und dann erstens Kaffee, zweitens Zeitung."), "Wir fangen an:⏎1. Kaffee⏎2. Zeitung")
        XCTAssertEqual(run("We start early, and firstly coffee, secondly the paper.", .en), "We start early:⏎1. Coffee⏎2. The paper")
        XCTAssertEqual(run("I went there and then first it was loud, second it was full.", .en),
                       "I went there:⏎1. It was loud⏎2. It was full")
        // Unchanged: no connector before the first ordinal.
        XCTAssertEqual(run("Das war erstens zu teuer und zweitens zu laut."), "Das war:⏎1. Zu teuer⏎2. Zu laut")
    }

    func testAConnectorInTheLastItemStays() {
        XCTAssertEqual(run("Erstens Milch, zweitens Eier und Brot"), "1. Milch⏎2. Eier und Brot")
    }

    func testOrdinalsAfterTheRunStayText() {
        XCTAssertEqual(run("First milk, second eggs, fourth butter.", .en), "1. Milk⏎2. Eggs, fourth butter")
    }

    func testAWordThatOnlyStartsLikeAnOrdinal() {
        XCTAssertEqual(run("Firstname Anna, second eggs.", .en), "Firstname Anna, second eggs.")
    }

    func testOtherLanguagesAreUntouched() {
        XCTAssertEqual(run("Premièrement le lait, deuxièmement les œufs.", .fr), "Premièrement le lait, deuxièmement les œufs.")
        XCTAssertEqual(run("First milk, second eggs.", .fr), "First milk, second eggs.")
    }

    // MARK: Items

    func testAnItemWithALowercaseGlossaryTermStaysLowercase() {
        let glossary = [GlossaryEntry(term: "vypo")]
        XCTAssertEqual(run("Erstens vypo installieren, zweitens diktieren.", glossary: glossary),
                       "1. vypo installieren⏎2. Diktieren")
        XCTAssertEqual(run("First macOS updates, second iPhone backups.", .en, spellings: ["macOS", "iPhone"]),
                       "1. macOS updates⏎2. iPhone backups")
    }

    func testAListAfterASpokenNewLine() {
        XCTAssertEqual(run("Einkauf neue Zeile erstens Milch Komma zweitens Eier"), "Einkauf:⏎1. Milch⏎2. Eier")
        XCTAssertEqual(run("Shopping new line first milk comma second eggs", .en), "Shopping:⏎1. Milk⏎2. Eggs")
    }

    func testFirstLineSecondLineIsAList() {
        // Follows the rules: “first” at the start, “second” after a line break. Seen in `WritingPunctuationTests`.
        XCTAssertEqual(run("First line new line second line", .en), "1. Line⏎2. Line")
    }

    func testSpokenPunktEndsItems() {
        XCTAssertEqual(run("Erstens Milch Punkt zweitens Eier Punkt"), "1. Milch⏎2. Eier")
    }

    func testTheLegacyLayoutToo() {
        XCTAssertEqual(run("Erstens Milch Punkt zweitens Eier Punkt", characters: nil), "1. Milch⏎2. Eier")
    }

    // MARK: Unchanged

    func testPromptAndStandardAppsAreUnchanged() {
        XCTAssertEqual(run("Erstens Milch, zweitens Eier.", mode: .prompt), "Erstens Milch, zweitens Eier")
        XCTAssertEqual(run("Erstens Milch, zweitens Eier.", mode: .standard), "Erstens Milch, zweitens Eier.")
        XCTAssertEqual(run("First milk, second eggs.", .en, mode: .standard), "First milk, second eggs.")
    }

    func testSwitchOffIsUnchanged() {
        XCTAssertEqual(run("Erstens Milch, zweitens Eier.", on: false), "Erstens Milch, zweitens Eier.")
    }

    func testSpokenPunktIsStillAPeriod() {
        XCTAssertEqual(run("Das ist gut Punkt"), "Das ist gut.")
        XCTAssertEqual(run("Punkt eins ist erledigt Punkt zwei auch"), run("Punkt eins ist erledigt Punkt zwei auch", on: false))
        XCTAssertFalse(run("Punkt eins ist erledigt Punkt zwei auch").contains("1. "))
    }

    // MARK: Default

    func testOnForANewInstallation() {
        let suite = "vypo.tests.lists.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        XCTAssertTrue(Preferences(defaults: UserDefaults(suiteName: suite)!).numberedLists)
    }

    func testOnForAnExistingInstallation() {
        // A Mac from before 0.6.0: other preferences stored, this one never.
        let suite = "vypo.tests.lists.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: DefaultsKey.typographicQuotes)
        defaults.set(WordsLayout.legacy.rawValue, forKey: DefaultsKey.wordsLayout)
        XCTAssertNil(defaults.persistentDomain(forName: suite)?[DefaultsKey.numberedLists])
        XCTAssertTrue(Preferences(defaults: defaults).numberedLists)
    }

    func testOffIsKept() {
        let suite = "vypo.tests.lists.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        Preferences(defaults: UserDefaults(suiteName: suite)!).numberedLists = false
        XCTAssertFalse(Preferences(defaults: UserDefaults(suiteName: suite)!).numberedLists)
    }

    // MARK: Smart spacing at paste time

    private func paste(_ text: String, before: String, after: Character? = nil, _ lang: Lang = .de) -> String {
        ContextFormatter.format(text, context: InsertionContext(before: before, after: after), language: lang, glossaryTerms: [])
            .replacingOccurrences(of: "\n", with: "⏎")
    }

    func testAListInTheMiddleOfALineGetsALineBreak() {
        XCTAssertEqual(paste("1. Milch\n2. Eier", before: "en"), "⏎1. Milch⏎2. Eier")
        XCTAssertEqual(paste("1. Milch\n2. Eier", before: ". "), "⏎1. Milch⏎2. Eier")
    }

    func testAListAtTheStartOrAfterALineBreakStaysAsItIs() {
        XCTAssertEqual(paste("1. Milch\n2. Eier", before: ""), "1. Milch⏎2. Eier")
        XCTAssertEqual(paste("1. Milch\n2. Eier", before: "x\n"), "1. Milch⏎2. Eier")
    }

    func testAListWithAnIntroKeepsTheUsualSpacing() {
        XCTAssertEqual(paste("Einkauf:\n1. Milch\n2. Eier", before: "t."), " Einkauf:⏎1. Milch⏎2. Eier")
    }
}
