import XCTest
@testable import vypo

/// Symbols are ordinary entries of the replacements list (Fix 6, second version). Said on its own, every enabled
/// entry works in every app; in a sentence, as set per entry.
@MainActor
final class ReplacementSymbolsTests: XCTestCase {
    private func run(_ raw: String, _ mode: AppMode, language: Lang = .de, replacements: [Replacement]? = nil) -> String {
        TextPipeline.process(raw, PipelineContext(language: language, replacements: replacements ?? Replacements.defaults, mode: mode))
    }

    private func defaultEntry(_ output: String) -> Replacement { Replacements.defaults.first { $0.output == output }! }

    private let modes: [AppMode] = [.standard, .prompt, .writing, .excluded]

    // MARK: On its own

    private let alone: [(String, String)] = [
        ("Slash", "/"), ("Schrägstrich", "/"),
        ("Semikolon", ";"), ("Semicolon", ";"), ("Semi-Kolon", ";"), ("Semi Kolon", ";"), ("Semikolen", ";"),
        ("Sammy Colon", ";"), ("Semikodon", ";"), ("Siemikulon", ";"),
        ("Doppelpunkt", ":"), ("Punkt", "."), ("Period", "."), ("Full stop", "."), ("Komma", ","), ("Comma", ","),
        ("Bindestrich", "-"), ("Dash", "-"), ("Strich", "-"),
    ]

    func testEveryDefaultSpellingAloneInEveryMode() {
        for (spoken, symbol) in alone {
            for mode in modes {
                XCTAssertEqual(run(spoken, mode), symbol, "\(spoken) in \(mode)")
                XCTAssertEqual(run(spoken.lowercased() + ".", mode), symbol, "\(spoken). in \(mode)")
                XCTAssertEqual(run(spoken + ",", mode), symbol)
            }
            XCTAssertEqual(run(spoken, .standard, language: .en), symbol)
        }
    }

    func testNewLineAndParagraphInBothLanguages() {
        for mode in modes {
            XCTAssertEqual(run("Wort neue Zeile Wort", mode), "Wort\nWort", "\(mode)")
            XCTAssertEqual(run("Wort new paragraph Wort", mode), "Wort\n\nWort", "\(mode)")
            XCTAssertEqual(run("neuer Absatz.", mode), "\n\n")
        }
    }

    func testTwoSymbolWordsAreNotOne() {
        XCTAssertEqual(run("Semikolon, Doppelpunkt.", .standard), "Semikolon, Doppelpunkt.")
        XCTAssertEqual(run("Full, stop", .standard), "Full, stop")
    }

    func testADisabledEntryDoesNothingAlsoAlone() {
        var all = Replacements.defaults
        let i = all.firstIndex { $0.output == "/" }!
        all[i].enabled = false
        for mode in modes {
            XCTAssertEqual(run("Slash", mode, replacements: all), "Slash", "\(mode)")
            XCTAssertEqual(run("Projekte slash vypo", mode, replacements: all), "Projekte slash vypo")
        }
    }

    func testALoneSymbolKeepsItsPeriodInPrompt() {
        XCTAssertEqual(run("Punkt.", .prompt), ".")
        XCTAssertEqual(run("Das ist gut.", .prompt), "Das ist gut")
    }

    func testASymbolTheModelWroteStaysOnce() {
        for s in ["/", ";", ":", "-"] { XCTAssertEqual(run(s, .prompt), s) }
    }

    // MARK: In a sentence – three values × four modes

    func testInASentenceByScopeAndMode() {
        func entry(_ scope: SentenceScope) -> [Replacement] { [Replacement(spoken: "slash", output: "/", inSentence: scope)] }
        let text = "Projekte slash vypo"
        for mode in modes {
            XCTAssertEqual(run(text, mode, replacements: entry(.everywhere)), "Projekte/vypo", "everywhere in \(mode)")
            XCTAssertEqual(run(text, mode, replacements: entry(.promptOnly)), mode == .prompt ? "Projekte/vypo" : text, "promptOnly in \(mode)")
            XCTAssertEqual(run(text, mode, replacements: entry(.never)), text, "never in \(mode)")
            // On its own the scope doesn't matter.
            for scope in SentenceScope.allCases { XCTAssertEqual(run("Slash", mode, replacements: entry(scope)), "/") }
        }
    }

