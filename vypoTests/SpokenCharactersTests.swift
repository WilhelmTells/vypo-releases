import XCTest
@testable import vypo

/// 0.4.0: Words → Spoken characters for new installations; the Mac's layout is decided once.
@MainActor
final class SpokenCharactersTests: XCTestCase {
    // MARK: Pipelines of both layouts

    /// 0.3.0 with the Writing fix: the default replacements and `SpokenPunctuation`.
    private func legacy(_ raw: String, _ mode: AppMode, _ lang: Lang = .de, spellings: [String] = [], typographic: Bool = true) -> String {
        TextPipeline.process(raw, PipelineContext(language: lang, replacements: Replacements.defaults, spellings: spellings,
                                                  mode: mode, typographicQuotes: typographic))
    }

    /// A new installation: no replacements of its own unless given, the default characters.
    private func new(_ raw: String, _ mode: AppMode, _ lang: Lang = .de, own: [Replacement] = [],
                     characters: [SpokenCharacter] = SpokenCharacters.defaults, spellings: [String] = [], typographic: Bool = true) -> String {
        TextPipeline.process(raw, PipelineContext(language: lang, replacements: own, spellings: spellings, mode: mode,
                                                  spokenCharacters: characters, typographicQuotes: typographic))
    }

    /// Off never reaches the pipeline: vypo doesn't record there (`DictationController`).
    private let modes: [AppMode] = [.standard, .prompt, .writing]

    /// Every input of `WritingPunctuationTests`, `ReplacementSymbolsTests`, `SymbolPolishTests`, the spoken punctuation
    /// of `TextQualityTests` and the tables of the words and apps exploration, with their language.
    private var corpus: [(String, Lang)] {
        var de = [
            "Erste Zeile neue Zeile zweite Zeile", "Fertig Punkt neuer Absatz nächster Satz", "neue Zeile macOS ist da",
            "Hallo neue Zeile iPhone ist da", "Fertig Punkt macOS läuft", "Das ist ein wichtiger Punkt", "Der Punkt ist klar",
            "Da fehlt ein Komma", "Das ist ein großes Fragezeichen", "Damit du meinen Punkt verstehst", "Ich glaube beim dritten Punkt",
            "Das ist kein Komma", "Das ist gut Punkt", "Hallo Komma wie geht es dir Punkt", "Ich habe das gemacht Punkt",
            "Ich habe das alles verstanden Punkt", "Wirklich Fragezeichen", "Das ist ein Doppelpunkt", "Ein neues Semikolon",
            "Ich nehme das. Punkt", "Wort neue Zeile Wort", "Wort new paragraph Wort", "neuer Absatz.", "Semikolon, Doppelpunkt.",
            "Punkt.", "Das ist gut.", "/", ";", ":", "-", "Projekte slash vypo", "Wort Semikolon weiter", "Wort Semi-Kolon weiter",
            "Wort Sammy Colon weiter", "Wort Doppelpunkt weiter", "Ein Komma und ein Strich", "Der Bindestrich und der Dash",
            "Punkt drei ist offen", "Struktur slash Anna slash user", "Slash exit.", "Anna/slash user", "Anna/slash", "Anna/ slash user",
            "Begriffserklärung, Doppelpunkt, Zero", "Begriffserklärung. Doppelpunkt. Zero", "Hallo Doppelpunkt.", "Wort; Semikolon weiter",
            "Doppelpunkt.", "Semikolon.", "Semikodon.", "Struktur slash Anna/slash user", "oder Doppelpunkt oder",
            "Der Doppelpunkt ist ein Zeichen", "Ein Semikolon trennt zwei Sätze", "Geh in den Ordner Projekte slash Vypo slash Docs.",
            "Erster Teil, Semikolon, zweiter Teil.", "Begriffserklärung Doppelpunkt Zero Day Exploit.", "Bindestrich.",
            "Erste Zeile, neue Zeile, zweite Zeile.", "Erste Zeile,neue Zeile zweite Zeile", "Erste Zeile, neuer Absatz zweite Zeile",
            "Fertig. neue Zeile weiter", "Fertig? neue Zeile weiter", "Fertig! neue Zeile weiter", "Eins Semikolon zwei",
            "Begriffserklärung Doppelpunkt Zero", "Hallo Komma wie geht's Fragezeichen neuer Absatz danke",
            "er sagte Anführungszeichen auf hallo Anführungszeichen zu", "Fertig. weiter geht's", "Die neue Zeile gefällt mir",
        ]
        for (spoken, _) in alone {
            de += [spoken, spoken.lowercased() + ".", spoken + ","]
        }
        let en = [
            "First line new line second line", "It took a long period of time", "In that period we shipped",
            "That was an important period", "Hello comma how are you period", "The colon and the period",
            "Use the slash command to start.", "Check my slash commands", "this semicolon is wrong", "the folder slash docs",
            "one, new paragraph, two", "first line new line second", "Use the slash command", "hello comma world period",
            "done. period", "hello, comma, world", "He said open quote hi close quote", "Wait question mark really exclamation mark",
            "Slash", "Semicolon", "Period", "Full stop", "Comma", "Dash",
        ] + ["the", "a", "this", "that", "my", "your", "der", "die", "das", "dem", "ein", "eine", "mein", "unser"].map { "\($0) slash x" }
        return de.map { ($0, .de) } + en.map { ($0, .en) }
    }

