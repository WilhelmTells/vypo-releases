import XCTest
@testable import vypo

/// The filter with the Mac's real spelling dictionaries, for English and German.
@MainActor
final class CorrectionFilterTests: XCTestCase {
    private func filter(terms: Set<String> = []) -> CorrectionFilter {
        CorrectionFilter(languages: [.en, .de], isGlossaryTerm: { terms.contains($0) })
    }

    private func pairs(_ old: String, _ new: String, continues: Bool = false, terms: Set<String> = []) -> [String] {
        filter(terms: terms).accepted(from: old, to: new, continuesSentence: continues).map { "\($0.heard) → \($0.term)" }
    }

    /// For tests whose expected result needs German. The filter drops a language whose spell checker doesn't reject
    /// nonsense, so this asks the filter and not the spell checker, and a Mac without German can still run the tests.
    /// “Hauses” is German only: with no German left, English decides, and it counts as unknown.
    private func skipWithoutGerman() throws {
        try XCTSkipIf(CorrectionFilter.unknownWord(in: [.de])("Hauses"),
                      "The spell checker has no usable German right now (not on this Mac, or still starting), so ordinary German words can't be told from terms.")
    }

    // MARK: The table of the brief

    func testAMisheardNameIsLearnt() {
        XCTAssertEqual(pairs("Wir nutzen cooper netties heute", "Wir nutzen Kubernetes heute"), ["cooper netties → Kubernetes"])
    }

    func testACaseChangeInsideASentenceIsLearnt() {
        XCTAssertEqual(pairs("Ich mag Vypo sehr", "Ich mag vypo sehr"), ["Vypo → vypo"])
    }

    func testOrdinaryWordsAreNotLearnt() throws {
        try skipWithoutGerman()
        for (old, new) in [("mit dem Hund", "mit den Hund"), ("Die Kinder ist da", "Die Kinder sind da"),
                           ("wegen des Haus heute", "wegen des Hauses heute"), ("ich gehe nach Hause", "ich gehen nach Hause"),
                           ("ich glaube das es geht", "ich glaube dass es geht"), ("das war gut heute", "das war toll heute")] {
            XCTAssertEqual(pairs(old, new), [], "\(old) → \(new)")
        }
    }

    func testAnOrdinaryWordSwapIsAnAcceptedLoss() {
        XCTAssertEqual(pairs("schick mir eine Mehl bitte", "schick mir eine Mail bitte"), [])
    }

    func testAMisheardWordThatIsNoWordLearnsANameTheDictionaryKnows() {
        XCTAssertEqual(pairs("Wir nutzen Kubernetis heute", "Wir nutzen Kubernetes heute"), ["Kubernetis → Kubernetes"])
    }

    /// The en dictionary holds “Hund”, “Stadt”, “Montag” and more like names (measured: 15 of 110 common German words).
    func testAnOrdinaryWordCorrectedToAWordLikeANameIsNotLearnt() throws {
        try skipWithoutGerman()
        XCTAssertEqual(pairs("mein Hunt schläft heute", "mein Hund schläft heute"), [])
        XCTAssertEqual(pairs("in der statt heute", "in der Stadt heute"), [])
        XCTAssertEqual(pairs("am Monntagg früh", "am Montag früh").count, 1, "a word that is no word still counts")
    }

    func testACaseChangeAtTheStartIsGrammar() {
        XCTAssertEqual(pairs("hallo zusammen", "Hallo zusammen"), [])
    }

    func testACaseChangeAfterAPeriodIsGrammar() {
        XCTAssertEqual(pairs("Das geht. hallo zusammen", "Das geht. Hallo zusammen"), [])
    }

    func testACaseChangeAfterALineBreakIsGrammar() {
        XCTAssertEqual(pairs("Liebe Lena\nhallo zusammen", "Liebe Lena\nHallo zusammen"), [])
    }

    func testAFirstWordInsideASentenceOfTheFieldCounts() {
        XCTAssertEqual(pairs("Vypo ist gut", "vypo ist gut", continues: true), ["Vypo → vypo"])
    }

    func testNumbersAreNotLearnt() {
        XCTAssertEqual(pairs("wir sind zwanzig Leute", "wir sind 20 Leute"), [])
        XCTAssertEqual(pairs("wir sind 20 Leute", "wir sind 21 Leute"), [])
    }

    func testATermAlreadyInTheGlossaryIsNotLearnt() {
        XCTAssertEqual(pairs("Wir nutzen cooper netties heute", "Wir nutzen Kubernetes heute", terms: ["Kubernetes"]), [])
    }

