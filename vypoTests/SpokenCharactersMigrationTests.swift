import XCTest
@testable import vypo

/// 0.4.1: a Mac from before 0.4.0 (`legacy`) moves to Spoken characters, on the user's click.
@MainActor
final class SpokenCharactersMigrationTests: XCTestCase {
    private let fixedID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    private func noIDs(_ list: [SpokenCharacter]) -> [SpokenCharacter] {
        list.map { var c = $0; c.id = fixedID; return c }
    }

    /// The default entries of Replacements, as 0.3.0 left them.
    private var legacy: [Replacement] { Replacements.migrated(Replacements.defaults) }

    private func entry(_ list: [SpokenCharacter], _ output: String) -> SpokenCharacter? {
        list.first { $0.output == output }
    }

    private func edited(_ output: String, _ change: (inout Replacement) -> Void) -> [Replacement] {
        var items = legacy
        let i = items.firstIndex { $0.output == output }!
        change(&items[i])
        return items
    }

    // MARK: The move, a pure function

    func testEveryLegacyDefaultHasExactlyOneNewDefault() {
        XCTAssertEqual(Set(Replacements.defaults.map(\.output)).count, Replacements.defaults.count, "outputs unique")
        XCTAssertEqual(Set(SpokenCharacters.defaults.map(\.output)).count, SpokenCharacters.defaults.count, "outputs unique")
        for old in Replacements.defaults {
            let new = SpokenCharacters.defaults.filter { $0.output == old.output }
            XCTAssertEqual(new.count, 1, Replacements.display(old.output))
            // Every old spelling is in the new default, so an unchanged entry moves without extras.
            XCTAssertEqual(Replacements.union(new[0].spoken, old.spoken), new[0].spoken, Replacements.display(old.output))
        }
    }

    func testUnchangedDefaultsBecomeTheNewDefaults() {
        let items = legacy
        let m = SpokenCharacters.migration(from: items, spokenPunctuation: true)
        XCTAssertEqual(noIDs(m.characters), noIDs(SpokenCharacters.defaults))
        XCTAssertEqual(m.ownReplacements, [])
        XCTAssertEqual(m.moved.map(\.output).sorted(), Replacements.defaults.map(\.output).sorted())
        XCTAssertEqual(m.added.map(\.output), ["?", "!", SpokenCharacters.openQuote, SpokenCharacters.closeQuote])
        XCTAssertEqual(m.merged, [])
        // A moved entry keeps the id of the user's entry.
        XCTAssertEqual(entry(m.characters, "/")?.id, items.first { $0.output == "/" }?.id)
    }

    func testAnExtraSpellingIsKeptAfterTheDefaultOnes() {
        let items = edited(",") { $0.spoken.append("Beistrich") }
        let comma = entry(SpokenCharacters.migration(from: items, spokenPunctuation: true).characters, ",")
        XCTAssertEqual(comma?.spoken, ["Komma", "Comma", "Beistrich"])
        XCTAssertEqual(comma?.inSentence, [.writing])
        XCTAssertEqual(comma?.enabled, true)
    }

    func testATurnedOffDefaultStaysOff() {
        let items = edited("/") { $0.enabled = false }
        let m = SpokenCharacters.migration(from: items, spokenPunctuation: true)
        XCTAssertEqual(entry(m.characters, "/")?.enabled, false)
        XCTAssertEqual(entry(m.characters, "/")?.inSentence, [.prompt])
        XCTAssertTrue(m.characters.filter { $0.output != "/" }.allSatisfy(\.enabled))
    }