    func testTheDefaultsInASentence() {
        XCTAssertEqual(run("Projekte slash vypo", .prompt), "Projekte/vypo")
        XCTAssertEqual(run("Projekte slash vypo", .standard), "Projekte slash vypo")
        XCTAssertEqual(run("Wort Semikolon weiter", .prompt), "Wort; weiter")
        XCTAssertEqual(run("Wort Semi-Kolon weiter", .prompt), "Wort; weiter")
        XCTAssertEqual(run("Wort Sammy Colon weiter", .prompt), "Wort; weiter")
        XCTAssertEqual(run("Wort Semikolon weiter", .standard), "Wort Semikolon weiter")
        // Writing keeps its spoken punctuation.
        XCTAssertEqual(run("Wort Semikolon weiter", .writing), "Wort; weiter")
        XCTAssertEqual(run("Wort Doppelpunkt weiter", .writing), "Wort: weiter")
        XCTAssertEqual(run("Projekte slash vypo", .writing), "Projekte slash vypo")
    }

    func testOrdinaryWordsStayInASentence() {
        for text in ["Das ist ein wichtiger Punkt", "Ein Komma und ein Strich", "Der Bindestrich und der Dash",
                     "The colon and the period", "Punkt drei ist offen"] {
            for mode in [AppMode.standard, .prompt] {
                XCTAssertEqual(run(text, mode, language: text.hasPrefix("The") ? .en : .de), text, "\(text) in \(mode)")
            }
        }
    }

    // MARK: Spacing follows from the output

    func testConnectingOutputsHaveNoSpaces() {
        XCTAssertEqual(run("Struktur slash Anna slash user", .prompt), "Struktur/Anna/user")
        XCTAssertEqual(run("Slash exit.", .prompt), "/exit")
        XCTAssertEqual(run("Anna/slash user", .prompt), "Anna/user")
        XCTAssertEqual(run("Anna/slash", .prompt), "Anna/")
        XCTAssertEqual(run("Anna/ slash user", .prompt), "Anna/user")
    }

    func testAttachingOutputsHangOnTheWordBefore() {
        XCTAssertEqual(run("Begriffserklärung, Doppelpunkt, Zero", .prompt), "Begriffserklärung: Zero")
        XCTAssertEqual(run("Begriffserklärung. Doppelpunkt. Zero", .prompt), "Begriffserklärung: Zero")
        XCTAssertEqual(run("Hallo Doppelpunkt.", .prompt), "Hallo:")
        XCTAssertEqual(run("Wort; Semikolon weiter", .prompt), "Wort; weiter")
        XCTAssertEqual(run("Semikolon, Doppelpunkt.", .prompt), ";:")
    }

    func testAnyOtherOutputIsAPlainWordReplacement() {
        let own = [Replacement(spoken: "brb, bin gleich zurück", output: "be right back")]
        XCTAssertEqual(run("BRB, see you", .standard, replacements: own), "be right back see you")
        let at = [Replacement(spoken: "at sign", output: "@", inSentence: .everywhere)]
        XCTAssertEqual(run("mail at sign example", .standard, replacements: at), "mail @ example")
    }

    func testOwnEntryEverywhereWorksAsBefore() {
        let own = [Replacement(spoken: "Pfad", output: "/", inSentence: .everywhere)]
        XCTAssertEqual(run("x Pfad y", .standard, replacements: own), "x/y")
    }

    // MARK: No Return after a symbol

    func testNoReturnAfterALoneSymbol() {
        XCTAssertTrue(ProfileTweaks.sendsReturn(mode: .prompt, autoEnter: true, inTextField: true, text: "Hallo Welt"))
        for text in ["/", ";", ":", "-", ".", "@"] {
            XCTAssertFalse(ProfileTweaks.sendsReturn(mode: .prompt, autoEnter: true, inTextField: true, text: text), text)
        }
        XCTAssertFalse(ProfileTweaks.sendsReturn(mode: .prompt, autoEnter: true, inTextField: true, text: run("Slash", .prompt)))
        XCTAssertFalse(ProfileTweaks.sendsReturn(mode: .prompt, autoEnter: false, inTextField: true, text: "Hallo"))
        XCTAssertFalse(ProfileTweaks.sendsReturn(mode: .standard, autoEnter: true, inTextField: true, text: "Hallo"))
    }