    func testAChangeOfContentIsNoCorrection() {
        XCTAssertEqual(pairs("Wir nutzen Kubernetes heute", "Wir nutzen Docker heute"), [])
    }

    func testMixedCaseCountsAsATermEvenIfTheDictionaryKnowsIt() {
        XCTAssertEqual(pairs("Das liegt auf git hub heute", "Das liegt auf GitHub heute"), ["git hub → GitHub"])
    }

    // MARK: Languages

    func testALanguageWithoutARealDictionaryDoesNotHideTerms() {
        let unknown = CorrectionFilter.unknownWord(in: [.fi, .en])
        XCTAssertTrue(unknown("Qzxvbnkt"), "Finnish accepts anything here, so it must not count")
        let onlyFinnish = CorrectionFilter.unknownWord(in: [.fi])
        XCTAssertTrue(onlyFinnish("Qzxvbnkt"), "with no dictionary to trust, English decides")
    }

    func testAYesIsKeptAndNotAskedAgain() {
        var usable: Set<String> = [], asked = 0
        for _ in 0..<3 {
            XCTAssertTrue(CorrectionFilter.rejectsNonsense("de", usable: &usable) { _, _ in asked += 1; return true })
        }
        XCTAssertEqual(asked, 1)
        XCTAssertEqual(usable, ["de"])
    }

    func testANoIsAskedAgainEveryTime() {
        var usable: Set<String> = [], asked = 0
        for _ in 0..<3 {
            XCTAssertFalse(CorrectionFilter.rejectsNonsense("fi", usable: &usable) { _, _ in asked += 1; return false })
        }
        XCTAssertEqual(asked, 3)
        XCTAssertEqual(usable, [])
    }

    func testAWrongNoFromAColdStartDoesNotStick() {
        var usable: Set<String> = []
        XCTAssertFalse(CorrectionFilter.rejectsNonsense("de", usable: &usable) { _, _ in false }, "the service is still starting")
        XCTAssertTrue(CorrectionFilter.rejectsNonsense("de", usable: &usable) { _, _ in true }, "the next correction asks again")
        XCTAssertTrue(CorrectionFilter.rejectsNonsense("de", usable: &usable) { _, _ in false }, "a yes stays")
    }

    func testAWordOfAnyChosenLanguageIsOrdinary() {
        let unknown = CorrectionFilter.unknownWord(in: [.en, .de])
        XCTAssertFalse(unknown("Hund"))
        XCTAssertFalse(unknown("house"))
    }
}

final class SoundsAlikeTests: XCTestCase {
    func testMisheardNames() {
        XCTAssertTrue(CorrectionFilter.soundsAlike("cooper netties", "Kubernetes"))
        XCTAssertTrue(CorrectionFilter.soundsAlike("jam f", "Jamf"))
        XCTAssertTrue(CorrectionFilter.soundsAlike("viper", "Vypo"))
    }

    func testDifferentWords() {
        XCTAssertFalse(CorrectionFilter.soundsAlike("Kubernetes", "Docker"))
        XCTAssertFalse(CorrectionFilter.soundsAlike("Montag", "Freitag und Samstag"))
    }
}

final class ContinuesSentenceTests: XCTestCase {
    func testInsideASentence() {
        XCTAssertTrue(CorrectionLearner.continuesSentence(InsertionContext(before: "er ", after: nil)))
        XCTAssertTrue(CorrectionLearner.continuesSentence(InsertionContext(before: "a,", after: nil)))
    }

    func testAtTheStartOfASentence() {
        XCTAssertFalse(CorrectionLearner.continuesSentence(nil))
        XCTAssertFalse(CorrectionLearner.continuesSentence(InsertionContext(before: "", after: nil)))
        XCTAssertFalse(CorrectionLearner.continuesSentence(InsertionContext(before: ". ", after: nil)))
        XCTAssertFalse(CorrectionLearner.continuesSentence(InsertionContext(before: "a\n", after: nil)))
    }
}

final class TrackedSegmentTests: XCTestCase {
    private let pasted = "Wir nutzen cooper netties heute im Team"

    private func tracked(_ value: String, caret: Int? = nil) -> TrackedSegment? {
        TrackedSegment(pasted: pasted, in: value, caret: caret)
    }

    func testFindsThePaste() {
        let s = tracked("Hallo. \(pasted) Tschüss")
        XCTAssertEqual(s?.text, pasted)
        XCTAssertEqual(s?.location, 7)
    }