    private let alone = [
        ("Slash", "/"), ("Schrägstrich", "/"), ("Semikolon", ";"), ("Semicolon", ";"), ("Semi-Kolon", ";"), ("Semi Kolon", ";"),
        ("Semikolen", ";"), ("Sammy Colon", ";"), ("Semikodon", ";"), ("Siemikulon", ";"), ("Doppelpunkt", ":"), ("Punkt", "."),
        ("Period", "."), ("Full stop", "."), ("Komma", ","), ("Comma", ","), ("Bindestrich", "-"), ("Dash", "-"), ("Strich", "-"),
    ]

    /// Where a new installation writes something else, on purpose (see the report).
    private let intended: [String: String] = [
        // Parakeet's spellings of “Semikolon” are part of the one entry, which works in Writing too.
        "Wort Sammy Colon weiter|writing": "Wort; weiter",
    ]

    func testANewInstallationWritesWhat030Wrote() {
        var checked = 0
        for (raw, lang) in corpus {
            for mode in modes {
                for typographic in [true, false] {
                    let spellings = ["macOS", "iPhone"]
                    let old = legacy(raw, mode, lang, spellings: spellings, typographic: typographic)
                    let now = new(raw, mode, lang, spellings: spellings, typographic: typographic)
                    let expected = intended["\(raw)|\(mode.rawValue)"] ?? old
                    XCTAssertEqual(now, expected, "“\(raw)” (\(lang.rawValue)) in \(mode.rawValue), typographic \(typographic)")
                    checked += 1
                }
            }
        }
        XCTAssertGreaterThan(checked, 900)
    }

    func testTheWritingCasesWithTheirExpectedOutput() {
        func w(_ raw: String, _ lang: Lang = .de) -> String {
            new(raw, .writing, lang, spellings: ["macOS"]).replacingOccurrences(of: "\n", with: "⏎")
        }
        XCTAssertEqual(w("Erste Zeile neue Zeile zweite Zeile"), "Erste Zeile⏎Zweite Zeile")
        XCTAssertEqual(w("Fertig Punkt neuer Absatz nächster Satz"), "Fertig.⏎⏎Nächster Satz")
        XCTAssertEqual(w("Fertig Punkt macOS läuft"), "Fertig. macOS läuft")
        XCTAssertEqual(w("Das ist ein wichtiger Punkt"), "Das ist ein wichtiger Punkt")
        XCTAssertEqual(w("Hallo Komma wie geht es dir Punkt"), "Hallo, wie geht es dir.")
        XCTAssertEqual(w("Hello comma how are you period", .en), "Hello, how are you.")
        XCTAssertEqual(w("Wort Doppelpunkt weiter"), "Wort: weiter")
        XCTAssertEqual(w("Wort Semikolon weiter"), "Wort; weiter")
        XCTAssertEqual(w("Projekte slash vypo"), "Projekte slash vypo")
        XCTAssertEqual(w("Wirklich Fragezeichen"), "Wirklich?")
        XCTAssertEqual(w("er sagte Anführungszeichen auf hallo Anführungszeichen zu"), "er sagte „hallo“")
        XCTAssertEqual(w("He said open quote hi close quote", .en), "He said “hi”")
        XCTAssertEqual(new("er sagte Anführungszeichen auf hallo Anführungszeichen zu", .writing, typographic: false), "er sagte \"hallo\"")
    }

