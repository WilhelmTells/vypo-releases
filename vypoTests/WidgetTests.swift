import XCTest
@testable import vypo

final class WidgetSnapshotTests: XCTestCase {
    private func sample() -> WidgetSnapshot {
        var s = WidgetSnapshot()
        s.writtenAt = Date(timeIntervalSince1970: 1_800_000_000)
        s.level = 4
        s.rankName = "Scribe"
        s.nextRankName = "Herald"
        s.words = 40_000
        s.rankStart = 25_000
        s.nextStart = 50_000
        s.progress = 0.6
        s.today = Date(timeIntervalSince1970: 1_799_971_200)
        s.wordsToday = 1_240
        s.minutesSaved = 200
        s.savedText = "3 h 20 min"
        s.activity = [[1, 2, 3, 4, 5, nil, nil]]
        s.latest = .init(id: "wordKeeper", name: "Word Keeper", day: "2026-11-01")
        s.ready = .init(id: "bookworm", name: "Bookworm")
        s.suggestion = .init(id: "Kubernetes", term: "Kubernetes")
        s.uiLanguage = "de"
        s.numberLocale = "de_DE"
        return s
    }

    func testRoundTrip() throws {
        let s = sample()
        let decoded = try WidgetStore.decoder.decode(WidgetSnapshot.self, from: WidgetStore.encoder.encode(s))
        XCTAssertEqual(decoded, s)
    }

    func testFileIsReplacedWhole() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("widget-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try WidgetStore.write(sample(), to: url)
        var next = sample()
        next.words = 41_000
        try WidgetStore.write(next, to: url)
        XCTAssertEqual(WidgetStore.read(from: url), next)
        XCTAssertNil(WidgetStore.read(from: url.appendingPathExtension("missing")))
    }

    /// A file from an older app: fields added since then take their defaults, nothing fails.
    func testOlderSnapshotWithoutNewFieldsDecodes() throws {
        let old = #"{"level": 3, "rankName": "Page", "words": 12000}"#
        let s = try WidgetStore.decoder.decode(WidgetSnapshot.self, from: Data(old.utf8))
        XCTAssertEqual(s.level, 3)
        XCTAssertEqual(s.rankName, "Page")
        XCTAssertTrue(s.collecting)
        XCTAssertNil(s.suggestion)
        XCTAssertEqual(s.activity, [])
    }