    func testFindsTheOneAtTheCaretWhenItIsThereTwice() {
        let value = "\(pasted) und \(pasted)"
        XCTAssertEqual(tracked(value, caret: (value as NSString).length)?.location, (pasted as NSString).length + 5)
        XCTAssertEqual(tracked(value, caret: (pasted as NSString).length)?.location, 0)
    }

    func testFindsThePasteAcrossAWrappedLine() {
        XCTAssertEqual(tracked("Wir nutzen cooper\nnetties heute im Team")?.text, "Wir nutzen cooper\nnetties heute im Team")
    }

    func testNotThereIsNil() {
        XCTAssertNil(tracked("Etwas ganz anderes steht hier"))
    }

    func testTextTypedBeforeItMovesIt() {
        var s = tracked(pasted)!
        XCTAssertTrue(s.update("Hey! \(pasted)"))
        XCTAssertEqual(s.text, pasted)
        XCTAssertEqual(s.location, 5)
    }

    func testTextTypedAfterItChangesNothing() {
        var s = tracked(pasted)!
        XCTAssertTrue(s.update("\(pasted) und mehr"))
        XCTAssertEqual(s.text, pasted)
        XCTAssertEqual(s.location, 0)
    }

    func testAWordChanged() {
        var s = tracked("Hallo. \(pasted) Tschüss")!
        XCTAssertTrue(s.update("Hallo. Wir nutzen Kubernetes heute im Team Tschüss"))
        XCTAssertEqual(s.text, "Wir nutzen Kubernetes heute im Team")
    }

    func testAWordChangedKeyByKey() {
        var s = tracked("Hallo. \(pasted) Tschüss")!
        var partial = ""
        XCTAssertTrue(s.update("Hallo. Wir nutzen  heute im Team Tschüss"))
        for ch in "Kubernetes" {
            partial.append(ch)
            XCTAssertTrue(s.update("Hallo. Wir nutzen \(partial) heute im Team Tschüss"), partial)
        }
        XCTAssertEqual(s.text, "Wir nutzen Kubernetes heute im Team")
    }

    func testTheFirstWordChangedDoesNotTakeTheWordBefore() {
        var s = TrackedSegment(pasted: "cooper netties heute im Team", in: "Hallo Welt. cooper netties heute im Team", caret: nil)!
        XCTAssertTrue(s.update("Hallo Welt. Kubernetes heute im Team"))
        XCTAssertEqual(s.text, "Kubernetes heute im Team")
    }

    func testTheLastWordChanged() {
        var s = TrackedSegment(pasted: "wir nutzen heute cooper netties", in: "wir nutzen heute cooper netties. Danke", caret: nil)!
        XCTAssertTrue(s.update("wir nutzen heute Kubernetes. Danke"))
        XCTAssertEqual(s.text, "wir nutzen heute Kubernetes")
    }

    func testADoubledFirstLetterStaysInside() {
        var s = TrackedSegment(pasted: "k ist gut heute", in: "k ist gut heute", caret: nil)!
        XCTAssertTrue(s.update("kk ist gut heute"))
        XCTAssertEqual(s.text, "kk ist gut heute")
    }

    func testCaseChanged() {
        var s = TrackedSegment(pasted: "Ich mag Vypo sehr", in: "Ich mag Vypo sehr", caret: nil)!
        XCTAssertTrue(s.update("Ich mag vypo sehr"))
        XCTAssertEqual(s.text, "Ich mag vypo sehr")
    }

    func testCorrectionThenTextBefore() {
        var s = tracked(pasted)!
        XCTAssertTrue(s.update("Wir nutzen Kubernetes heute im Team"))
        XCTAssertTrue(s.update("Hey! Wir nutzen Kubernetes heute im Team"))
        XCTAssertEqual(s.text, "Wir nutzen Kubernetes heute im Team")
    }

    func testALongTextBeforeItDeleted() {
        var s = TrackedSegment(pasted: "ein kurzer Satz", in: "Ein sehr langer Text steht ganz am Anfang davor. ein kurzer Satz", caret: nil)!
        XCTAssertTrue(s.update("ein kurzer Satz"))
        XCTAssertEqual(s.location, 0)
        XCTAssertEqual(s.text, "ein kurzer Satz")
    }

    func testRewrittenIsLostAndKeepsTheLastVersion() {
        var s = tracked(pasted)!
        XCTAssertTrue(s.update("Wir nutzen Kubernetes heute im Team"))
        XCTAssertFalse(s.update("Ganz etwas anderes steht jetzt da und zwar lang"))
        XCTAssertEqual(s.text, "Wir nutzen Kubernetes heute im Team")
    }