    func testDefaultAndPromptWithTheirExpectedOutput() {
        XCTAssertEqual(new("Projekte slash vypo", .prompt), "Projekte/vypo")
        XCTAssertEqual(new("Projekte slash vypo", .standard), "Projekte slash vypo")
        XCTAssertEqual(new("Eins Semikolon zwei", .prompt), "Eins; zwei")
        XCTAssertEqual(new("Eins Semikolon zwei", .standard), "Eins Semikolon zwei")
        XCTAssertEqual(new("Begriffserklärung Doppelpunkt Zero", .prompt), "Begriffserklärung: Zero")
        XCTAssertEqual(new("Hallo Komma wie geht es dir Punkt", .standard), "Hallo Komma wie geht es dir Punkt")
        XCTAssertEqual(new("Hallo Komma wie geht es dir Punkt", .prompt), "Hallo Komma wie geht es dir Punkt")
        XCTAssertEqual(new("Erste Zeile neue Zeile zweite Zeile", .standard), "Erste Zeile\nzweite Zeile")
        XCTAssertEqual(new("Use the slash command", .prompt, .en), "Use the slash command")
        for (word, symbol) in [("Punkt", "."), ("Slash", "/"), ("Doppelpunkt", ":")] {
            for mode in [AppMode.standard, .prompt, .writing] { XCTAssertEqual(new(word, mode), symbol) }
        }
    }

    // MARK: Intended changes

    func testColonIsNoLongerAColonInWriting() {
        XCTAssertEqual(legacy("Wort colon weiter", .writing, .en), "Wort: weiter", "0.3.0")
        XCTAssertEqual(new("Wort colon weiter", .writing, .en), "Wort colon weiter")
        XCTAssertEqual(new("colon", .writing, .en), "colon")
        // Anyone who wants it adds it.
        let own = SpokenCharacters.defaults + [SpokenCharacter(spoken: ["colon"], output: ":", inSentence: [])]
        XCTAssertEqual(new("colon", .standard, .en, characters: own), ":")
        XCTAssertEqual(new("Wort colon weiter", .writing, .en, characters: own), "Wort colon weiter")
    }

    func testTheNewLineAsANounStaysInBothLayouts() {
        for mode in [AppMode.standard, .prompt, .writing] {
            XCTAssertEqual(new("Die neue Zeile gefällt mir", mode), "Die neue Zeile gefällt mir", "\(mode)")
            XCTAssertEqual(legacy("Die neue Zeile gefällt mir", mode), "Die neue Zeile gefällt mir", "\(mode)")
            XCTAssertEqual(legacy("Ein neuer Absatz beginnt", mode), "Ein neuer Absatz beginnt", "\(mode)")
            XCTAssertEqual(legacy("Start the new line here", mode, .en), "Start the new line here", "\(mode)")
            XCTAssertEqual(new("Start the new line here", mode, .en), "Start the new line here", "\(mode)")
            XCTAssertEqual(legacy("Ich mag meinen neuen Absatz", mode), "Ich mag meinen neuen Absatz", "no entry")
        }
        // Only the word right before counts: these are still breaks.
        XCTAssertEqual(legacy("Please check the code new line thanks", .standard, .en), "Please check the code\nthanks")
        XCTAssertEqual(new("Please check the code new line thanks", .writing, .en), "Please check the code\nThanks")
        XCTAssertEqual(legacy("Erste Zeile neue Zeile zweite Zeile", .standard), "Erste Zeile\nzweite Zeile")
        XCTAssertEqual(legacy("Die, neue Zeile, zweite", .standard), "Die\nzweite", "a comma between: not a noun")
        // German contractions and inflected forms count in German only.
        XCTAssertEqual(legacy("Hier beim neuer Absatz", .standard), "Hier beim neuer Absatz")
        XCTAssertEqual(Replacements.apply(Replacements.defaults, to: "Here I am new line"), "Here I am\n")
    }

    func testWordsOfTheTableAloneNowWorkInEveryMode() {
        // In 0.3.0 only Writing knew “Fragezeichen”; now every entry said on its own works everywhere.
        XCTAssertEqual(legacy("Fragezeichen", .standard), "Fragezeichen", "0.3.0")
        for mode in [AppMode.standard, .prompt, .writing] {
            XCTAssertEqual(new("Fragezeichen", mode), "?")
            XCTAssertEqual(new("Exclamation mark.", mode, .en), "!")
        }
        XCTAssertEqual(new("Anführungszeichen auf", .standard), "“", "outside Writing: the character as written")
        XCTAssertEqual(new("Anführungszeichen auf", .writing), "„", "in Writing: the language's quote")
    }