    func testAChangedScopeIsMapped() {
        var items = edited(".") { $0.inSentence = .everywhere }
        items[items.firstIndex { $0.output == "/" }!].inSentence = .never
        items[items.firstIndex { $0.output == "\n" }!].inSentence = .promptOnly
        let m = SpokenCharacters.migration(from: items, spokenPunctuation: true)
        XCTAssertEqual(entry(m.characters, ".")?.inSentence, [.standard, .prompt, .writing])
        XCTAssertEqual(entry(m.characters, "/")?.inSentence, [])
        XCTAssertEqual(entry(m.characters, "\n")?.inSentence, [.prompt])
        // Left as it came: the new default's modes.
        XCTAssertEqual(entry(m.characters, ":")?.inSentence, [.prompt, .writing])
        XCTAssertEqual(entry(m.characters, "\n\n")?.inSentence, [.standard, .prompt, .writing])
    }

    func testADeletedDefaultStaysDeleted() {
        let items = legacy.filter { $0.output != "-" && $0.output != "\n\n" }
        let m = SpokenCharacters.migration(from: items, spokenPunctuation: true)
        XCTAssertNil(entry(m.characters, "-"))
        XCTAssertNil(entry(m.characters, "\n\n"))
        XCTAssertEqual(m.characters.count, SpokenCharacters.defaults.count - 2)
        XCTAssertEqual(m.ownReplacements, [])
    }

    func testOwnSymbolEntriesStayInReplacements() {
        // Same output as a default but no spelling in common: no version. “Stern” has no default at all.
        let dot = Replacement(spoken: ["Pünktchen"], output: ".", inSentence: .never)
        let star = Replacement(spoken: ["Stern"], output: "*")
        let question = Replacement(spoken: ["Frage"], output: "?")
        let m = SpokenCharacters.migration(from: legacy + [dot, star, question], spokenPunctuation: true)
        XCTAssertEqual(m.ownReplacements, [dot, star, question])
        XCTAssertEqual(entry(m.characters, ".")?.spoken, ["Punkt", "Period", "Full stop"])
        XCTAssertEqual(entry(m.characters, "?")?.spoken, ["Fragezeichen", "Question mark"], "the new default is added anyway")
    }

    func testOwnNormalEntriesStayInTheirOrder() {
        let mail = Replacement(spoken: ["my email"], output: "name@example.com")
        let sign = Replacement(spoken: ["Gruß"], output: "Viele Grüße", enabled: false, inSentence: .promptOnly)
        let star = Replacement(spoken: ["Stern"], output: "*")
        let m = SpokenCharacters.migration(from: [mail] + legacy + [sign, star], spokenPunctuation: true)
        XCTAssertEqual(m.ownReplacements, [mail, sign, star])
        XCTAssertEqual(noIDs(m.characters), noIDs(SpokenCharacters.defaults))
    }

    func testTwoVersionsOfOneDefaultAreMerged() {
        let items = edited(",") { $0.enabled = false } + [Replacement(spoken: ["Comma", "Beistrich"], output: ",", inSentence: .promptOnly)]
        let m = SpokenCharacters.migration(from: items, spokenPunctuation: true)
        XCTAssertEqual(m.merged, [","])
        XCTAssertEqual(m.characters.filter { $0.output == "," }.count, 1)
        let comma = entry(m.characters, ",")
        XCTAssertEqual(comma?.spoken, ["Komma", "Comma", "Beistrich"])
        XCTAssertEqual(comma?.enabled, true, "on if either was on")
        XCTAssertEqual(comma?.inSentence, [.prompt, .writing], "the default's Writing and the changed one's Prompt")
        XCTAssertEqual(m.ownReplacements, [])

        // “Punkt” → “.” of one's own shares a spelling with the default: it is a version and merges too.
        let punkt = SpokenCharacters.migration(from: legacy + [Replacement(spoken: ["Punkt"], output: ".")], spokenPunctuation: true)
        XCTAssertEqual(punkt.merged, ["."])
        XCTAssertEqual(entry(punkt.characters, ".")?.inSentence, [.standard, .prompt, .writing])
    }