    func testEmptiedByReturnKeepsTheLastVersion() {
        var s = tracked(pasted)!
        XCTAssertTrue(s.update("Wir nutzen Kubernetes heute im Team"))
        XCTAssertFalse(s.update(""))
        XCTAssertEqual(s.text, "Wir nutzen Kubernetes heute im Team")
    }

    // MARK: One or two words

    /// Types `text` one letter at a time between `before` and `after`, the way the app reports it.
    private func type(_ text: String, into s: inout TrackedSegment, before: String = "", after: String = "",
                      file: StaticString = #filePath, line: UInt = #line) {
        var partial = ""
        for ch in text {
            partial.append(ch)
            XCTAssertTrue(s.update(before + partial + after), "lost at “\(partial)”", file: file, line: line)
            XCTAssertEqual(s.text, partial, file: file, line: line)
        }
    }

    func testAOneWordPasteSelectedAndRetypedLetterByLetter() {
        var s = TrackedSegment(pasted: "Kubernetes", in: "Kubernetes", caret: nil)!
        type("Zwiebelix", into: &s)
    }

    func testAOneWordPasteRetypedInsideASentence() {
        let (before, after) = ("Morgen treffe ich Frau ", " im Büro.")
        var s = TrackedSegment(pasted: "Zwiebels", in: before + "Zwiebels" + after, caret: nil)!
        type("Zwiebelix", into: &s, before: before, after: after)
        XCTAssertEqual(s.location, (before as NSString).length)
    }

    func testARetypedWordThatStartsLikeTheOldOne() {
        var s = TrackedSegment(pasted: "Zwiebels", in: "Hallo Zwiebels", caret: nil)!
        type("Zwiebelix", into: &s, before: "Hallo ")
    }

    func testOneWordLettersEdited() {
        var s = TrackedSegment(pasted: "Zwiebelics", in: "Zwiebelics", caret: nil)!
        for value in ["Zwiebelic", "Zwiebeli", "Zwiebelix"] {
            XCTAssertTrue(s.update(value), value)
            XCTAssertEqual(s.text, value)
        }
    }

    func testOneWordDeletedBackwardsAndRetyped() {
        var s = TrackedSegment(pasted: "Abc", in: "Abc", caret: nil)!
        for value in ["Ab", "A", ""] { XCTAssertTrue(s.update(value), value) }
        XCTAssertEqual(s.text, "")
        type("Xyz", into: &s)
    }

    func testOneWordDeletedBackwardsInsideASentenceAndRetyped() {
        var s = TrackedSegment(pasted: "ab", in: "Hallo ab Welt", caret: nil)!
        for value in ["Hallo a Welt", "Hallo  Welt"] { XCTAssertTrue(s.update(value), value) }
        type("xy", into: &s, before: "Hallo ", after: " Welt")
    }

    func testTheFirstLetterRetyped() {
        var s = TrackedSegment(pasted: "Zwiebels", in: "Hallo Zwiebels", caret: nil)!
        XCTAssertTrue(s.update("Hallo wiebels"))
        XCTAssertTrue(s.update("Hallo Swiebels"))
        XCTAssertEqual(s.text, "Swiebels")
    }

    func testATwoWordPasteWithBothWordsChanged() {
        var s = TrackedSegment(pasted: "cooper netties", in: "cooper netties", caret: nil)!
        type("Kubernetes", into: &s)
    }

    func testAShortPasteStillEndsWithAChatsReturn() {
        var s = TrackedSegment(pasted: "Kubernetes", in: "Kubernetes", caret: nil)!
        XCTAssertTrue(s.update("Kubernetis"))
        XCTAssertFalse(s.update(""))
        XCTAssertEqual(s.text, "Kubernetis")
    }

    func testTextTypedAfterAShortPasteIsNotPartOfIt() {
        var s = TrackedSegment(pasted: "Kubernetes", in: "Kubernetes", caret: nil)!
        XCTAssertTrue(s.update("Kubernetes "))
        XCTAssertTrue(s.update("Kubernetes und"))
        XCTAssertTrue(s.update("Kubernetes, und"))
        XCTAssertEqual(s.text, "Kubernetes")
    }

    func testThreeWordsAreNoShortPaste() {
        var s = TrackedSegment(pasted: "eins zwei drei", in: "eins zwei drei", caret: nil)!
        XCTAssertFalse(s.update("vier"))
    }