    // MARK: Order, switches, language

    func testOwnReplacementsWin() {
        let own = [Replacement(spoken: "Punkt", output: "Punkt (Satzzeichen)", inSentence: .everywhere)]
        for mode in [AppMode.standard, .prompt, .writing] {
            XCTAssertEqual(new("Das ist gut Punkt", mode, own: own), "Das ist gut Punkt (Satzzeichen)", "\(mode)")
            XCTAssertEqual(new("Punkt", mode, own: own), "Punkt (Satzzeichen)", "\(mode)")
        }
        let mail = [Replacement(spoken: "my email", output: "name@example.com")]
        XCTAssertEqual(new("Write to my email comma please", .writing, .en, own: mail), "Write to name@example.com, please")
        let slash = [Replacement(spoken: "Slash", output: "/", inSentence: .everywhere)]
        XCTAssertEqual(new("Projekte slash vypo", .standard, own: slash), "Projekte/vypo")
    }

    func testOffAndDisabledEntries() {
        for mode in [AppMode.standard, .prompt, .writing] {
            XCTAssertEqual(new("Punkt", mode, characters: []), "Punkt", "switch off: nothing")
            XCTAssertEqual(new("Wort neue Zeile Wort", mode, characters: []), "Wort neue Zeile Wort")
        }
        XCTAssertEqual(new("Hallo Komma du", .writing, characters: []), "Hallo Komma du")
        var list = SpokenCharacters.defaults
        let comma = list.firstIndex { $0.output == "," }!
        list[comma].enabled = false
        XCTAssertEqual(new("Hallo Komma du Punkt", .writing, characters: list), "Hallo Komma du.")
        XCTAssertEqual(new("Komma", .standard, characters: list), "Komma")
    }

    func testModesPerEntry() {
        var list = SpokenCharacters.defaults
        let slash = list.firstIndex { $0.output == "/" }!
        list[slash].inSentence = [.standard, .writing]
        XCTAssertEqual(new("Projekte slash vypo", .standard, characters: list), "Projekte/vypo")
        XCTAssertEqual(new("Projekte slash vypo", .writing, characters: list), "Projekte/vypo")
        XCTAssertEqual(new("Projekte slash vypo", .prompt, characters: list), "Projekte slash vypo")
        let period = list.firstIndex { $0.output == "." }!
        list[period].inSentence = [.prompt]
        XCTAssertEqual(new("Das ist gut Punkt", .writing, characters: list), "Das ist gut Punkt")
        XCTAssertEqual(new("Das ist gut Punkt nächster", .prompt, characters: list), "Das ist gut. nächster")
        XCTAssertEqual(new("Punkt", .writing, characters: list), ".", "on its own in every mode")
    }

    func testAnyLanguage() {
        // The entries are words of one language each; a misdetected dictation still gets them.
        XCTAssertEqual(new("Hallo Komma du", .writing, .en), "Hallo, du")
        XCTAssertEqual(new("Hello comma you", .writing, .de), "Hello, you")
        // The noun rule follows the detected language.
        XCTAssertEqual(new("Das ist ein wichtiger Punkt", .writing, .de), "Das ist ein wichtiger Punkt")
        XCTAssertEqual(new("That was an important period", .writing, .en), "That was an important period")
        XCTAssertEqual(new("Erste Zeile neue Zeile zweite", .standard, .fr), "Erste Zeile\nzweite")
    }

    // MARK: Defaults and the store

    func testTheDefaultTable() {
        let d = SpokenCharacters.defaults
        XCTAssertFalse(d.contains { $0.spoken.contains { $0.lowercased() == "colon" } })
        func modes(_ output: String) -> Set<AppMode> { d.first { $0.output == output }!.inSentence }
        XCTAssertEqual(modes("\n"), [.standard, .prompt, .writing])
        XCTAssertEqual(modes("\n\n"), [.standard, .prompt, .writing])
        XCTAssertEqual(modes("."), [.writing])
        XCTAssertEqual(modes(","), [.writing])
        XCTAssertEqual(modes(":"), [.prompt, .writing])
        XCTAssertEqual(modes(";"), [.prompt, .writing])
        XCTAssertEqual(modes("/"), [.prompt])
        XCTAssertEqual(modes("-"), [])
        // Every spelling of the old defaults and of the old Writing table is in.
        let all = Set(d.flatMap(\.spoken).map(Replacements.normalized))
        for r in Replacements.defaults { for s in r.spoken { XCTAssertTrue(all.contains(Replacements.normalized(s)), s) } }
        for lang in [Lang.de, .en] {
            for (words, _) in SpokenPunctuation.phrases(lang) where words != ["colon"] {
                XCTAssertTrue(all.contains(words.joined(separator: " ")), words.joined(separator: " "))
            }
        }
    }