    func testSpokenPunctuationOffKeepsMarksOutOfWritingSentences() {
        let items = edited(",") { $0.inSentence = .everywhere }
        let m = SpokenCharacters.migration(from: items, spokenPunctuation: false)
        for c in m.characters where SpokenCharacters.mark(for: c.output) != nil {
            XCTAssertFalse(c.inSentence.contains(.writing), Replacements.display(c.output))
        }
        XCTAssertEqual(entry(m.characters, ",")?.inSentence, [.standard, .prompt])
        XCTAssertEqual(entry(m.characters, ";")?.inSentence, [.prompt])
        XCTAssertEqual(entry(m.characters, "?")?.inSentence, [])
        XCTAssertEqual(entry(m.characters, SpokenCharacters.openQuote)?.inSentence, [])
        // Line breaks are no marks: they keep Writing.
        XCTAssertEqual(entry(m.characters, "\n")?.inSentence, [.standard, .prompt, .writing])
        XCTAssertEqual(entry(m.characters, "/")?.inSentence, [.prompt])
    }

    func testWritingStaysOnAMarkWhenSpokenPunctuationWasOn() {
        let promptOnly = edited(",") { $0.inSentence = .promptOnly }
        let a = entry(SpokenCharacters.migration(from: promptOnly, spokenPunctuation: true).characters, ",")
        XCTAssertEqual(a?.inSentence, [.prompt, .writing])
        XCTAssertEqual(a?.enabled, true)

        let never = edited("/") { $0.inSentence = .never }
        XCTAssertEqual(entry(SpokenCharacters.migration(from: never, spokenPunctuation: true).characters, "/")?.inSentence, [],
                       "a slash is no mark: no Writing added")
    }

    func testAMarkSwitchedOffIsOnInWritingAppsOnlyWhenSpokenPunctuationWasOn() {
        let off = edited(",") { $0.enabled = false }
        let m = SpokenCharacters.migration(from: off, spokenPunctuation: true)
        XCTAssertEqual(entry(m.characters, ",")?.enabled, true)
        XCTAssertEqual(entry(m.characters, ",")?.inSentence, [.writing])

        // Off and a changed scope: still Writing only.
        let offPrompt = edited(",") { $0.enabled = false; $0.inSentence = .promptOnly }
        let n = SpokenCharacters.migration(from: offPrompt, spokenPunctuation: true)
        XCTAssertEqual(entry(n.characters, ",")?.inSentence, [.writing])

        // Not a mark: stays off.
        let slash = SpokenCharacters.migration(from: edited("/") { $0.enabled = false }, spokenPunctuation: true)
        XCTAssertEqual(entry(slash.characters, "/")?.enabled, false)
    }

    func testWithSpokenPunctuationOffAMarkGetsNoWriting() {
        let promptOnly = edited(",") { $0.inSentence = .promptOnly }
        let a = SpokenCharacters.migration(from: promptOnly, spokenPunctuation: false)
        XCTAssertEqual(entry(a.characters, ",")?.inSentence, [.prompt])

        let off = edited(",") { $0.enabled = false }
        let b = SpokenCharacters.migration(from: off, spokenPunctuation: false)
        XCTAssertEqual(entry(b.characters, ",")?.enabled, false)
        XCTAssertFalse(entry(b.characters, ",")?.inSentence.contains(.writing) ?? true)
    }

    func testASpellingTheUserRemovedStaysRemovedAndANewOneComes() {
        let items = edited("-") { $0.spoken.removeAll { $0 == "Strich" } }
            + [] // Bindestrich keeps Dash and Bindestrich
        let m = SpokenCharacters.migration(from: items, spokenPunctuation: true)
        XCTAssertEqual(entry(m.characters, "-")?.spoken, ["Bindestrich", "Dash"])

        // Semikolon: the new default has “Semi colon” and “Semi-colon”, which no old default had.
        let semi = edited(";") { $0.spoken.removeAll { $0 == "Siemikulon" } }
        let s = entry(SpokenCharacters.migration(from: semi, spokenPunctuation: true).characters, ";")?.spoken ?? []
        XCTAssertFalse(s.contains("Siemikulon"))
        XCTAssertTrue(s.contains("Semi colon") && s.contains("Semi-colon"))
        XCTAssertEqual(Set(s.map(Replacements.normalized)).count, s.count, "no duplicates")
        XCTAssertEqual(Array(s.prefix(7)), ["Semikolon", "Semicolon", "Semi-Kolon", "Semi Kolon", "Semikolen", "Sammy Colon", "Semikodon"])
    }

