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

    /// Where a new installation writes something else in a Writing app, on purpose.
    private let intended: [String: String] = [
        // Parakeet's spellings of “Semikolon” are part of the one entry, which works in Writing too.
        "Wort Sammy Colon weiter": "Wort; weiter",
        // Slash works in a sentence in every app now; a word after an article stays a word.
        "Projekte slash vypo": "Projekte/vypo", "Struktur slash Anna slash user": "Struktur/Anna/user",
        "Slash exit.": "/exit.", "Anna/slash user": "Anna/user", "Anna/slash": "Anna/", "Anna/ slash user": "Anna/user",
        "the folder slash docs": "the folder/docs", "Struktur slash Anna/slash user": "Struktur/Anna/user", "Geh in den Ordner Projekte slash Vypo slash Docs.": "Geh in den Ordner Projekte/Vypo/Docs.",
    ]

    /// The other two modes changed on purpose (`testEveryExpectedResult`); Writing is the path they all use now.
    func testWritingAppsWriteWhat030Wrote() {
        var checked = 0
        for (raw, lang) in corpus where !raw.lowercased().hasSuffix("slash x") {
            // The typographic switch no longer decides about spoken quotes, so it stays on here.
            let spellings = ["macOS", "iPhone"]
            let old = legacy(raw, .writing, lang, spellings: spellings)
            let now = new(raw, .writing, lang, spellings: spellings)
            XCTAssertEqual(now, intended[raw] ?? old, "“\(raw)” (\(lang.rawValue))")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 100)
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
        XCTAssertEqual(w("Projekte slash vypo"), "Projekte/vypo")
        XCTAssertEqual(w("Wirklich Fragezeichen"), "Wirklich?")
        XCTAssertEqual(w("er sagte Anführungszeichen auf hallo Anführungszeichen zu"), "er sagte „hallo“")
        XCTAssertEqual(w("He said open quote hi close quote", .en), "He said “hi”")
        // “Typographic quotes” is about the `"` the model wrote; spoken ones are the language's forms anyway.
        XCTAssertEqual(new("er sagte Anführungszeichen auf hallo Anführungszeichen zu", .writing, typographic: false), "er sagte „hallo“")
        XCTAssertEqual(new("er sagte \"hallo\"", .writing, typographic: false), "er sagte \"hallo\"")
        XCTAssertEqual(new("er sagte \"hallo\"", .writing), "er sagte „hallo“")
        XCTAssertEqual(new("er sagte \"hallo\"", .standard), "er sagte \"hallo\"")
    }

    /// The table of the brief, through `TextPipeline.process`, with the raw text of the analysis report. Nil: as said.
    func testEveryExpectedResult() {
        let cases: [(raw: String, lang: Lang, standard: String, prompt: String, writing: String)] = [
            ("Hallo Komma Welt.", .de, "Hallo, Welt.", "Hallo, Welt", "Hallo, Welt."),
            ("Komma.", .de, ",", ",", ","),
            ("Hallo Punkt.", .de, "Hallo.", "Hallo.", "Hallo."),
            ("Hallo Punkt wie geht es dir.", .de, "Hallo. Wie geht es dir.", "Hallo. Wie geht es dir", "Hallo. Wie geht es dir."),
            ("Wir treffen uns Punkt acht Uhr.", .de, "Wir treffen uns Punkt acht Uhr.", "Wir treffen uns Punkt acht Uhr", "Wir treffen uns Punkt acht Uhr."),
            ("Das ist ein wichtiger Punkt.", .de, "Das ist ein wichtiger Punkt.", "Das ist ein wichtiger Punkt", "Das ist ein wichtiger Punkt."),
            ("Pfad A Schrägstrich B.", .de, "Pfad A/B.", "Pfad A/B", "Pfad A/B."),
            ("Unterm Strich passt es.", .de, "Unterm Strich passt es.", "Unterm Strich passt es", "Unterm Strich passt es."),
            ("Erste Zeile, neue Zeile, zweite Zeile.", .de, "Erste Zeile\nzweite Zeile.", "Erste Zeile\nzweite Zeile", "Erste Zeile\nZweite Zeile."),
            ("Hier steht Anführungszeichen auf Hallo Anführungszeichen zu.", .de, "Hier steht „Hallo“", "Hier steht „Hallo“", "Hier steht „Hallo“"),
            ("Hello, comma, world.", .en, "Hello, world.", "Hello, world", "Hello, world."),
            ("A long period of time.", .en, "A long period of time.", "A long period of time", "A long period of time."),
        ]
        for c in cases {
            XCTAssertEqual(new(c.raw, .standard, c.lang), c.standard, "Standard: \(c.raw)")
            XCTAssertEqual(new(c.raw, .prompt, c.lang), c.prompt, "Prompt: \(c.raw)")
            XCTAssertEqual(new(c.raw, .writing, c.lang), c.writing, "Writing: \(c.raw)")
        }
    }

    func testALoneLineBreakSendsNoReturn() {
        let text = new("neue Zeile.", .prompt)
        XCTAssertEqual(text, "\n")
        XCTAssertFalse(ProfileTweaks.sendsReturn(mode: .prompt, autoEnter: true, inTextField: true, text: text))
        XCTAssertFalse(ProfileTweaks.sendsReturn(mode: .prompt, autoEnter: true, inTextField: true, text: new("neuer Absatz.", .prompt)))
        XCTAssertFalse(ProfileTweaks.sendsReturn(mode: .prompt, autoEnter: true, inTextField: true, text: " \n "))
        XCTAssertTrue(ProfileTweaks.sendsReturn(mode: .prompt, autoEnter: true, inTextField: true, text: "Hallo\n"))
    }

    func testNumbersAfterPunktAndKomma() {
        for mode in modes {
            for text in ["Punkt 8 Uhr", "Punkt zwölf", "Treffen um Punkt dreißig", "drei Komma fünf", "3 Komma 5", "Punkt Acht"] {
                XCTAssertEqual(new(text, mode), text, "\(mode)")
            }
            for text in ["Period one begins", "version full stop two", "two comma five", "Period 3"] {
                XCTAssertEqual(new(text, mode, .en), text, "\(mode)")
            }
            // Punctuation between them: not “directly followed”. Another word: a mark.
            XCTAssertEqual(new("Fertig Punkt, acht Uhr", mode), "Fertig. Acht Uhr", "\(mode)")
            XCTAssertEqual(new("Fertig Punkt nun acht", mode), "Fertig. Nun acht", "\(mode)")
            // Only period and comma: other marks are no decimal point or time.
            XCTAssertEqual(new("Wie viele Fragezeichen acht", mode), "Wie viele? Acht", "\(mode)")
        }
    }

    func testASingleCapitalLetterIsNoArticle() {
        for mode in modes {
            XCTAssertEqual(new("Pfad A Schrägstrich B", mode).hasPrefix("Pfad A/B"), true, "\(mode)")
            XCTAssertEqual(new("Hello a slash b", mode, .en), "Hello a slash b", "lowercase: the article")
            XCTAssertEqual(new("A dash of salt.  A long period.", mode == .prompt ? .standard : mode, .en), "A dash of salt. A long period.")
            XCTAssertEqual(new("A Schrägstrich B", mode), "A/B", "in German “A” is never an article")
        }
    }

    /// Symbols that connect words (`/`, `-`) ask only the word right before; marks also look past an adjective.
    func testConnectingSymbolsAreProtectedByTheDirectArticleOnly() {
        for mode in modes {
            XCTAssertEqual(new("the folder slash docs", mode, .en).hasPrefix("the folder/docs"), true, "\(mode)")
            XCTAssertEqual(new("Pfad Schrägstrich Ordner", mode), "Pfad/Ordner", "\(mode)")
            XCTAssertEqual(new("the slash command", mode, .en), "the slash command", "\(mode)")
            XCTAssertEqual(new("der Schrägstrich fehlt", mode), "der Schrägstrich fehlt", "\(mode)")
            // The long list of determiners stays.
            for text in ["Am Schrägstrich hängt es", "Beim Slash bleibt es"] { XCTAssertEqual(new(text, mode), text, "\(mode)") }
            // Marks keep the adjective.
            XCTAssertEqual(new("Das ist ein großes Fragezeichen", mode), "Das ist ein großes Fragezeichen", "\(mode)")
        }
        // The hyphen, once it is set to work in a sentence.
        var list = SpokenCharacters.defaults
        list[list.firstIndex { $0.output == "-" }!].alsoInSentence = true
        XCTAssertEqual(new("the long dash here", .standard, .en, characters: list), "the long-here")
        XCTAssertEqual(new("the dash here", .standard, .en, characters: list), "the dash here")
        // The same for an own entry with a symbol output; an output that is plain text has no rule.
        let own = [Replacement(spoken: "Pfad", output: "/")]
        XCTAssertEqual(new("Der Pfad bleibt", .standard, own: own), "Der Pfad bleibt")
        XCTAssertEqual(new("x Pfad y", .standard, own: own), "x/y")
        let text = [Replacement(spoken: "brb", output: "be right back")]
        XCTAssertEqual(new("the brb is here", .standard, .en, own: text), "the be right back is here")
    }

    func testNoCapitalAfterAnAbbreviation() {
        for mode in modes {
            for text in ["z. B. das", "z.B. das", "Das ist z. B. das", "Äpfel bzw. Birnen und mehr", "usw. und so", "ca. drei", "d. h. wir", "d.h. wir",
                         "u. a. das", "u.a. das", "etc. und", "Nr. acht", "Dr. med", "Prof. hier",
                         "bspw. das", "Das gilt z. T. auch hier", "z.T. auch"] {
                XCTAssertEqual(new(text, mode), text, "\(mode)")
            }
            for text in ["e.g. this", "i.e. this", "red etc. and", "cats vs. dogs", "Dr. who", "Mr. who", "Mrs. who", "Ms. who", "approx. three"] {
                XCTAssertEqual(new(text, mode, .en), text, "\(mode)")
            }
            // A real sentence end still gets its capital, spoken or from the model.
            XCTAssertEqual(new("Hallo Punkt wie geht es", mode), "Hallo. Wie geht es", "\(mode)")
            XCTAssertEqual(new("Ja. wir gehen", mode), "Ja. Wir gehen", "\(mode)")
            XCTAssertEqual(new("Hallo Punkt z. B. das", mode), "Hallo. Z. B. das", "\(mode)")
            XCTAssertEqual(new("Wirklich? ja", mode), "Wirklich? Ja", "\(mode)")
        }
        // `legacy` Writing uses the same path.
        XCTAssertEqual(legacy("z. B. das", .writing), "z. B. das")
    }

    func testPromptKeepsASpokenPeriodAtTheEnd() {
        XCTAssertEqual(new("Hallo Punkt.", .prompt), "Hallo.")
        XCTAssertEqual(new("Hallo Punkt", .prompt), "Hallo.")
        XCTAssertEqual(new("Hello full stop.", .prompt, .en), "Hello.")
        XCTAssertEqual(new("Erste neue Zeile zweite Punkt.", .prompt), "Erste\nzweite.")
        XCTAssertEqual(new("Hallo Welt.", .prompt), "Hallo Welt", "the model's period goes")
        XCTAssertEqual(new("Das ist ein wichtiger Punkt.", .prompt), "Das ist ein wichtiger Punkt", "a noun is no spoken period")
        // An own entry for the period counts too.
        let own = [Replacement(spoken: "Stopp", output: ".")]
        XCTAssertEqual(new("Hallo Stopp.", .prompt, own: own), "Hallo.")
        // “Only on its own”: the word stays, the model's period goes.
        var list = SpokenCharacters.defaults
        list[list.firstIndex { $0.output == "." }!].alsoInSentence = false
        XCTAssertEqual(new("Hallo Punkt.", .prompt, characters: list), "Hallo Punkt")
        // `legacy` stays as it was.
        XCTAssertEqual(legacy("Hallo Punkt.", .prompt), "Hallo Punkt")
    }

    func testPromptOnlyCountsAsAlsoInASentence() {
        let own = [Replacement(spoken: "Rohr", output: "|", inSentence: .promptOnly)]
        for mode in modes { XCTAssertEqual(new("a Rohr b", mode, own: own), "a | b", "\(mode)") }
        let never = [Replacement(spoken: "Rohr", output: "|", inSentence: .never)]
        for mode in modes {
            XCTAssertEqual(new("a Rohr b", mode, own: never), "a Rohr b", "\(mode)")
            XCTAssertEqual(new("Rohr", mode, own: never), "|", "\(mode)")
        }
        XCTAssertEqual(legacy("a slash b", .standard), "a slash b", "`legacy` keeps Prompt apps only")
    }

    // MARK: Intended changes

    func testColonIsNoLongerAColonInWriting() {
        XCTAssertEqual(legacy("Wort colon weiter", .writing, .en), "Wort: weiter", "0.3.0")
        XCTAssertEqual(new("Wort colon weiter", .writing, .en), "Wort colon weiter")
        XCTAssertEqual(new("colon", .writing, .en), "colon")
        // Anyone who wants it adds it.
        let own = SpokenCharacters.defaults + [SpokenCharacter(spoken: ["colon"], output: ":", alsoInSentence: false)]
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
        for mode in [AppMode.standard, .prompt, .writing] {
            XCTAssertEqual(new("Anführungszeichen auf", mode), "„", "the language's quote in every app")
            XCTAssertEqual(new("Open quote", mode, .en), "“")
        }
        var alone = SpokenCharacters.defaults
        alone[alone.firstIndex { $0.output == SpokenCharacters.closeQuote }!].alsoInSentence = false
        XCTAssertEqual(new("Anführungszeichen zu", .standard, characters: alone), "“", "the German closing form, also when only on its own")
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

    func testAlsoInASentencePerEntry() {
        var list = SpokenCharacters.defaults
        let dash = list.firstIndex { $0.output == "-" }!
        for mode in modes { XCTAssertEqual(new("Wort Bindestrich Wort", mode), "Wort Bindestrich Wort", "\(mode)") }
        list[dash].alsoInSentence = true
        for mode in modes { XCTAssertEqual(new("Wort Bindestrich Wort", mode, characters: list), "Wort-Wort", "\(mode)") }
        let period = list.firstIndex { $0.output == "." }!
        list[period].alsoInSentence = false
        for mode in modes {
            XCTAssertTrue(new("Das ist gut Punkt nächster", mode, characters: list).hasPrefix("Das ist gut Punkt nächster"), "\(mode)")
            XCTAssertEqual(new("Punkt", mode, characters: list), ".", "on its own in every mode")
        }
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
        for c in d { XCTAssertEqual(c.alsoInSentence, c.output != "-", Replacements.display(c.output)) }
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
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""alsoInSentence" : true"#))
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
        slash.alsoInSentence = false
        sc.upsert(slash)
        sc.delete(sc.items.first { $0.output == "." }!.id)
        sc.upsert(SpokenCharacter(spoken: ["Pfeil"], output: "→", alsoInSentence: true))
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

    func testTheModeTextsNameWhatIsLeft() {
        XCTAssertTrue(AppMode.prompt.explanation(.legacy).contains("Prompt apps only"))
        XCTAssertTrue(AppMode.writing.explanation(.legacy).contains("comma"))
        for mode in [AppMode.prompt, .writing] {
            let text = mode.explanation(.spokenCharacters)
            XCTAssertFalse(text.contains("Spoken characters") || text.contains("Replacements") || text.contains("comma"), text)
        }
    }

    func testListNote() {
        XCTAssertEqual(SpokenCharacters.listNote(false), "Only on its own")
        XCTAssertEqual(SpokenCharacters.listNote(true), "Also in a sentence")
    }

    // MARK: The file, with 0.4.1

    /// How 0.4.1 read an entry, copied from `SpokenCharacter.init(from:)` of that version.
    private struct Decoded041: Decodable {
        var id: UUID
        var spoken: [String]
        var output: String
        var enabled: Bool
        var inSentence: Set<AppMode>

        private enum CodingKeys: String, CodingKey { case id, spoken, output, enabled, inSentence }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            spoken = try c.decode([String].self, forKey: .spoken)
            output = try c.decode(String.self, forKey: .output)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
            inSentence = Set(try c.decodeIfPresent([AppMode].self, forKey: .inSentence) ?? [])
        }
    }

    private func decoded(_ modes: String, flag: String = "") throws -> SpokenCharacter {
        let json = #"[{"spoken":["x"],"output":"/","enabled":true"# + flag + #","inSentence":"# + modes + "}]"
        return try Store.decoder.decode([SpokenCharacter].self, from: Data(json.utf8))[0]
    }

    func testAnOldFileWithEveryShapeOfInSentence() throws {
        for shape in [#"["default"]"#, #"["prompt"]"#, #"["writing"]"#, #"["prompt","writing"]"#, #"["default","prompt","writing"]"#] {
            XCTAssertTrue(try decoded(shape).alsoInSentence, shape)
        }
        XCTAssertFalse(try decoded("[]").alsoInSentence)
        let missing = try Store.decoder.decode([SpokenCharacter].self, from: Data(#"[{"spoken":["x"],"output":"/"}]"#.utf8))
        XCTAssertFalse(missing[0].alsoInSentence)
    }

    func testTheNewFlagComesFirst() throws {
        XCTAssertFalse(try decoded(#"["writing"]"#, flag: #","alsoInSentence":false"#).alsoInSentence)
        XCTAssertTrue(try decoded("[]", flag: #","alsoInSentence":true"#).alsoInSentence)
    }

    func test041CanStillReadTheFile() throws {
        let data = try Store.encoder.encode(SpokenCharacters.defaults)
        let old = try Store.decoder.decode([Decoded041].self, from: data)
        XCTAssertEqual(old.map(\.output), SpokenCharacters.defaults.map(\.output))
        for (o, c) in zip(old, SpokenCharacters.defaults) {
            XCTAssertEqual(o.inSentence, c.alsoInSentence ? [.standard, .prompt, .writing] : [], Replacements.display(c.output))
        }
    }

    func testAnOldReplacementsFileWithEveryScope() throws {
        let json = #"[{"spoken":["a"],"output":"1","inSentence":"everywhere"},{"spoken":["b"],"output":"2","inSentence":"promptOnly"},"#
            + #"{"spoken":["c"],"output":"3","inSentence":"never"},{"spoken":"d","output":"4"}]"#
        let items = try Store.decoder.decode([Replacement].self, from: Data(json.utf8))
        XCTAssertEqual(items.map(\.inSentence.alsoInSentence), [true, true, false, true])
        XCTAssertEqual(items.map(\.inEveryApp.inSentence), [.everywhere, .everywhere, .never, .everywhere])
        // The file format didn't change: 0.4.1 reads `inSentence` as one of its three values.
        let text = String(decoding: try Store.encoder.encode(items), as: UTF8.self)
        for scope in ["everywhere", "promptOnly", "never"] { XCTAssertTrue(text.contains(#""inSentence" : "\#(scope)""#), scope) }
    }
}
