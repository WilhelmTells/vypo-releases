import XCTest
@testable import vypo

/// 0.4.0: achievements, the data without the card.
@MainActor
final class AchievementsTests: XCTestCase {
    private var berlin: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }

    private func scratch() -> (Store, UserDefaults) {
        let store = Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent("vypo-ach-\(UUID().uuidString)"))
        let suite = "vypo.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: store.directory) }
        return (store, defaults)
    }

    /// A store filled from `state`, as a first launch would.
    private func store(_ state: AchievementState = AchievementState(), collecting: Bool = true) -> (AchievementStore, Store) {
        let (s, _) = scratch()
        return (AchievementStore(store: s, calendar: berlin, collecting: collecting) { state }, s)
    }

    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    private func facts(_ iso: String, words: Int = 10, seconds: Double = 5, language: Lang = .de, app: String? = "com.example.a",
                       handsFree: Bool = false, vypo: Bool = false) -> DictationFacts {
        DictationFacts(date: date(iso), words: words, seconds: seconds, language: language, bundleID: app,
                       handsFree: handsFree, mentionsVypo: vypo)
    }

    private func level(_ a: AchievementStore, _ id: AchievementID) -> Int { a.status(id).level }

    // MARK: The list

    func testTheListAsDecided() {
        XCTAssertEqual(AchievementID.allCases.count, 20)
        XCTAssertEqual(Achievements.definitions.map(\.id), AchievementID.allCases)
        let tiers = Dictionary(uniqueKeysWithValues: Achievements.definitions.map { ($0.id, $0.thresholds) })
        XCTAssertEqual(tiers[.tales], [10, 100, 1_000, 10_000])
        XCTAssertEqual(tiers[.timeBack], [60, 600, 1_440, 3_000, 6_000])
        XCTAssertEqual(tiers[.longBreath], [60, 180, 300])
        XCTAssertEqual(tiers[.wordCollector], [10, 50, 100])
        XCTAssertEqual(tiers[.bookshelf], [17_000, 95_000, 783_000])
        XCTAssertEqual(tiers[.regular], [7, 30, 100])
        XCTAssertEqual(tiers[.chatterbox], [50, 100, 200])
        XCTAssertEqual(tiers[.wellTravelled], [3, 5, 10])
        XCTAssertEqual(Achievements.definitions.filter { $0.kind == .discover }.count, 8)
        XCTAssertEqual(Achievements.definitions.filter { $0.kind == .curious }.map(\.id),
                       [.nightOwl, .earlyBird, .threeTongues, .chatterbox, .sayMyName, .wellTravelled])
        XCTAssertEqual(Achievements.definitions.reduce(0) { $0 + $1.tiers }, 39, "the table has 39 tiers")
    }

    func testEveryThresholdAndTier() {
        for d in Achievements.definitions {
            XCTAssertEqual(d.level(for: 0), 0, "\(d.id)")
            for (i, t) in d.thresholds.enumerated() {
                if d.above {
                    XCTAssertEqual(d.level(for: t), i, "\(d.id) at \(t)")
                    XCTAssertEqual(d.level(for: t + 0.5), i + 1, "\(d.id) above \(t)")
                } else {
                    XCTAssertEqual(d.level(for: t - 1), i, "\(d.id) below \(t)")
                    XCTAssertEqual(d.level(for: t), i + 1, "\(d.id) at \(t)")
                }
            }
        }
    }

    func testEachAchievementFromItsData() {
        var s = AchievementState()
        s.dictations = 1_000
        s.maxGlossaryEntries = 50
        s.flags = Set(AchievementFlag.allCases)
        s.languages = ["de", "en"]
        s.maxSavedMinutes = 1_440
        s.maxRecordingSeconds = 181
        s.maxWords = 95_000
        s.days = Set((1...30).map { String(format: "2026-11-%02d", $0) })
        s.maxDayDictations = 100
        s.apps = ["a", "b", "c", "d", "e"]
        let (a, _) = store(s)
        let expected: [AchievementID: Int] = [
            .firstWords: 1, .wordKeeper: 1, .bookworm: 1, .swapArtist: 1, .rightTool: 1, .handsFree: 1, .secondThoughts: 1,
            .polyglot: 1, .tales: 3, .timeBack: 3, .longBreath: 2, .wordCollector: 2, .bookshelf: 2, .regular: 2,
            .nightOwl: 1, .earlyBird: 1, .threeTongues: 1, .chatterbox: 2, .sayMyName: 1, .wellTravelled: 2,
        ]
        for id in AchievementID.allCases { XCTAssertEqual(level(a, id), expected[id], "\(id)") }
        XCTAssertEqual(a.readyCount, 20, "all reached from data are ready")
        XCTAssertEqual(a.stampedCount, 0)
    }

    // MARK: Dictations

    func testADictationAndItsFacts() {
        let (a, _) = store()
        XCTAssertEqual(a.status(.firstWords).level, 0)
        a.dictated(facts("2026-11-02T10:00:00Z", seconds: 61, handsFree: true, vypo: true), savedMinutes: 61, words: 17_000)
        XCTAssertEqual(level(a, .firstWords), 1)
        XCTAssertEqual(level(a, .handsFree), 1)
        XCTAssertEqual(level(a, .sayMyName), 1)
        XCTAssertEqual(level(a, .longBreath), 1)
        XCTAssertEqual(level(a, .timeBack), 1)
        XCTAssertEqual(level(a, .bookshelf), 1)
        XCTAssertEqual(level(a, .tales), 0)
        XCTAssertEqual(a.status(.tales).value, 1)
        XCTAssertEqual(a.status(.tales).next, 10)
        XCTAssertEqual(a.status(.tales).progress, 0.1, accuracy: 0.0001)
        XCTAssertEqual(level(a, .nightOwl), 0)
    }

    func testLongBreathIsLongerThan() {
        let (a, _) = store()
        a.dictated(facts("2026-11-02T10:00:00Z", seconds: 60), savedMinutes: 0, words: 1)
        XCTAssertEqual(level(a, .longBreath), 0, "exactly a minute is not longer")
        a.dictated(facts("2026-11-02T10:01:00Z", seconds: 300.4), savedMinutes: 0, words: 1)
        XCTAssertEqual(level(a, .longBreath), 3)
    }

    func testLanguagesNeedFourWords() {
        let (a, _) = store()
        a.dictated(facts("2026-11-02T10:00:00Z", words: 10, language: .de), savedMinutes: 0, words: 10)
        a.dictated(facts("2026-11-02T10:01:00Z", words: 3, language: .en), savedMinutes: 0, words: 13)
        XCTAssertEqual(level(a, .polyglot), 0, "three English words don't count")
        a.dictated(facts("2026-11-02T10:02:00Z", words: 4, language: .en), savedMinutes: 0, words: 17)
        XCTAssertEqual(level(a, .polyglot), 1)
        XCTAssertEqual(level(a, .threeTongues), 0)
        a.dictated(facts("2026-11-03T10:00:00Z", words: 5, language: .fr), savedMinutes: 0, words: 22)
        XCTAssertEqual(level(a, .threeTongues), 0, "three languages, but not on one day")
        a.dictated(facts("2026-11-03T10:01:00Z", words: 5, language: .de), savedMinutes: 0, words: 27)
        a.dictated(facts("2026-11-03T10:02:00Z", words: 5, language: .en), savedMinutes: 0, words: 32)
        XCTAssertEqual(level(a, .threeTongues), 1)
    }

    func testAppsDaysAndChatterbox() {
        let (a, _) = store()
        for i in 0..<10 { a.dictated(facts("2026-11-02T10:00:\(String(format: "%02d", i))Z", app: "app.\(i)"), savedMinutes: 0, words: i) }
        XCTAssertEqual(level(a, .wellTravelled), 3)
        for d in 1...7 { a.dictated(facts(String(format: "2026-12-%02dT12:00:00Z", d), app: nil), savedMinutes: 0, words: 1) }
        XCTAssertEqual(level(a, .regular), 1, "8 days")
        let (b, _) = store()
        for i in 0..<200 {
            b.dictated(DictationFacts(date: date("2026-11-02T08:00:00Z").addingTimeInterval(Double(i) * 60), words: 5, seconds: 2,
                                      language: .de), savedMinutes: 0, words: i)
        }
        XCTAssertEqual(level(b, .chatterbox), 3)
        XCTAssertEqual(level(b, .tales), 2)
    }

    func testNightOwlAndEarlyBirdWindows() {
        // Berlin is UTC+1 in November.
        let cases: [(String, Bool, Bool)] = [
            ("2026-11-01T22:59:59Z", false, false),   // 23:59
            ("2026-11-01T23:00:00Z", true, false),    // 0:00
            ("2026-11-02T02:59:59Z", true, false),    // 3:59
            ("2026-11-02T03:00:00Z", false, true),    // 4:00
            ("2026-11-02T04:59:59Z", false, true),    // 5:59
            ("2026-11-02T05:00:00Z", false, false),   // 6:00
        ]
        for (iso, owl, bird) in cases {
            let (a, _) = store()
            a.dictated(facts(iso), savedMinutes: 0, words: 1)
            XCTAssertEqual(level(a, .nightOwl), owl ? 1 : 0, iso)
            XCTAssertEqual(level(a, .earlyBird), bird ? 1 : 0, iso)
        }
    }

    func testDayChangeAndDaylightSaving() {
        let (a, _) = store()
        // 25 Oct 2026: clocks go back at 3:00 CEST. 0:30 CEST and 23:30 CET are two local days.
        a.dictated(facts("2026-10-24T22:30:00Z"), savedMinutes: 0, words: 1)   // 25 Oct, 0:30 CEST
        a.dictated(facts("2026-10-25T00:30:00Z"), savedMinutes: 0, words: 2)   // 25 Oct, 2:30 CEST
        a.dictated(facts("2026-10-25T01:30:00Z"), savedMinutes: 0, words: 3)   // 25 Oct, 2:30 CET (the hour again)
        a.dictated(facts("2026-10-25T22:30:00Z"), savedMinutes: 0, words: 4)   // 25 Oct, 23:30 CET
        XCTAssertEqual(a.state.days, ["2026-10-25"])
        XCTAssertEqual(a.state.today?.dictations, 4)
        a.dictated(facts("2026-10-25T23:30:00Z"), savedMinutes: 0, words: 5)   // 26 Oct, 0:30 CET
        XCTAssertEqual(a.state.days, ["2026-10-25", "2026-10-26"])
        XCTAssertEqual(a.state.today, AchievementState.Today(day: "2026-10-26", dictations: 1, languages: ["de"]))
        XCTAssertEqual(a.state.maxDayDictations, 4, "the busiest day stays")
        // 29 Mar 2026: clocks go forward at 2:00. 1:30 UTC is 3:30 CEST (Night Owl), 2:30 UTC is 4:30 (Early Bird).
        let (b, _) = store()
        b.dictated(facts("2026-03-29T01:30:00Z"), savedMinutes: 0, words: 1)
        XCTAssertEqual(level(b, .nightOwl), 1)
        XCTAssertEqual(level(b, .earlyBird), 0)
        b.dictated(facts("2026-03-29T02:30:00Z"), savedMinutes: 0, words: 1)
        XCTAssertEqual(level(b, .earlyBird), 1)
        XCTAssertEqual(b.state.days, ["2026-03-29"])
    }

    // MARK: Ready, stamp, never sinking

    func testReadyStampNewTierReady() {
        let (a, file) = store()
        XCTAssertFalse(a.stamp(.firstWords), "locked: nothing to stamp")
        for i in 0..<10 { a.dictated(facts("2026-11-02T10:00:\(String(format: "%02d", i))Z"), savedMinutes: 0, words: i) }
        XCTAssertEqual(a.all.filter(\.isReady).map(\.id), [.firstWords, .tales])
        XCTAssertTrue(a.stamp(.tales, now: date("2026-11-03T09:00:00Z")))
        XCTAssertFalse(a.stamp(.tales), "stamped twice")
        let tales = a.status(.tales)
        XCTAssertFalse(tales.isReady)
        XCTAssertEqual(tales.stampedLevel, 1)
        XCTAssertEqual(tales.stampedOn, "2026-11-03")
        XCTAssertEqual(a.readyCount, 1, "stamping one doesn't stamp the others")
        XCTAssertEqual(a.stampedCount, 1)
        for i in 0..<90 { a.dictated(facts("2026-11-04T10:00:00Z").withOffset(i), savedMinutes: 0, words: i) }
        XCTAssertTrue(a.status(.tales).isReady, "a new tier is ready again")
        XCTAssertEqual(a.status(.tales).level, 2)
        XCTAssertEqual(a.status(.tales).stampedLevel, 1)
        a.stamp(.tales, now: date("2026-11-05T09:00:00Z"))
        XCTAssertEqual(a.state.stamps[.tales], ["2026-11-03", "2026-11-05"])
        // Saved, and read back by the next launch without filling again.
        let again = AchievementStore(store: file, calendar: berlin, collecting: true) { XCTFail("no second fill"); return AchievementState() }
        XCTAssertEqual(again.state, a.state)
    }

    func testStampingTwoTiersAtOnce() {
        var s = AchievementState()
        s.dictations = 150
        let (a, _) = store(s)
        XCTAssertEqual(a.status(.tales).level, 2)
        a.stamp(.tales, now: date("2026-11-03T09:00:00Z"))
        XCTAssertEqual(a.state.stamps[.tales], ["2026-11-03", "2026-11-03"])
    }

    func testNeverSinking() {
        let (a, _) = store()
        a.glossaryCount(12)
        XCTAssertEqual(level(a, .wordCollector), 1)
        a.glossaryCount(3)
        XCTAssertEqual(a.state.maxGlossaryEntries, 12, "the highest stays")
        XCTAssertEqual(level(a, .wordCollector), 1)
        a.dictated(facts("2026-11-02T10:00:00Z"), savedMinutes: 70, words: 20_000)
        a.dictated(facts("2026-11-02T10:01:00Z"), savedMinutes: 30, words: 5)
        XCTAssertEqual(a.state.maxSavedMinutes, 70)
        XCTAssertEqual(a.state.maxWords, 20_000)
        XCTAssertEqual(level(a, .timeBack), 1)
        XCTAssertEqual(level(a, .bookshelf), 1)
    }

    // MARK: Through AppState: undo, collect stats, reset, the hooks

    private func app(collect: Bool = true) -> (AppState, Store) {
        let (s, defaults) = scratch()
        defaults.set(collect, forKey: DefaultsKey.collectStats)
        return (AppState(prefs: Preferences(defaults: defaults), store: s, calendar: berlin), s)
    }

    private func insertion(_ text: String = "Hallo das ist ein Test", at iso: String = "2026-11-02T10:00:00Z", seconds: Double = 30,
                           handsFree: Bool = false) -> LastInsertion {
        LastInsertion(text: text, pid: nil, date: date(iso), language: .de, historyID: nil,
                      words: text.split(separator: " ").count, recordingSeconds: seconds, bundleID: "com.example.notes",
                      handsFree: handsFree)
    }

    func testUndoKeepsCountingAndIsSecondThoughts() {
        let (app, _) = app()
        let last = insertion(String(repeating: "Wort ", count: 200), seconds: 10)
        app.count(last)
        let saved = app.achievements.state.maxSavedMinutes
        XCTAssertGreaterThan(saved, 0)
        app.uncount(last)
        XCTAssertEqual(app.achievements.state.dictations, 1, "undo doesn't subtract")
        XCTAssertEqual(app.achievements.status(.secondThoughts).level, 1)
        XCTAssertEqual(app.achievements.state.maxSavedMinutes, saved, "Time Back keeps its highest")
        XCTAssertEqual(app.stats.allTime, 0, "the stats go down, as before")
        XCTAssertEqual(app.achievements.state.days, ["2026-11-02"])
    }

    func testHandsFreeOnlyFromACountedDictation() {
        let (app, _) = app()
        app.count(insertion())
        XCTAssertEqual(app.achievements.status(.handsFree).level, 0)
        app.count(insertion(handsFree: true))
        XCTAssertEqual(app.achievements.status(.handsFree).level, 1)
    }

    func testSayMyNameKeepsNoText() throws {
        let (app, s) = app()
        app.count(insertion("Das schreibt vypo für mich geheimnis4711"))
        XCTAssertEqual(app.achievements.status(.sayMyName).level, 1)
        let file = try String(contentsOf: s.url(AchievementStore.file), encoding: .utf8)
        XCTAssertFalse(file.contains("geheimnis4711"))
        XCTAssertFalse(file.contains("schreibt"))
        XCTAssertFalse(file.lowercased().contains("vypo"), "only a flag: \(file)")
        XCTAssertTrue(file.contains("sayMyName"))
        XCTAssertFalse(file.contains("10:00"), "no times of day")
        XCTAssertTrue(Achievements.mentionsVypo("Die vypo-App"))
        XCTAssertTrue(Achievements.mentionsVypo("VYPO."))
        XCTAssertFalse(Achievements.mentionsVypo("vypos"))
        XCTAssertFalse(Achievements.mentionsVypo("Vipo"))
    }

    func testCollectStatsOffRecordsNothing() {
        let (app, s) = app(collect: false)
        app.count(insertion())
        app.uncount(insertion())
        app.glossary.add(term: "TikTok")
        app.replacements.upsert(Replacement(spoken: "my email", output: "name@example.com"))
        app.achievementReached(.documentImport)
        XCTAssertEqual(app.achievements.all.filter { !$0.isLocked }.count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: s.url(AchievementStore.file).path), "not even the file")
        // Switched on: never filled, so filled now, with what the files tell (glossary, own replacement).
        app.prefs.collectStats = true
        app.collectStatsSwitchedOn()
        XCTAssertEqual(app.achievements.status(.wordKeeper).level, 1)
        XCTAssertEqual(app.achievements.status(.swapArtist).level, 1)
        XCTAssertEqual(app.achievements.status(.firstWords).level, 0, "the dictation while off isn't caught up")
        XCTAssertEqual(app.achievements.status(.bookworm).level, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: s.url(AchievementStore.file).path))
    }

    func testCollectStatsOffAgainAndOnCatchesUpFromTheFiles() {
        let (app, _) = app()
        app.count(insertion())
        app.prefs.collectStats = false
        app.glossary.add(term: "TikTok")
        app.profiles.update(AppProfile(bundleID: "com.example.chat", appName: "Chat", mode: .prompt))
        XCTAssertEqual(app.achievements.status(.wordKeeper).level, 0)
        XCTAssertEqual(app.achievements.status(.rightTool).level, 0)
        app.prefs.collectStats = true
        app.collectStatsSwitchedOn()
        XCTAssertEqual(app.achievements.status(.wordKeeper).level, 1)
        XCTAssertEqual(app.achievements.status(.rightTool).level, 1)
        XCTAssertEqual(app.achievements.state.dictations, 1)
    }

    func testResetStatsLeavesTheAchievements() {
        let (app, _) = app()
        app.count(insertion(String(repeating: "Wort ", count: 100)))
        app.achievements.stamp(.firstWords)
        let before = app.achievements.state
        app.resetStats()
        XCTAssertEqual(app.stats.allTime, 0)
        XCTAssertEqual(app.level.xpWords, 0)
        XCTAssertEqual(app.achievements.state, before)
    }

    func testTheHooks() {
        let (app, _) = app()
        XCTAssertEqual(app.wordsLayout, .spokenCharacters)
        // Swap Artist: only a new own entry.
        app.replacements.restoreDefaults()
        XCTAssertEqual(app.achievements.status(.swapArtist).level, 0, "restore is no own entry")
        app.replacements.upsert(Replacement(spoken: "my email", output: "name@example.com"))
        XCTAssertEqual(app.achievements.status(.swapArtist).level, 1)
        // Right Tool: only a switch to Prompt or Writing.
        app.profiles.add(appAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"))
        app.profiles.update(AppProfile(bundleID: "com.example.x", appName: "X", mode: .excluded))
        XCTAssertEqual(app.achievements.status(.rightTool).level, 0)
        app.profiles.update(AppProfile(bundleID: "com.example.x", appName: "X", mode: .writing))
        XCTAssertEqual(app.achievements.status(.rightTool).level, 1)
        // Word Keeper and Word Collector from the glossary's count.
        for i in 0..<10 { app.glossary.add(term: "Term\(i)") }
        XCTAssertEqual(app.achievements.status(.wordKeeper).level, 1)
        XCTAssertEqual(app.achievements.status(.wordCollector).level, 1)
        // Bookworm: the import sheet reports it.
        app.achievementReached(.documentImport)
        XCTAssertEqual(app.achievements.status(.bookworm).level, 1)
    }

    func testEditingADefaultReplacementIsNoSwapArtist() {
        let (s, defaults) = scratch()
        store(s, Replacements.defaults)
        let app = AppState(prefs: Preferences(defaults: defaults), store: s, calendar: berlin)
        XCTAssertEqual(app.wordsLayout, .legacy)
        XCTAssertEqual(app.achievements.status(.swapArtist).level, 0)
        var slash = app.replacements.items.first { $0.output == "/" }!
        slash.inSentence = .everywhere
        slash.spoken = ["Slash", "Strich zwei"]
        app.replacements.upsert(slash)
        XCTAssertEqual(app.achievements.status(.swapArtist).level, 0)
    }

    private func store<T: Encodable>(_ s: Store, _ value: T, as name: String = ReplacementStore.file) { s.save(value, to: name) }

    // MARK: The fill from the existing data

    func testAFreshInstallationStartsLockedAndFilled() throws {
        let (app, s) = app()
        XCTAssertTrue(app.achievements.state.seeded)
        XCTAssertEqual(app.achievements.all.filter { !$0.isLocked }.count, 0)
        XCTAssertEqual(app.achievements.hiddenCuriousLeft, 6)
        XCTAssertTrue(FileManager.default.fileExists(atPath: s.url(AchievementStore.file).path))
    }

    /// Example files of an existing installation.
    private func existing(_ s: Store, history: Bool = true) {
        let c = berlin
        var d1 = StatsDay(date: c.startOfDay(for: date("2026-10-21T10:00:00Z")), words: 30_000, recordingSeconds: 3_600)
        d1.wordsByLanguage = ["de": 29_000, "en": 1_000, "fr": 3]
        d1.apps = ["com.apple.Notes": 20_000, "com.apple.Terminal": 10_000, "com.example.undone": 0]
        var d2 = StatsDay(date: c.startOfDay(for: date("2026-10-27T10:00:00Z")), words: 0, recordingSeconds: 0)
        d2.wordsByLanguage = [:]
        s.save([d1, d2], to: "stats.json")
        s.save([GlossaryEntry(term: "TikTok"), GlossaryEntry(term: "SwiftUI")], to: "glossary.json")
        s.save(Replacements.defaults + [Replacement(spoken: "brb", output: "be right back")], to: ReplacementStore.file)
        s.save([AppProfile(bundleID: "com.example.prompt", appName: "Prompt", mode: .prompt, autoEnter: true)],
               to: "appProfiles.json")
        if history {
            var items: [HistoryItem] = []
            for i in 0..<60 {
                items.append(HistoryItem(date: date("2026-10-22T10:00:00Z").addingTimeInterval(Double(i)), text: "Satz \(i)", rawText: "",
                                         appBundleID: nil, appName: nil, language: .de, modelID: "m"))
            }
            items.append(HistoryItem(date: date("2026-10-23T00:30:00Z"), text: "Spät mit vypo", rawText: "", appBundleID: nil,
                                     appName: nil, language: .de, modelID: "m", undone: true))
            s.save(items, to: "history.json")
        }
    }

    func testFillFromAnExistingInstallation() throws {
        let (s, defaults) = scratch()
        existing(s)
        defaults.set(true, forKey: DefaultsKey.symbolsAreReplacements)
        let app = AppState(prefs: Preferences(defaults: defaults), store: s, calendar: berlin)
        let a = app.achievements
        let reached = Dictionary(uniqueKeysWithValues: a.all.filter { !$0.isLocked }.map { ($0.id, $0.level) })
        XCTAssertEqual(reached, [.firstWords: 1, .wordKeeper: 1, .swapArtist: 1, .rightTool: 1, .secondThoughts: 1,
                                 .polyglot: 1, .tales: 1, .timeBack: 2, .bookshelf: 1, .nightOwl: 1, .chatterbox: 1,
                                 .sayMyName: 1, .wellTravelled: 1])
        XCTAssertEqual(a.state.dictations, 61, "Tales starts with the history's entries")
        XCTAssertEqual(a.state.languages, ["de", "en"], "French had only 3 words")
        XCTAssertEqual(a.state.apps, ["com.apple.Notes", "com.apple.Terminal", "com.example.undone"])
        XCTAssertEqual(a.state.days, ["2026-10-21", "2026-10-22", "2026-10-23"], "a day with 0 words isn't a day")
        XCTAssertEqual(a.readyCount, reached.count, "everything from the fill is ready")
        XCTAssertEqual(a.stampedCount, 0)
        XCTAssertEqual(a.hiddenCuriousLeft, 2)   // Early Bird, Three Tongues
        let file = try String(contentsOf: s.url(AchievementStore.file), encoding: .utf8)
        XCTAssertFalse(file.contains("Satz"), "no history text")
        XCTAssertFalse(file.contains("Spät"))
        // The files read are not changed.
        XCTAssertEqual(s.load([StatsDay].self, from: "stats.json")?.count, 2)
    }

    func testFillWithoutHistory() {
        let (s, defaults) = scratch()
        existing(s, history: false)
        defaults.set(true, forKey: DefaultsKey.symbolsAreReplacements)
        let a = AppState(prefs: Preferences(defaults: defaults), store: s, calendar: berlin).achievements
        XCTAssertEqual(a.state.dictations, 1, "words but no history: at least one dictation")
        XCTAssertEqual(a.status(.firstWords).level, 1)
        XCTAssertEqual(a.status(.tales).level, 0)
        XCTAssertEqual(a.status(.nightOwl).level, 0)
        XCTAssertEqual(a.status(.secondThoughts).level, 0)
        XCTAssertEqual(a.state.days, ["2026-10-21"])
    }

    func testWhatTheFilesTell() {
        // `AppProfileStore` has removed vypo's own former profiles by then: one that is left, the user re-added.
        let profiles = [AppProfileStore.formerDefaults[0]]
        XCTAssertTrue(AchievementSeed.fromFiles(glossaryCount: 0, replacements: [], layout: .legacy, profiles: profiles)
            .flags.contains(.promptOrWritingApp))
        let standard = [AppProfile(bundleID: "com.example.x", appName: "X", mode: .standard)]
        XCTAssertFalse(AchievementSeed.fromFiles(glossaryCount: 0, replacements: [], layout: .legacy, profiles: standard)
            .flags.contains(.promptOrWritingApp))
        XCTAssertTrue(AchievementSeed.fromFiles(glossaryCount: 0, replacements: [Replacement(spoken: "Punkt", output: ".")],
                                                layout: .spokenCharacters, profiles: []).flags.contains(.ownReplacement),
                      "a new installation has no default replacements: every entry is the user's")
        XCTAssertFalse(AchievementSeed.fromFiles(glossaryCount: 0, replacements: Replacements.defaults, layout: .legacy, profiles: [])
            .flags.contains(.ownReplacement), "the defaults are no own entries")
    }

    func testABrokenFileIsKeptAndFilledAgain() throws {
        let (s, _) = scratch()
        try FileManager.default.createDirectory(at: s.directory, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: s.url(AchievementStore.file))
        var seed = AchievementState()
        seed.dictations = 12
        let a = AchievementStore(store: s, calendar: berlin, collecting: true) { seed }
        XCTAssertEqual(a.status(.tales).level, 1)
        XCTAssertTrue(a.status(.tales).isReady, "filled again: ready, nothing stamped")
        let files = try FileManager.default.contentsOfDirectory(atPath: s.directory.path)
        let kept = files.filter { $0.hasPrefix("achievements-unreadable-") }
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(try String(contentsOf: s.url(kept[0]), encoding: .utf8), "{ not json", "the broken file is kept")
        XCTAssertNotNil(s.load(AchievementState.self, from: AchievementStore.file))
    }

    func testMissingFieldsTakeTheirDefaults() throws {
        let (s, _) = scratch()
        try FileManager.default.createDirectory(at: s.directory, withIntermediateDirectories: true)
        try Data(#"{"seeded": true, "levels": {"tales": 2, "someday": 1}, "stamps": {"tales": ["2026-10-30"]}, "flags": ["undo", "unknown"]}"#.utf8)
            .write(to: s.url(AchievementStore.file))
        let a = AchievementStore(store: s, calendar: berlin, collecting: true) { XCTFail("no fill"); return AchievementState() }
        XCTAssertEqual(a.status(.tales).level, 2, "a level stays even without its data")
        XCTAssertEqual(a.status(.tales).stampedLevel, 1)
        XCTAssertTrue(a.status(.tales).isReady)
        XCTAssertEqual(a.state.flags, [.undo])
        XCTAssertEqual(a.state.version, 1)
        XCTAssertEqual(a.state.dictations, 0)
    }

    func testTheFileFormat() throws {
        var s = AchievementState()
        s.seeded = true
        s.dictations = 3
        s.days = ["2026-10-30", "2026-10-29"]
        s.languages = ["en", "de"]
        s.flags = [.undo, .handsFree]
        s.levels = [.firstWords: 1]
        s.stamps = [.firstWords: ["2026-10-30"]]
        s.today = AchievementState.Today(day: "2026-10-30", dictations: 2, languages: ["de"])
        let data = try Store.encoder.encode(s)
        XCTAssertEqual(try Store.decoder.decode(AchievementState.self, from: data), s)
        XCTAssertEqual(try Store.encoder.encode(try Store.decoder.decode(AchievementState.self, from: data)), data, "stable")
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains(#""days" : [\#n    "2026-10-29",\#n    "2026-10-30""#), text)
        XCTAssertTrue(text.contains(#""flags" : [\#n    "handsFree",\#n    "undo""#), text)
    }

    func testCountsForTheCard() {
        var s = AchievementState()
        s.dictations = 10
        s.flags = [.nightOwl]
        let (a, _) = store(s)
        XCTAssertEqual(a.readyCount, 3)   // firstWords, tales, nightOwl
        XCTAssertEqual(a.hiddenCuriousLeft, 5)
        XCTAssertFalse(a.status(.nightOwl).isHidden)
        XCTAssertTrue(a.status(.earlyBird).isHidden)
        XCTAssertFalse(a.status(.bookworm).isHidden, "only curious ones hide")
        a.stamp(.nightOwl)
        XCTAssertEqual(a.stampedCount, 1)
        XCTAssertEqual(a.readyCount, 2)
        XCTAssertEqual(a.status(.tales).next, 100)
    }

    func testNothingWhileNotCollectingAtFirstLaunch() {
        let (a, s) = store(collecting: false)
        XCTAssertFalse(a.state.seeded)
        a.dictated(facts("2026-11-02T10:00:00Z"), savedMinutes: 0, words: 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: s.url(AchievementStore.file).path))
    }
}

private extension DictationFacts {
    func withOffset(_ seconds: Int) -> DictationFacts {
        var f = self
        f.date = f.date.addingTimeInterval(Double(seconds))
        return f
    }
}