    func testALoneSymbolGetsNoSpaceFromTheContext() {
        for symbol in [":", "/", ";", "-", "."] {
            XCTAssertEqual(ContextFormatter.format(symbol, context: InsertionContext(before: "ab", after: nil), language: .de, glossaryTerms: []), symbol)
        }
        XCTAssertEqual(ContextFormatter.format(".", context: InsertionContext(before: "ab", after: "c"), language: .de, glossaryTerms: []), ".")
    }

    /// The raw transcripts of 2026-10-25 (Diagnosis, part 1), with the defaults.
    func testTheRealCasesOfTheDiagnosis() {
        let cases: [(raw: String, standard: String, prompt: String)] = [
            ("Doppelpunkt.", ":", ":"), ("Semikolon.", ";", ";"), ("Slash", "/", "/"), ("Sammy Colon", ";", ";"), ("Semikodon.", ";", ";"),
            ("Struktur slash Anna/slash user", "Struktur slash Anna/slash user", "Struktur/Anna/user"),
            ("oder Doppelpunkt oder", "oder Doppelpunkt oder", "oder: oder"),
            ("Begriffserklärung, Doppelpunkt, Zero", "Begriffserklärung, Doppelpunkt, Zero", "Begriffserklärung: Zero"),
            ("Semikolon, Doppelpunkt.", "Semikolon, Doppelpunkt.", ";:"),
            ("Slash exit.", "Slash exit.", "/exit"),
        ]
        for c in cases {
            XCTAssertEqual(run(c.raw, .standard), c.standard, c.raw)
            XCTAssertEqual(run(c.raw, .prompt), c.prompt, c.raw)
        }
    }

    // MARK: Model and storage

    func testOldFilesStillDecode() throws {
        let old = #"[{"id":"0B2FB6A1-926E-4C02-A2E2-DED120900AF1","spoken":"Semikolon, Semicolon","output":";","enabled":true}]"#
        let r = try JSONDecoder().decode([Replacement].self, from: Data(old.utf8))
        XCTAssertEqual(r.first?.spoken, ["Semikolon", "Semicolon"])
        XCTAssertEqual(r.first?.inSentence, .everywhere)
        let new = try JSONDecoder().decode([Replacement].self, from: JSONEncoder().encode(Replacements.defaults))
        XCTAssertEqual(new.map(\.spoken), Replacements.defaults.map(\.spoken))
        XCTAssertEqual(new.map(\.inSentence), Replacements.defaults.map(\.inSentence))
    }

    func testTheListShowsTwoSpellingsAndADots() {
        XCTAssertEqual(defaultEntry("/").summary, "“Slash”, “Schrägstrich”")
        XCTAssertTrue(defaultEntry(";").summary.hasSuffix("…"))
        XCTAssertEqual(defaultEntry(";").spoken.prefix(2), ["Semikolon", "Semicolon"])
    }

    // MARK: Migration

    private func ownerList() -> [Replacement] {
        [Replacement(spoken: "new line", output: "\n"), Replacement(spoken: "new paragraph", output: "\n\n"),
         Replacement(spoken: "Doppelpunkt", output: ":"), Replacement(spoken: "Semikolon", output: ";"),
         Replacement(spoken: "Slash", output: "/"), Replacement(spoken: "Dash", output: "-"),
         Replacement(spoken: "Semicolon", output: ";")]
    }

    func testMigrationMergesSpellingsOfOneOutput() {
        let m = Replacements.migrated([Replacement(spoken: "a", output: "x"), Replacement(spoken: "b", output: "x"),
                                       Replacement(spoken: "c", output: "x", enabled: false)])
        let x = m.filter { $0.output == "x" }
        XCTAssertEqual(x.count, 2, "a disabled entry stays apart")
        XCTAssertEqual(x.first?.spoken, ["a", "b"])
        XCTAssertEqual(x.first?.inSentence, .everywhere, "the old entries work as before")
    }