    func testNewerSnapshotWithUnknownFieldDecodes() throws {
        let s = try WidgetStore.decoder.decode(WidgetSnapshot.self, from: Data(#"{"level": 3, "fromTheFuture": true}"#.utf8))
        XCTAssertEqual(s.level, 3)
    }

    func testSameContentIgnoresTheTimeOfWriting() {
        var other = sample()
        other.writtenAt = Date()
        XCTAssertTrue(sample().sameContent(as: other))
        other.words += 1
        XCTAssertFalse(sample().sameContent(as: other))
    }

    func testWordsTodayEndWithTheDay() {
        let s = sample()
        XCTAssertEqual(s.wordsToday(on: s.today.addingTimeInterval(3_600)), 1_240)
        XCTAssertEqual(s.wordsToday(on: s.today.addingTimeInterval(2 * 86_400)), 0)
    }

    func testActivityLevels() {
        XCTAssertEqual(WidgetSnapshot.activityLevel(0, peak: 100), 0)
        XCTAssertEqual(WidgetSnapshot.activityLevel(1, peak: 100), 1)
        XCTAssertEqual(WidgetSnapshot.activityLevel(100, peak: 100), 4)
    }
}

@MainActor
final class WidgetCurrentSnapshotTests: XCTestCase {
    private func makeApp() -> AppState {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("widget-\(UUID().uuidString)")
        let suite = "vypo.widget.\(UUID().uuidString)"
        return AppState(prefs: Preferences(defaults: UserDefaults(suiteName: suite)!), store: Store(directory: dir))
    }

    func testUsesTheStatsNumbers() {
        let app = makeApp()
        app.level.add(words: 40_000)
        app.stats.record(words: 400, seconds: 60, language: .en)
        let s = WidgetSnapshot.current(app: app)
        XCTAssertEqual(s.level, Rank.scribe.level)
        XCTAssertEqual(s.rankName, Rank.scribe.name)
        XCTAssertEqual(s.nextRankName, Rank.herald.name)
        XCTAssertEqual(s.nextStart, 50_000)
        XCTAssertEqual(s.progress, Rank.scribe.progress(words: 40_000))
        XCTAssertEqual(s.wordsToday, 400)
        XCTAssertEqual(s.minutesSaved, StatsMath.minutesSaved(words: 400, seconds: 60))
        XCTAssertEqual(s.activity.count, 27)
        XCTAssertEqual(s.activity.joined().compactMap { $0 }.reduce(0, +), 400)
    }

    func testStatsOffCarriesNoNumbersAndNoTerm() {
        let app = makeApp()
        app.level.add(words: 40_000)
        _ = app.glossary.suggest(heard: "cuber", term: "Kubernetes", scope: .all)
        app.prefs.collectStats = false
        let s = WidgetSnapshot.current(app: app)
        XCTAssertFalse(s.collecting)
        XCTAssertEqual(s.words, 0)
        XCTAssertEqual(s.rankName, "")
        XCTAssertNil(s.suggestion)
    }

    func testNewestVisibleSuggestion() {
        let app = makeApp()
        _ = app.glossary.suggest(heard: "cuber", term: "Kubernetes", scope: .all)
        _ = app.glossary.suggest(heard: "hello", term: "Halo", scope: .all, source: .app)
        // The second is one correction in an app: not visible yet.
        XCTAssertEqual(WidgetSnapshot.current(app: app).suggestion?.term, "Kubernetes")
    }

    func testSyncWritesOnlyWhenTheContentChanged() {
        let app = makeApp()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("widget-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var reloads = 0
        let sync = WidgetSync(app: app, url: url) { reloads += 1 }
        sync.flush()
        sync.flush()
        XCTAssertEqual(reloads, 1)
        app.level.add(words: 3_000)
        sync.flush()
        XCTAssertEqual(reloads, 2)
        XCTAssertEqual(WidgetStore.read(from: url)?.words, 3_000)
    }

    func testSyncWithoutGroupDoesNothing() {
        var reloads = 0
        let sync = WidgetSync(app: makeApp(), url: nil) { reloads += 1 }
        sync.start()
        sync.flush()
        XCTAssertEqual(reloads, 0)
    }
}

@MainActor
final class DebouncerTests: XCTestCase {
    func testBurstRunsOnce() async throws {
        var runs = 0
        let d = Debouncer(delay: .milliseconds(30)) { runs += 1 }
        for _ in 0..<5 { d.call() }
        XCTAssertEqual(runs, 0)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(runs, 1)
    }

    func testLaterCallRunsAgain() async throws {
        var runs = 0
        let d = Debouncer(delay: .milliseconds(10)) { runs += 1 }
        d.call()
        try await Task.sleep(for: .milliseconds(80))
        d.call()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(runs, 2)
    }
}

final class WidgetLinkTests: XCTestCase {
    private func link(_ s: String) -> WidgetLink? { WidgetLink(url: URL(string: s)!, scheme: "vypo") }

    func testKnownLinks() {
        XCTAssertEqual(link("vypo://stats"), .stats)
        XCTAssertEqual(link("vypo://stats?stamp=bookworm"), .stamp("bookworm"))
        XCTAssertEqual(link("vypo://words?suggestion=Kubernetes"), .suggestion("Kubernetes"))
    }

    func testUnknownLinksDoNothing() {
        for s in ["vypo://", "vypo://words", "vypo://about", "vypo://stats/more", "vypo://stats?stamp=", "vypo://stats?other=1",
                  "vypo://words?suggestion=", "vypo://words?stamp=x", "vypo://stats?stamp=a&stamp=b", "https://stats", "vypo-test://stats"] {
            XCTAssertNil(link(s), s)
        }
    }

    func testTheTestAppsSchemeIsItsOwn() {
        XCTAssertEqual(WidgetLink(url: URL(string: "vypo-test://stats")!, scheme: "vypo-test"), .stats)
        XCTAssertEqual(WidgetLink.stats.url(scheme: "vypo-test").absoluteString, "vypo-test://stats")
    }

    func testTermsSurviveTheRoundTrip() {
        for term in ["C++ & Co", "Größe", "a=b?c", "two words", "#1"] {
            let url = WidgetLink.suggestion(term).url(scheme: "vypo")
            XCTAssertEqual(WidgetLink(url: url, scheme: "vypo"), .suggestion(term))
        }
    }
}

@MainActor
final class WidgetLinkOpeningTests: XCTestCase {
    private func makeApp() -> (AppState, () -> [SettingsPane?]) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("widget-\(UUID().uuidString)")
        let app = AppState(prefs: Preferences(defaults: UserDefaults(suiteName: "vypo.widget.\(UUID().uuidString)")!), store: Store(directory: dir))
        var opened: [SettingsPane?] = []
        app.onOpenSettings = { opened.append($0) }
        return (app, { opened })
    }

    func testPanes() {
        let (app, opened) = makeApp()
        app.open(.stats)
        app.open(.suggestion("x"))
        XCTAssertEqual(opened(), [.stats, .words])
        XCTAssertEqual(app.scrollTarget, .suggestions)
    }

    func testStampUnfoldsTheCard() {
        let (app, opened) = makeApp()
        app.prefs.achievementsExpanded = false
        app.open(.stamp("bookworm"))
        XCTAssertEqual(opened(), [.stats])
        XCTAssertTrue(app.prefs.achievementsExpanded)
        XCTAssertEqual(app.scrollTarget, .achievements(.bookworm))
    }

    func testUnknownStampDoesNothing() {
        let (app, opened) = makeApp()
        app.open(.stamp("nope"))
        XCTAssertEqual(opened(), [])
        XCTAssertNil(app.scrollTarget)
    }
}