    func testDataOfVersion030UnchangedGivesExactlyTheNewDefaults() {
        for on in [true, false] {
            let m = SpokenCharacters.migration(from: Replacements.defaults, spokenPunctuation: on)
            if on {
                XCTAssertEqual(noIDs(m.characters), noIDs(SpokenCharacters.defaults))
            }
            XCTAssertEqual(m.ownReplacements, [])
            XCTAssertEqual(m.characters.map(\.output), SpokenCharacters.defaults.map(\.output))
            XCTAssertEqual(m.characters.map(\.spoken), SpokenCharacters.defaults.map(\.spoken))
        }
    }

    /// "Hallo Komma Welt" through the real pipeline in every mode, before (legacy context) and after (moved lists).
    /// Stands in for dictating by voice, which a test can't do.
    func testHalloKommaWeltBeforeAndAfterTheMove() {
        func run(_ items: [Replacement], punct: Bool, moved: Bool, _ mode: AppMode, _ lang: Lang = .de) -> String {
            let m = SpokenCharacters.migration(from: items, spokenPunctuation: punct)
            let ctx = moved
                ? PipelineContext(language: lang, replacements: m.ownReplacements, mode: mode, spokenCharacters: m.characters, spokenPunctuation: punct)
                : PipelineContext(language: lang, replacements: items, mode: mode, spokenCharacters: nil, spokenPunctuation: punct)
            return TextPipeline.process(lang == .de ? "Hallo Komma Welt" : "Hello comma world", ctx)
        }
        let cases: [(String, [Replacement])] = [
            ("untouched", legacy),
            ("Komma prompt only", edited(",") { $0.inSentence = .promptOnly }),
            ("Komma off", edited(",") { $0.enabled = false }),
        ]
        for (name, items) in cases {
            for punct in [true, false] {
                for mode in [AppMode.standard, .prompt, .writing] {
                    for lang in [Lang.de, .en] {
                        XCTAssertEqual(run(items, punct: punct, moved: true, mode, lang), run(items, punct: punct, moved: false, mode, lang),
                                       "\(name), spoken punctuation \(punct), \(mode), \(lang)")
                    }
                }
            }
        }
        // The two cases of the brief, spelled out.
        let promptOnly = cases[1].1
        XCTAssertEqual(run(promptOnly, punct: true, moved: true, .writing), "Hallo, Welt")
        XCTAssertEqual(run(promptOnly, punct: false, moved: true, .writing), "Hallo Komma Welt")
        XCTAssertEqual(run(promptOnly, punct: true, moved: true, .prompt), "Hallo, Welt")
        XCTAssertEqual(run(promptOnly, punct: true, moved: true, .standard), "Hallo Komma Welt")
        let off = cases[2].1
        XCTAssertEqual(run(off, punct: true, moved: true, .writing), "Hallo, Welt")
        XCTAssertEqual(run(off, punct: true, moved: true, .prompt), "Hallo Komma Welt")
        XCTAssertEqual(run(off, punct: false, moved: true, .writing), "Hallo Komma Welt")
    }

    // MARK: Backup and the move through AppState