    func testTheLastWordOfALongPasteRetyped() {
        var s = TrackedSegment(pasted: "wir nutzen heute Kubernetis", in: "wir nutzen heute Kubernetis", caret: nil)!
        XCTAssertTrue(s.update("wir nutzen heute "))
        var partial = "wir nutzen heute "
        for ch in "Kubernetes" {
            partial.append(ch)
            XCTAssertTrue(s.update(partial))
        }
        XCTAssertEqual(s.text, "wir nutzen heute Kubernetes")
    }

    func testEmoji() {
        var s = TrackedSegment(pasted: "Wir 😀 nutzen cooper netties heute", in: "😀😀 Wir 😀 nutzen cooper netties heute", caret: nil)!
        XCTAssertTrue(s.update("😀😀 Wir 😀 nutzen Kubernetes heute"))
        XCTAssertEqual(s.text, "Wir 😀 nutzen Kubernetes heute")
    }
}

@MainActor
final class GlossaryLearningTests: XCTestCase {
    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private var store: GlossaryStore { GlossaryStore(store: Store(directory: dir)) }

    func testOneCorrectionInAnAppStaysHidden() {
        let g = store
        g.suggest(heard: "cooper netties", term: "Kubernetes", scope: .all, source: .app)
        XCTAssertTrue(g.visibleSuggestions.isEmpty)
    }

    func testTwoCorrectionsInAnAppShow() {
        let g = store
        g.suggest(heard: "cooper netties", term: "Kubernetes", scope: .all, source: .app)
        g.suggest(heard: "Cooper netties", term: "Kubernetes", scope: .all, source: .app)
        XCTAssertEqual(g.visibleSuggestions.map(\.count), [2])
    }

    func testAHistoryFixShowsAtOnce() {
        let g = store
        g.suggest(heard: "cooper netties", term: "Kubernetes", scope: .all, source: .history)
        XCTAssertEqual(g.visibleSuggestions.count, 1)
    }

    func testHistoryAndAppsAddUp() {
        let g = store
        g.suggest(heard: "cooper netties", term: "Kubernetes", scope: .all, source: .app)
        g.suggest(heard: "cooper netties", term: "Kubernetes", scope: .all, source: .history)
        XCTAssertEqual(g.visibleSuggestions.map(\.count), [2])
    }

    func testCaseOfTheTermKeepsPairsApart() {
        let g = store
        g.suggest(heard: "Vypo", term: "vypo", scope: .all, source: .app)
        g.suggest(heard: "Vypo", term: "VYPO", scope: .all, source: .app)
        XCTAssertTrue(g.visibleSuggestions.isEmpty)
    }

    func testAnIgnoredPairNeverComesBack() {
        let g = store
        g.suggest(heard: "cooper netties", term: "Kubernetes", scope: .all, source: .history)
        g.ignore(g.visibleSuggestions[0])
        XCTAssertNil(g.suggest(heard: "Cooper Netties", term: "Kubernetes", scope: .all, source: .history))
        XCTAssertNil(store.suggest(heard: "cooper netties", term: "Kubernetes", scope: .all, source: .app), "after a restart too")
        XCTAssertTrue(store.suggestions.isEmpty)
    }

    func testAnIgnoredPairKeepsTheCaseOfItsTerm() {
        let g = store
        g.suggest(heard: "Vypo", term: "vypo", scope: .all, source: .history)
        g.ignore(g.visibleSuggestions[0])
        XCTAssertNotNil(g.suggest(heard: "Vypo", term: "VYPO", scope: .all, source: .history))
    }

    func testAcceptingIsNotIgnoring() {
        let g = store
        g.suggest(heard: "cooper netties", term: "Kubernetes", scope: .all, source: .history)
        g.accept(g.visibleSuggestions[0])
        XCTAssertTrue(g.contains(term: "Kubernetes"))
        g.delete(g.entries[0].id)
        XCTAssertNotNil(g.suggest(heard: "cooper netties", term: "Kubernetes", scope: .all, source: .history))
    }

    // MARK: One suggestion per term

    /// Three watches, each with a filter of its own, the way `CorrectionLearner` runs them.
    private func correct(_ g: GlossaryStore, _ hearings: [String], to term: String, source: GlossarySuggestion.Source = .app) {
        let filter = CorrectionFilter(languages: [.en, .de], isGlossaryTerm: g.contains(term:))
        for heard in hearings {
            g.learn(from: filter.accepted(from: "Morgen treffe ich Frau \(heard) im Büro.", to: "Morgen treffe ich Frau \(term) im Büro.",
                                          continuesSentence: false), scope: .only(.de), source: source)
        }
    }