    func testTheFileIsStableAndRoundTrips() throws {
        let data = try Store.encoder.encode(SpokenCharacters.defaults)
        let back = try Store.decoder.decode([SpokenCharacter].self, from: data)
        XCTAssertEqual(back, SpokenCharacters.defaults.enumerated().map { i, c in var c = c; c.id = back[i].id; return c })
        XCTAssertEqual(try Store.encoder.encode(back), data)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""inSentence" : ["#))
    }

    private func scratch() -> (Store, UserDefaults) {
        let store = Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent("vypo-sc-\(UUID().uuidString)"))
        let suite = "vypo.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: store.directory) }
        return (store, defaults)
    }

    func testRestoreDefaultCharactersAddsOnlyWhatIsMissing() {
        let (store, _) = scratch()
        let sc = SpokenCharacterStore(store: store)
        XCTAssertEqual(sc.items.count, SpokenCharacters.defaults.count)
        var slash = sc.items.first { $0.output == "/" }!
        slash.spoken = ["Slash", "Eigen"]
        slash.inSentence = [.standard]
        sc.upsert(slash)
        sc.delete(sc.items.first { $0.output == "." }!.id)
        sc.upsert(SpokenCharacter(spoken: ["Pfeil"], output: "→", inSentence: [.writing]))
        XCTAssertEqual(sc.restoreDefaults(), 1)
        XCTAssertEqual(sc.items.first { $0.output == "/" }, slash, "yours stays")
        XCTAssertTrue(sc.items.contains { $0.output == "→" })
        XCTAssertEqual(sc.items.count, SpokenCharacters.defaults.count + 1)
        XCTAssertEqual(sc.restoreDefaults(), 0)
        // Saved, and read back by the next launch.
        XCTAssertEqual(SpokenCharacterStore(store: store).items, sc.items)
    }

    func testTheStoreWritesTheDefaultsOnceAndKeepsABrokenFile() throws {
        let (store, _) = scratch()
        _ = SpokenCharacterStore(store: store)
        XCTAssertNotNil(store.load([SpokenCharacter].self, from: SpokenCharacterStore.file))
        try Data("{broken".utf8).write(to: store.url(SpokenCharacterStore.file))
        let again = SpokenCharacterStore(store: store)
        XCTAssertEqual(again.items.count, SpokenCharacters.defaults.count)
        XCTAssertEqual(try String(contentsOf: store.url(SpokenCharacterStore.file), encoding: .utf8), "{broken")
    }

    // MARK: New or existing

    func testAFreshMacIsNew() {
        let (store, defaults) = scratch()
        XCTAssertEqual(WordsLayout.resolve(store: store, defaults: defaults), .spokenCharacters)
        XCTAssertEqual(defaults.string(forKey: DefaultsKey.wordsLayout), "spokenCharacters")
    }

    func testAnUpdateWithTheFileIsLegacy() {
        let (store, defaults) = scratch()
        store.save(Replacements.defaults, to: ReplacementStore.file)
        defaults.set(true, forKey: DefaultsKey.symbolsAreReplacements)
        XCTAssertEqual(WordsLayout.resolve(store: store, defaults: defaults), .legacy)
        XCTAssertEqual(defaults.string(forKey: DefaultsKey.wordsLayout), "legacy")
    }

    func testAnEmptyListIsLegacy() throws {
        let (store, defaults) = scratch()
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: store.url(ReplacementStore.file))
        XCTAssertEqual(WordsLayout.resolve(store: store, defaults: defaults), .legacy)
    }

    func testABrokenFileIsLegacy() throws {
        let (store, defaults) = scratch()
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.url(ReplacementStore.file))
        XCTAssertNil(store.load([Replacement].self, from: ReplacementStore.file))
        XCTAssertEqual(WordsLayout.resolve(store: store, defaults: defaults), .legacy)
    }

    func testFileDeletedButPreferencesKeptIsNew() {
        let (store, defaults) = scratch()
        defaults.set(true, forKey: DefaultsKey.symbolsAreReplacements)
        defaults.set(true, forKey: DefaultsKey.onboardingCompleted)
        XCTAssertEqual(WordsLayout.resolve(store: store, defaults: defaults), .spokenCharacters)
    }

    func testASecondLaunchChangesNothing() throws {
        let (store, defaults) = scratch()
        XCTAssertEqual(WordsLayout.resolve(store: store, defaults: defaults), .spokenCharacters)
        store.save([Replacement(spoken: "my email", output: "name@example.com")], to: ReplacementStore.file)
        XCTAssertEqual(WordsLayout.resolve(store: store, defaults: defaults), .spokenCharacters, "own replacements saved since")

        let (old, oldDefaults) = scratch()
        store.save(Replacements.defaults, to: ReplacementStore.file)
        old.save(Replacements.defaults, to: ReplacementStore.file)
        XCTAssertEqual(WordsLayout.resolve(store: old, defaults: oldDefaults), .legacy)
        try FileManager.default.removeItem(at: old.url(ReplacementStore.file))
        XCTAssertEqual(WordsLayout.resolve(store: old, defaults: oldDefaults), .legacy, "the verdict stays")
    }

    func testTheCharactersFileMeansNewEvenWithoutPreferences() {
        let (store, defaults) = scratch()
        _ = SpokenCharacterStore(store: store)
        store.save([Replacement(spoken: "my email", output: "name@example.com")], to: ReplacementStore.file)
        XCTAssertEqual(WordsLayout.resolve(store: store, defaults: defaults), .spokenCharacters)
    }

    // MARK: Through AppState, as at launch

    func testANewInstallationStartsWithEmptyReplacementsAndTheCharacters() {
        let (store, defaults) = scratch()
        let app = AppState(prefs: Preferences(defaults: defaults), store: store)
        XCTAssertEqual(app.wordsLayout, .spokenCharacters)
        XCTAssertEqual(app.replacements.items, [])
        XCTAssertEqual(app.spokenCharacters?.items.map(\.spoken), SpokenCharacters.defaults.map(\.spoken))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(SpokenCharacterStore.file).path))
        XCTAssertTrue(app.prefs.spokenCharacters)
        // An own entry is saved; the next launch is still new, with it.
        app.replacements.upsert(Replacement(spoken: "my email", output: "name@example.com"))
        let next = AppState(prefs: Preferences(defaults: defaults), store: store)
        XCTAssertEqual(next.wordsLayout, .spokenCharacters)
        XCTAssertEqual(next.replacements.items.map(\.output), ["name@example.com"])
    }

    func testAnExistingInstallationIsLeftAsItWas() throws {
        let (store, defaults) = scratch()
        var own = Replacements.defaults
        own[0].enabled = false
        store.save(own, to: ReplacementStore.file)
        defaults.set(true, forKey: DefaultsKey.symbolsAreReplacements)
        defaults.set(false, forKey: DefaultsKey.spokenPunctuation)
        let before = try Data(contentsOf: store.url(ReplacementStore.file))
        let app = AppState(prefs: Preferences(defaults: defaults), store: store)
        XCTAssertEqual(app.wordsLayout, .legacy)
        XCTAssertNil(app.spokenCharacters)
        XCTAssertEqual(app.replacements.items, own)
        XCTAssertEqual(try Data(contentsOf: store.url(ReplacementStore.file)), before, "the file is not written")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(SpokenCharacterStore.file).path))
        XCTAssertFalse(app.prefs.spokenPunctuation, "their setting stays")
    }

    func testTheWordsSwitchesAreOnByDefault() {
        let (_, defaults) = scratch()
        let prefs = Preferences(defaults: defaults)
        XCTAssertTrue(prefs.spokenCharacters)
        XCTAssertTrue(prefs.removeFillers)
        XCTAssertTrue(prefs.spellingsEnabled)
        XCTAssertTrue(SpokenCharacters.defaults.allSatisfy(\.enabled))
    }

    func testThePromptModeTextPointsToWhereItIsSet() {
        XCTAssertTrue(AppMode.prompt.explanation(.legacy).contains("Prompt apps only"))
        XCTAssertTrue(AppMode.prompt.explanation(.spokenCharacters).contains("Spoken characters"))
        XCTAssertEqual(AppMode.writing.explanation(.legacy), AppMode.writing.explanation(.spokenCharacters))
    }

    func testListNote() {
        XCTAssertEqual(SpokenCharacters.listNote([]), "Only on its own")
        XCTAssertEqual(SpokenCharacters.listNote([.writing, .prompt]), "In sentences: Prompt and Writing")
    }
}