    func testMigrationMergesTheOwnersEntriesIntoTheDefaults() {
        let m = Replacements.migrated(ownerList())
        XCTAssertEqual(m.count, Replacements.defaults.count, "no duplicates")
        let semi = m.first { $0.output == ";" }!
        XCTAssertEqual(semi.spoken.prefix(3), ["Semikolon", "Semicolon", "Semi-Kolon"])
        XCTAssertTrue(semi.spoken.contains("Siemikulon"))
        XCTAssertEqual(semi.inSentence, .promptOnly)
        XCTAssertEqual(m.first { $0.output == "/" }?.spoken, ["Slash", "Schrägstrich"])
        XCTAssertEqual(m.first { $0.output == "/" }?.inSentence, .promptOnly)
        XCTAssertEqual(m.first { $0.output == "-" }?.spoken, ["Dash", "Bindestrich", "Strich"])
        XCTAssertEqual(m.first { $0.output == "-" }?.inSentence, .never)
        XCTAssertEqual(m.first { $0.output == "\n" }?.spoken, ["new line", "neue Zeile"])
        XCTAssertEqual(m.first { $0.output == "\n\n" }?.spoken, ["new paragraph", "neuer Absatz"])
        XCTAssertEqual(m.first { $0.output == "\n" }?.inSentence, .everywhere)
        XCTAssertNotNil(m.first { $0.output == "." })
        XCTAssertNotNil(m.first { $0.output == "," })
    }

    func testMigrationKeepsOtherEntriesAndTheirState() {
        var list = ownerList()
        list.append(Replacement(spoken: "brb", output: "be right back"))
        list[4].enabled = false   // Slash
        let m = Replacements.migrated(list)
        XCTAssertEqual(m.first { $0.output == "be right back" }?.inSentence, .everywhere)
        XCTAssertEqual(m.first { $0.output == "/" }?.enabled, false, "his switch stays")
    }

    func testMigrationTurnsOffWhatTheOldSwitchesTurnedOff() {
        let noSentence = Replacements.migrated(ownerList(), symbolsInSentence: false)
        XCTAssertTrue(noSentence.filter { ["/", ";", ":"].contains($0.output) }.allSatisfy { $0.inSentence == .never })
        let noAlone = Replacements.migrated(ownerList(), symbolsAlone: false)
        XCTAssertTrue(noAlone.filter { [".", ",", "-"].contains($0.output) }.allSatisfy { !$0.enabled })
        XCTAssertTrue(noAlone.filter { ["/", ";", ":"].contains($0.output) }.allSatisfy { $0.enabled })
    }

    func testTheStoreMigratesOnceAndSavesIt() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = Store(directory: dir)
        store.save(ownerList(), to: "replacements.json")
        let suite = "vypo.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: DefaultsKey.spokenSymbols)
        defaults.set(true, forKey: DefaultsKey.spokenSymbolsAlone)
        let first = ReplacementStore(store: store, defaults: defaults)
        XCTAssertEqual(first.items.count, Replacements.defaults.count)
        XCTAssertEqual(first.items.first { $0.output == "/" }?.inSentence, .never, "the old switch was off")
        XCTAssertNil(defaults.object(forKey: DefaultsKey.spokenSymbols), "the old switches are gone")
        XCTAssertTrue(defaults.bool(forKey: DefaultsKey.symbolsAreReplacements))
        // Starting again changes nothing, also after the user changed an entry.
        var edited = first.items.first { $0.output == "/" }!
        edited.inSentence = .everywhere
        edited.spoken = ["Slash"]
        first.upsert(edited)
        let second = ReplacementStore(store: store, defaults: defaults)
        XCTAssertEqual(second.items, first.items)
        XCTAssertEqual(second.items.first { $0.output == "/" }?.spoken, ["Slash"])
    }

    func testAFreshInstallationHasTheDefaults() {
        let store = Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let defaults = UserDefaults(suiteName: "vypo.tests.\(UUID().uuidString)")!
        let rs = ReplacementStore(store: store, defaults: defaults)
        XCTAssertEqual(rs.items.map(\.spoken), Replacements.defaults.map(\.spoken))
        XCTAssertEqual(rs.items.map(\.output), Replacements.defaults.map(\.output))
    }

    func testRestoreDefaultEntriesAddsOnlyWhatIsMissing() {
        let store = Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let rs = ReplacementStore(store: store, defaults: UserDefaults(suiteName: "vypo.tests.\(UUID().uuidString)")!)
        let slash = rs.items.first { $0.output == "/" }!
        var changed = slash
        changed.spoken = ["Slash", "Eigen"]
        changed.inSentence = .everywhere
        rs.upsert(changed)
        rs.delete(rs.items.first { $0.output == "." }!.id)
        XCTAssertEqual(rs.restoreDefaults(), 1)
        XCTAssertEqual(rs.items.first { $0.output == "/" }, changed, "his version stays")
        XCTAssertEqual(rs.items.count, Replacements.defaults.count)
        XCTAssertEqual(rs.restoreDefaults(), 0)
    }
}