    func testThreeHearingsOfOneNameBecomeOneSuggestion() {
        let g = store
        correct(g, ["Zwiebels"], to: "Zwiebelix")
        XCTAssertTrue(g.visibleSuggestions.isEmpty)
        correct(g, ["Zwiebelics", "Zwiebeliks"], to: "Zwiebelix")
        XCTAssertEqual(g.visibleSuggestions.count, 1)
        XCTAssertEqual(g.visibleSuggestions[0].spellings, ["Zwiebels", "Zwiebelics", "Zwiebeliks"])
        XCTAssertEqual(g.visibleSuggestions[0].count, 3)
        XCTAssertTrue(g.hasUnseenSuggestions)
    }

    func testSpellingsAreUniqueInAnyCaseAndStillCount() {
        let g = store
        for heard in ["Zwiebels", "zwiebels", "ZWIEBELS"] { g.suggest(heard: heard, term: "Zwiebelix", scope: .all, source: .app) }
        XCTAssertEqual(g.visibleSuggestions[0].spellings, ["Zwiebels"])
        XCTAssertEqual(g.visibleSuggestions[0].count, 3)
    }

    func testTheCaseOfTheTermKeepsSuggestionsApart() {
        let g = store
        g.suggest(heard: "viper", term: "vypo", scope: .all, source: .app)
        g.suggest(heard: "wiper", term: "VYPO", scope: .all, source: .app)
        XCTAssertEqual(g.suggestions.count, 2)
    }

    func testAcceptingAddsEverySpelling() {
        let g = store
        correct(g, ["Zwiebels", "Zwiebelics", "Zwiebeliks"], to: "Zwiebelix")
        g.accept(g.visibleSuggestions[0])
        XCTAssertEqual(g.entries.map(\.term), ["Zwiebelix"])
        XCTAssertEqual(g.entries[0].soundsLike, ["Zwiebels", "Zwiebelics", "Zwiebeliks"])
        XCTAssertEqual(g.entries[0].scope, .only(.de))
        XCTAssertTrue(g.suggestions.isEmpty)
    }

    func testAcceptingACopyTakesTheSpellingsThatCameLater() {
        let g = store
        g.suggest(heard: "Zwiebels", term: "Zwiebelix", scope: .all, source: .history)
        let banner = g.visibleSuggestions[0]
        g.suggest(heard: "Zwiebelics", term: "Zwiebelix", scope: .all, source: .app)
        g.accept(banner)
        XCTAssertEqual(g.entries[0].soundsLike, ["Zwiebels", "Zwiebelics"])
    }

    func testAcceptingAddsToAnExistingTermOnce() {
        let g = store
        g.add(term: "Zwiebelix", soundsLike: ["zwiebels"])
        g.suggest(heard: "Zwiebels", term: "Zwiebelix", scope: .all, source: .history)
        g.suggest(heard: "Zwiebelics", term: "Zwiebelix", scope: .all, source: .history)
        g.accept(g.visibleSuggestions[0])
        XCTAssertEqual(g.entries[0].soundsLike, ["zwiebels", "Zwiebelics"])
    }

    func testIgnoringATermStopsNewSpellingsToo() {
        let g = store
        correct(g, ["Zwiebels", "Zwiebelics"], to: "Zwiebelix")
        g.ignore(g.visibleSuggestions[0])
        XCTAssertTrue(g.suggestions.isEmpty)
        correct(g, ["Zwiebeliks"], to: "Zwiebelix")
        correct(g, ["Zwiebels"], to: "Zwiebelix", source: .history)
        XCTAssertTrue(g.suggestions.isEmpty)
        let restarted = store
        correct(restarted, ["Zwiebelicks"], to: "Zwiebelix")
        XCTAssertTrue(restarted.suggestions.isEmpty, "after a restart too")
    }

    func testTwoLanguagesWidenTheScope() {
        let g = store
        g.suggest(heard: "Zwiebels", term: "Zwiebelix", scope: .only(.de), source: .app)
        g.suggest(heard: "Swiebelix", term: "Zwiebelix", scope: .only(.en), source: .app)
        XCTAssertEqual(g.suggestions[0].scope, .all)
    }

    func testAHistoryFixStillShowsAtOnceWithItsTerm() {
        let g = store
        g.suggest(heard: "Zwiebels", term: "Zwiebelix", scope: .all, source: .app)
        XCTAssertTrue(g.visibleSuggestions.isEmpty)
        correct(g, ["Zwiebelics"], to: "Zwiebelix", source: .history)
        XCTAssertEqual(g.visibleSuggestions.map(\.spellings), [["Zwiebels", "Zwiebelics"]])
        XCTAssertFalse(g.hasUnseenSuggestions, "History has just offered it")
    }