    private func scratch() -> (Store, UserDefaults) {
        let store = Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent("vypo-move-\(UUID().uuidString)"))
        let suite = "vypo.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: store.directory) }
        return (store, defaults)
    }

    private let when = Date(timeIntervalSince1970: 1_793_370_301)   // 2026-10-30 14:25:01 UTC

    func testTheBackupHoldsTheFileAndThePreferences() throws {
        let (store, defaults) = scratch()
        let items = legacy + [Replacement(spoken: ["my email"], output: "name@example.com")]
        store.save(items, to: ReplacementStore.file)
        let original = try Data(contentsOf: store.url(ReplacementStore.file))
        let prefs = Preferences(defaults: defaults)
        prefs.spokenPunctuation = false
        defaults.set(WordsLayout.legacy.rawValue, forKey: DefaultsKey.wordsLayout)

        let dir = try SpokenCharactersBackup.write(store: store, defaults: defaults, replacements: items, now: when,
                                                   timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(dir.lastPathComponent, "spoken-characters-2026-10-30-142501")
        XCTAssertEqual(dir.deletingLastPathComponent().lastPathComponent, "Backups")
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent(ReplacementStore.file)), original)
        let saved = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("preferences.json"))) as? [String: Any])
        XCTAssertEqual(saved["wordsLayout"] as? String, "legacy")
        XCTAssertEqual(saved["spokenPunctuation"] as? Bool, false)
        XCTAssertEqual(saved["spokenCharacters"] as? Bool, true)
        XCTAssertEqual(saved["typographicQuotes"] as? Bool, true)

        // The same second again: a folder of its own.
        let again = try SpokenCharactersBackup.write(store: store, defaults: defaults, replacements: items, now: when,
                                                     timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(again.lastPathComponent, "spoken-characters-2026-10-30-142501-2")
    }

    /// A legacy Mac: changed and deleted defaults, an own entry, “Spoken punctuation” off.
    private func legacyMac() -> (Store, UserDefaults, [Replacement]) {
        let (store, defaults) = scratch()
        var items = legacy.filter { $0.output != "-" }
        items[items.firstIndex { $0.output == "/" }!].spoken.append("Strich zwei")
        items.append(Replacement(spoken: ["my email"], output: "name@example.com"))
        store.save(items, to: ReplacementStore.file)
        defaults.set(true, forKey: DefaultsKey.symbolsAreReplacements)
        defaults.set(false, forKey: DefaultsKey.spokenPunctuation)
        return (store, defaults, items)
    }

    func testTheMoveAppliesAtOnceAndStays() throws {
        let (store, defaults, items) = legacyMac()
        let before = try Data(contentsOf: store.url(ReplacementStore.file))
        let app = AppState(prefs: Preferences(defaults: defaults), store: store)
        XCTAssertEqual(app.wordsLayout, .legacy)
        let achievements = app.achievements.state
        let expected = SpokenCharacters.migration(from: items, spokenPunctuation: false)

        try app.moveToSpokenCharacters(now: when)

        XCTAssertEqual(app.wordsLayout, .spokenCharacters)
        XCTAssertEqual(defaults.string(forKey: DefaultsKey.wordsLayout), "spokenCharacters")
        // The added defaults get new ids each time.
        XCTAssertEqual(noIDs(app.spokenCharacters?.items ?? []), noIDs(expected.characters))
        XCTAssertNil(app.spokenCharacters?.items.first { $0.output == "-" }, "deleted stays deleted")
        XCTAssertEqual(app.replacements.items.map(\.output), ["name@example.com"])
        XCTAssertTrue(app.prefs.spokenCharacters)
        XCTAssertFalse(app.prefs.spokenPunctuation, "the old key stays as it was")
        XCTAssertEqual(app.achievements.state, achievements, "the move is no new own replacement")

        // The backup has the file as it was before the move.
        let backups = try FileManager.default.contentsOfDirectory(at: store.url(SpokenCharactersBackup.folder), includingPropertiesForKeys: nil)
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try Data(contentsOf: backups[0].appendingPathComponent(ReplacementStore.file)), before)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backups[0].appendingPathComponent("preferences.json").path))

        // The pipeline gets the characters (as `AppCoordinator` builds its context).
        let ctx = PipelineContext(language: .de, replacements: app.replacements.items, mode: .writing,
                                  spokenCharacters: app.spokenCharacters.map { app.prefs.spokenCharacters ? $0.items : [] },
                                  spokenPunctuation: app.prefs.spokenPunctuation)
        XCTAssertEqual(TextPipeline.process("Hallo neue Zeile Welt", ctx), "Hallo\nWelt")

        // The next launch reads the same.
        let next = AppState(prefs: Preferences(defaults: defaults), store: store)
        XCTAssertEqual(next.wordsLayout, .spokenCharacters)
        XCTAssertEqual(next.spokenCharacters?.items, app.spokenCharacters?.items)
        XCTAssertEqual(next.replacements.items, app.replacements.items)

        // A second move does nothing.
        try app.moveToSpokenCharacters(now: when)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.url(SpokenCharactersBackup.folder).path).count, 1)
    }

    func testNoBackupNoMove() throws {
        let (store, defaults, items) = legacyMac()
        let before = try Data(contentsOf: store.url(ReplacementStore.file))
        // A file where the backup folder should go: the backup can't be written.
        try Data("x".utf8).write(to: store.url(SpokenCharactersBackup.folder))
        let app = AppState(prefs: Preferences(defaults: defaults), store: store)

        XCTAssertThrowsError(try app.moveToSpokenCharacters(now: when)) { XCTAssertEqual($0 as? SpokenCharactersMoveError, .backup) }

        XCTAssertEqual(app.wordsLayout, .legacy)
        XCTAssertNil(app.spokenCharacters)
        XCTAssertEqual(app.replacements.items, items)
        XCTAssertEqual(try Data(contentsOf: store.url(ReplacementStore.file)), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(SpokenCharacterStore.file).path))
        XCTAssertEqual(defaults.string(forKey: DefaultsKey.wordsLayout), "legacy")
    }

    func testTheHintIsShownUntilNotNow() {
        let (_, defaults) = scratch()
        let prefs = Preferences(defaults: defaults)
        XCTAssertFalse(prefs.spokenCharactersHintDismissed)
        prefs.spokenCharactersHintDismissed = true
        XCTAssertTrue(Preferences(defaults: defaults).spokenCharactersHintDismissed)
    }

    // MARK: “Komma” in English

    func testTheSummaryShowsTheLanguageOfTheUIFirst() {
        let d = SpokenCharacters.defaults
        XCTAssertEqual(entry(d, ",")?.summary(for: .en), "“Comma”, “Komma”")
        XCTAssertEqual(entry(d, ",")?.summary(for: .de), "“Komma”, “Comma”")
        XCTAssertEqual(entry(d, ",")?.summary(for: .de, quote: { "„\($0)“" }), "„Komma“, „Comma“")
        XCTAssertEqual(entry(d, ".")?.summary(for: .en), "“Period”, “Full stop” …")
        XCTAssertEqual(entry(d, ";")?.summary(for: .en), "“Semicolon”, “Semi colon” …")
        XCTAssertEqual(entry(d, ";")?.summary(for: .de), "“Semikolon”, “Semi-Kolon” …")
        XCTAssertEqual(entry(d, "/")?.summary(for: .de), "“Schrägstrich”, “Slash”")
        XCTAssertEqual(entry(d, SpokenCharacters.openQuote)?.summary(for: .en), "“Open quote”, “Anführungszeichen auf”")
        XCTAssertEqual(entry(d, ":")?.summary(for: .en), "“Doppelpunkt”")
        // A spelling of no known language keeps its place among the others.
        let own = SpokenCharacter(spoken: ["Beistrich", "Komma", "Comma"], output: ",", inSentence: [.writing])
        XCTAssertEqual(own.summary(for: .en), "“Comma”, “Beistrich” …")
        // Only the display: the stored order stays.
        XCTAssertEqual(entry(d, ",")?.spoken, ["Komma", "Comma"])
    }
}