/// Fix: a symbol word after an article stays a word; a comma before a line break goes.
@MainActor
final class SymbolPolishTests: XCTestCase {
    private func run(_ raw: String, _ mode: AppMode = .prompt, language: Lang = .de, replacements: [Replacement]? = nil) -> String {
        TextPipeline.process(raw, PipelineContext(language: language, replacements: replacements ?? Replacements.defaults, mode: mode))
    }

    func testASymbolWordAfterAnArticleStaysAWord() {
        XCTAssertEqual(run("Use the slash command to start.", language: .en), "Use the slash command to start")
        XCTAssertEqual(run("Der Doppelpunkt ist ein Zeichen", language: .de), "Der Doppelpunkt ist ein Zeichen")
        XCTAssertEqual(run("Ein Semikolon trennt zwei Sätze"), "Ein Semikolon trennt zwei Sätze")
        XCTAssertEqual(run("Check my slash commands", language: .en), "Check my slash commands")
        XCTAssertEqual(run("this semicolon is wrong", language: .en), "this semicolon is wrong")
        for word in ["the", "a", "this", "that", "my", "your", "der", "die", "das", "dem", "ein", "eine", "mein", "unser"] {
            XCTAssertEqual(run("\(word) slash x", language: .en), "\(word) slash x", word)
        }
    }

    func testWithoutAnArticleItIsStillReplaced() {
        XCTAssertEqual(run("Projekte slash vypo"), "Projekte/vypo")
        XCTAssertEqual(run("Geh in den Ordner Projekte slash Vypo slash Docs."), "Geh in den Ordner Projekte/Vypo/Docs")
        XCTAssertEqual(run("Erster Teil, Semikolon, zweiter Teil."), "Erster Teil; zweiter Teil")
        XCTAssertEqual(run("Begriffserklärung Doppelpunkt Zero Day Exploit."), "Begriffserklärung: Zero Day Exploit")
        // The article only counts right before the word.
        XCTAssertEqual(run("the folder slash docs", language: .en), "the folder/docs")
    }

    func testAloneStaysASymbolWhateverTheRule() {
        for (word, symbol) in [("Slash", "/"), ("Semikolon.", ";"), ("Doppelpunkt.", ":"), ("Punkt", "."), ("Bindestrich.", "-")] {
            XCTAssertEqual(run(word), symbol)
        }
    }

    func testTheRuleIsOnlyForSymbolOutputs() {
        let own = [Replacement(spoken: "brb", output: "be right back")]
        XCTAssertEqual(run("the brb is here", .standard, language: .en, replacements: own), "the be right back is here")
        // An own entry whose output is a symbol follows the rule too.
        let pfad = [Replacement(spoken: "Pfad", output: "/", inSentence: .everywhere)]
        XCTAssertEqual(run("der Pfad ist lang", .standard, replacements: pfad), "der Pfad ist lang")
        XCTAssertEqual(run("x Pfad y", .standard, replacements: pfad), "x/y")
        // Said everywhere: also outside Prompt apps, unless it follows an article.
        XCTAssertEqual(run("the slash command", .standard, language: .en, replacements: [Replacement(spoken: "slash", output: "/")]), "the slash command")
    }

    func testACommaBeforeALineBreakGoes() {
        XCTAssertEqual(run("Erste Zeile, neue Zeile, zweite Zeile."), "Erste Zeile\nzweite Zeile")
        XCTAssertEqual(run("Erste Zeile,neue Zeile zweite Zeile", .standard), "Erste Zeile\nzweite Zeile")
        XCTAssertEqual(run("one, new paragraph, two", .standard, language: .en), "one\n\ntwo")
        XCTAssertEqual(run("Erste Zeile, neuer Absatz zweite Zeile", .writing), "Erste Zeile\n\nzweite Zeile")
    }

    func testAPeriodQuestionOrExclamationMarkBeforeALineBreakStays() {
        XCTAssertEqual(Replacements.apply(Replacements.defaults, to: "Fertig. neue Zeile weiter"), "Fertig.\nweiter")
        XCTAssertEqual(Replacements.apply(Replacements.defaults, to: "Fertig? neue Zeile weiter"), "Fertig?\nweiter")
        XCTAssertEqual(Replacements.apply(Replacements.defaults, to: "Fertig! neue Zeile weiter"), "Fertig!\nweiter")
        XCTAssertEqual(Replacements.apply(Replacements.defaults, to: "first line new line second"), "first line\nsecond")
    }
}