    func testTheLineForTheRowIsCompact() {
        var s = GlossarySuggestion(heard: "a", term: "T", scope: .all, count: 1, lastSeen: Date(), historyFix: false, seen: false)
        XCTAssertEqual(s.spellingsLine, "a")
        for spelling in ["b", "c", "d"] { s.add(spelling: spelling) }
        XCTAssertEqual(s.spellingsLine, "a / b / c / d")
        s.add(spelling: "e")
        XCTAssertEqual(s.spellingsLine, "a / b / c / d +1")
        let word = GlossarySuggestion(heard: "ab cd", term: "T", scope: .all, count: 1, lastSeen: Date(), historyFix: false, seen: false)
        XCTAssertEqual(word.spellingsLine, "a\u{2060}b c\u{2060}d", "a break only between words")
    }

    // MARK: Whole watches on field values

    func testAOneWordPasteRetypedPassesTheFilterForAMadeUpName() {
        var s = TrackedSegment(pasted: "Zwiebels", in: "Zwiebels", caret: nil)!
        var partial = ""
        for ch in "Zwiebelix" {
            partial.append(ch)
            XCTAssertTrue(s.update(partial), partial)
        }
        XCTAssertEqual(WordDiff.suggestionCandidates(from: s.pasted, to: s.text).count, 1)
        let filter = CorrectionFilter(languages: [.en, .de], isGlossaryTerm: { _ in false })
        XCTAssertEqual(filter.accepted(from: s.pasted, to: s.text).map(\.term), ["Zwiebelix"])
    }

    func testAOneWordPasteReplacedByAnUnrelatedWordGivesNothing() {
        var s = TrackedSegment(pasted: "Kubernetes", in: "Kubernetes", caret: nil)!
        var partial = ""
        for ch in "Fenster" {
            partial.append(ch)
            XCTAssertTrue(s.update(partial), partial)
        }
        XCTAssertEqual(s.text, "Fenster")
        let filter = CorrectionFilter(languages: [.en, .de], isGlossaryTerm: { _ in false })
        XCTAssertEqual(filter.accepted(from: s.pasted, to: s.text), [])
    }

    // MARK: Files of older versions

    func testOldPairsForOneTermMerge() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let old = #"""
        [{"heard":"Zwiebelics","term":"Zwiebelix","scope":"de","count":1,"lastSeen":"2026-11-02T10:00:00Z","historyFix":false,"seen":false},
         {"heard":"Zwiebels","term":"Zwiebelix","scope":"de","count":1,"lastSeen":"2026-11-01T10:00:00Z","historyFix":false,"seen":false},
         {"heard":"jam f","term":"Jamf","scope":"all","count":1,"lastSeen":"2026-10-20T10:00:00Z"}]
        """#
        try Data(old.utf8).write(to: dir.appendingPathComponent("suggestions.json"))
        let g = store
        XCTAssertEqual(g.suggestions.map(\.term), ["Zwiebelix", "Jamf"])
        let merged = g.suggestions[0]
        XCTAssertEqual(merged.spellings, ["Zwiebels", "Zwiebelics"], "the older one first")
        XCTAssertEqual(merged.count, 2)
        XCTAssertTrue(merged.isVisible)
        XCTAssertFalse(merged.seen)
        XCTAssertEqual(merged.scope, .only(.de))
    }

    func testAFileFrom041Loads() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let old = #"[{"heard":"jam f","term":"Jamf","scope":"en","count":3,"lastSeen":"2026-10-20T10:00:00Z"}]"#
        try Data(old.utf8).write(to: dir.appendingPathComponent("suggestions.json"))
        let s = store.suggestions[0]
        XCTAssertEqual([s.heard, s.term], ["jam f", "Jamf"])
        XCTAssertEqual(s.spellings, ["jam f"])
        XCTAssertEqual(s.count, 3)
    }

    func testAnOldIgnoredPairBlocksOnlyItsPair() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"[{"heard":"Zwiebels","term":"Zwiebelix"}]"#.utf8).write(to: dir.appendingPathComponent("ignoredSuggestions.json"))
        let g = store
        XCTAssertNil(g.suggest(heard: "zwiebels", term: "Zwiebelix", scope: .all, source: .history))
        XCTAssertNotNil(g.suggest(heard: "Zwiebelics", term: "Zwiebelix", scope: .all, source: .history))
    }

    func testAnOldVersionCanReadWhatIsSavedNow() throws {
        struct At041: Decodable {
            var heard: String, term: String, scope: GlossaryScope, count: Int, lastSeen: Date
        }
        let g = store
        for heard in ["Zwiebels", "Zwiebelics"] { g.suggest(heard: heard, term: "Zwiebelix", scope: .all, source: .app) }
        let data = try Data(contentsOf: dir.appendingPathComponent("suggestions.json"))
        let read = try Store.decoder.decode([At041].self, from: data)
        XCTAssertEqual(read.map(\.heard), ["Zwiebels"])
        XCTAssertEqual(read.map(\.count), [2])
    }

    func testAnIgnoredTermStaysAPairForOlderReaders() throws {
        let g = store
        for heard in ["Zwiebels", "Zwiebelics"] { g.suggest(heard: heard, term: "Zwiebelix", scope: .all, source: .history) }
        g.ignore(g.visibleSuggestions[0])
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("ignoredSuggestions.json"))) as! [[String: Any]]
        XCTAssertEqual(json.map { $0["heard"] as? String }, ["Zwiebels", "Zwiebelics"])
    }

    func testAnOldFileLoadsAndItsSuggestionsShowAtOnceWithoutADot() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let old = #"[{"heard":"jam f","term":"Jamf","scope":"all","count":1,"lastSeen":"2026-10-20T10:00:00Z"}]"#
        try Data(old.utf8).write(to: dir.appendingPathComponent("suggestions.json"))
        let g = store
        XCTAssertEqual(g.visibleSuggestions.map(\.term), ["Jamf"])
        XCTAssertFalse(g.hasUnseenSuggestions)
    }

    func testWhatIsStoredIsOnlyThePairAndItsCount() throws {
        let g = store
        g.suggest(heard: "cooper netties", term: "Kubernetes", scope: .all, source: .app)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("suggestions.json"))) as! [[String: Any]]
        XCTAssertEqual(Set(json[0].keys), ["heard", "term", "scope", "count", "lastSeen", "historyFix", "seen"])
    }

    func testMoreSpellingsAddOneFieldAndNoText() throws {
        let g = store
        g.suggest(heard: "cooper netties", term: "Kubernetes", scope: .all, source: .app)
        g.suggest(heard: "Kubernetis", term: "Kubernetes", scope: .all, source: .app)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("suggestions.json"))) as! [[String: Any]]
        XCTAssertEqual(Set(json[0].keys), ["heard", "term", "scope", "count", "lastSeen", "otherSpellings", "historyFix", "seen"])
        XCTAssertEqual(json[0]["otherSpellings"] as? [String], ["Kubernetis"])
    }

    // MARK: The dot

    func testTheDotComesWhenASuggestionShows() {
        let g = store
        g.suggest(heard: "cooper netties", term: "Kubernetes", scope: .all, source: .app)
        XCTAssertFalse(g.hasUnseenSuggestions)
        g.suggest(heard: "cooper netties", term: "Kubernetes", scope: .all, source: .app)
        XCTAssertTrue(g.hasUnseenSuggestions)
    }

    func testTheDotGoesOnceSeenAndStaysGoneAfterARestart() {
        let g = store
        for _ in 0..<2 { g.suggest(heard: "cooper netties", term: "Kubernetes", scope: .all, source: .app) }
        g.markSuggestionsSeen()
        XCTAssertFalse(g.hasUnseenSuggestions)
        XCTAssertEqual(g.visibleSuggestions.count, 1, "seen, not handled: the suggestion stays")
        XCTAssertFalse(store.hasUnseenSuggestions)
    }

    func testAHistoryFixGivesNoDot() {
        let g = store
        g.suggest(heard: "cooper netties", term: "Kubernetes", scope: .all, source: .history)
        XCTAssertFalse(g.hasUnseenSuggestions, "History has just offered it")
    }

    // MARK: History goes through the same filter

    func testHistoryFixesGoThroughTheFilter() {
        let g = store
        let filter = CorrectionFilter(languages: [.en, .de], isGlossaryTerm: g.contains(term:))
        g.learn(from: filter.accepted(from: "Wir nutzen cooper netties und dem Hund", to: "Wir nutzen Kubernetes und den Hund"),
                scope: .all, source: .history)
        XCTAssertEqual(g.visibleSuggestions.map(\.term), ["Kubernetes"])
    }

    func testTheSwitchIsOnByDefault() {
        let prefs = Preferences(defaults: UserDefaults(suiteName: "vypo.corrections.\(UUID().uuidString)")!)
        XCTAssertTrue(prefs.learnFromCorrections)
    }
}
