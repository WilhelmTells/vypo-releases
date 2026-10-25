import XCTest
@testable import vypo

@MainActor
final class LevelTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func app(collectStats: Bool = true) -> AppState {
        let prefs = Preferences(defaults: UserDefaults(suiteName: "vypo.level.\(UUID().uuidString)")!)
        prefs.collectStats = collectStats
        return AppState(prefs: prefs, store: Store(directory: dir))
    }

    private func insertion(_ words: Int) -> LastInsertion {
        LastInsertion(text: "", pid: nil, date: Date(), language: .en, words: words, recordingSeconds: 2)
    }

    func testCountsUpAndUndoLeavesIt() {
        let app = app()
        app.count(insertion(30))
        app.count(insertion(12))
        XCTAssertEqual(app.level.xpWords, 42)
        app.uncount(insertion(12))
        XCTAssertEqual(app.stats.allTime, 30)
        XCTAssertEqual(app.level.xpWords, 42)
        // Kept across launches.
        XCTAssertEqual(LevelStore(store: Store(directory: dir), seedWords: 0).xpWords, 42)
    }

    func testNothingCountedWithStatsOff() {
        let app = app(collectStats: false)
        app.count(insertion(30))
        XCTAssertEqual(app.level.xpWords, 0)
    }

    func testStartsFromAllWordsSoFarWithoutALevelUp() {
        let store = Store(directory: dir)
        let stats = StatsStore(store: store)
        stats.record(words: 26_000, seconds: 600, language: .de)
        let level = LevelStore(store: store, seedWords: stats.allTime)
        XCTAssertEqual(level.xpWords, 26_000)
        XCTAssertEqual(level.rank, .scribe)
        XCTAssertEqual(level.lastSeenLevel, 4)
        XCTAssertEqual(level.lastSeenWords, 26_000)
        // Only the first time: an existing level.json wins over the stats.
        stats.record(words: 1_000, seconds: 20, language: .de)
        XCTAssertEqual(LevelStore(store: store, seedWords: stats.allTime).xpWords, 26_000)
    }

    func testResetStatsResetsTheLevel() {
        let app = app()
        app.count(insertion(6_000))
        app.level.markSeen()
        XCTAssertEqual(app.level.lastSeenLevel, 2)
        app.resetStats()
        XCTAssertEqual(app.level.xpWords, 0)
        XCTAssertEqual(app.level.lastSeenLevel, 1)
        XCTAssertEqual(app.level.lastSeenWords, 0)
        XCTAssertEqual(app.level.rank.level, app.level.lastSeenLevel, "nothing to celebrate after a reset")
    }

    func testMarkSeen() {
        let level = LevelStore(store: Store(directory: dir), seedWords: 2_490)
        level.add(words: 20)
        XCTAssertEqual(level.rank, .messenger)
        XCTAssertEqual(level.lastSeenRank, .errandBoy)
        level.markSeen()
        XCTAssertEqual(level.lastSeenRank, .messenger)
        XCTAssertEqual(level.lastSeenWords, 2_510)
    }

    func testThresholdsAndProgressAtTheEdges() {
        XCTAssertEqual(Rank.allCases.count, 10)
        XCTAssertEqual(Rank.thresholds, [0, 2_500, 10_000, 25_000, 50_000, 100_000, 200_000, 400_000, 700_000, 1_000_000])
        XCTAssertEqual(Rank(words: 0), .errandBoy)
        XCTAssertEqual(Rank(words: 2_499), .errandBoy)
        XCTAssertEqual(Rank(words: 2_500), .messenger)
        XCTAssertEqual(Rank(words: 9_999), .messenger)
        XCTAssertEqual(Rank(words: 10_000), .page)
        XCTAssertEqual(Rank(words: 25_000), .scribe)
        XCTAssertEqual(Rank(words: 50_000), .herald)
        XCTAssertEqual(Rank(words: 100_000), .courtCoachman)
        XCTAssertEqual(Rank(words: 199_999), .courtCoachman)
        XCTAssertEqual(Rank(words: 200_000), .chronicler)
        XCTAssertEqual(Rank(words: 400_000), .steward)
        XCTAssertEqual(Rank(words: 700_000), .chancellor)
        XCTAssertEqual(Rank(words: 999_999), .chancellor)
        XCTAssertEqual(Rank(words: 1_000_000), .poetLaureate)
        XCTAssertEqual(Rank.allCases.map(\.threshold), Rank.thresholds)
        XCTAssertEqual(Rank.allCases.map(\.level), Array(1...10))
        XCTAssertEqual(Rank.highest, .poetLaureate)
        XCTAssertEqual(Rank.poetLaureate.previous, .chancellor)
        XCTAssertNil(Rank.errandBoy.previous)

        XCTAssertEqual(Rank.errandBoy.progress(words: 0), 0)
        XCTAssertEqual(Rank.errandBoy.progress(words: 1_250), 0.5)
        XCTAssertEqual(Rank.scribe.progress(words: 25_000), 0)
        // (35,000 − 25,000) ÷ (50,000 − 25,000)
        XCTAssertEqual(Rank.scribe.progress(words: 35_000), 0.4, accuracy: 0.0001)
        XCTAssertEqual(Rank.scribe.progress(words: 49_999), 1, accuracy: 0.001)
        XCTAssertEqual(Rank.scribe.next, .herald)
    }

    func testHighestRankIsFullAndKeepsCounting() {
        let level = LevelStore(store: Store(directory: dir), seedWords: 999_990)
        level.add(words: 1_000_000)
        XCTAssertEqual(level.rank, .poetLaureate)
        XCTAssertNil(level.rank.next)
        XCTAssertEqual(level.rank.progress(words: level.xpWords), 1)
        XCTAssertEqual(level.xpWords, 1_999_990)
    }

    // MARK: Six ranks became ten

    private func writeOldFile(words: Int, lastSeenLevel: Int, lastSeenWords: Int) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let json = #"{"xpWords":\#(words),"lastSeenLevel":\#(lastSeenLevel),"lastSeenWords":\#(lastSeenWords)}"#
        try Data(json.utf8).write(to: dir.appendingPathComponent("level.json"))
    }

    /// The owner on 2026-10-25: 36,322 words, old level 3 (Page). The new list makes that Scribe, level 4: one
    /// fanfare, for the current level.
    func testTheOwnersLevelMovesWithOneFanfare() throws {
        try writeOldFile(words: 36_322, lastSeenLevel: 3, lastSeenWords: 36_247)
        let level = LevelStore(store: Store(directory: dir), seedWords: 0)
        XCTAssertEqual(level.xpWords, 36_322, "the words never change")
        XCTAssertEqual(level.rank, .scribe)
        XCTAssertEqual(level.lastSeenLevel, 3, "Page stays Page: one level below the current one")
        XCTAssertGreaterThan(level.rank.level, level.lastSeenLevel)
        XCTAssertEqual(level.rank.level - level.lastSeenLevel, 1, "at most one fanfare")
        // Done once: after the card was seen, a new start changes nothing.
        level.markSeen()
        XCTAssertEqual(LevelStore(store: Store(directory: dir), seedWords: 0).lastSeenLevel, 4)
        XCTAssertEqual(LevelStore(store: Store(directory: dir), seedWords: 0).lastSeenLevel, 4)
    }

    func testNoChainOfFanfares() {
        // Old Messenger (2) with 120,000 words is level 6 now: the old level maps to 2, but only the last step plays.
        XCTAssertEqual(LevelStore.movedLastSeenLevel(old: 2, words: 120_000), 5)
        // Old Chancellor (6) maps to 9, but 360,000 words are level 7 now: never above the current level.
        XCTAssertEqual(LevelStore.movedLastSeenLevel(old: 6, words: 360_000), 7)
        // Old Herald (4) is level 5 now, which 80,000 words are too: nothing to celebrate.
        XCTAssertEqual(LevelStore.movedLastSeenLevel(old: 4, words: 80_000), 5)
        // Unknown numbers count as the first rank.
        XCTAssertEqual(LevelStore.movedLastSeenLevel(old: 0, words: 100), 1)
        XCTAssertEqual(LevelStore.movedLastSeenLevel(old: 9, words: 100), 1)
    }

    func testTheMoveIsSavedAndNotRepeated() throws {
        try writeOldFile(words: 12_000, lastSeenLevel: 2, lastSeenWords: 12_000)
        _ = LevelStore(store: Store(directory: dir), seedWords: 0)
        let saved = try String(contentsOf: dir.appendingPathComponent("level.json"), encoding: .utf8)
        XCTAssertTrue(saved.contains("\"ranks\" : 2"), saved)
        // A level the new file holds is taken as it is, not moved again.
        let again = LevelStore(store: Store(directory: dir), seedWords: 0)
        XCTAssertEqual(again.lastSeenLevel, 2, "Messenger stays; Page (3) is one fanfare")
        again.markSeen()
        XCTAssertEqual(LevelStore(store: Store(directory: dir), seedWords: 0).lastSeenLevel, 3)
    }

    func testAccessibilityNamesNoNextRank() {
        let text = LevelCard.accessibilityText(rank: .page, words: 13_200)
        XCTAssertTrue(text.contains("Level 3 of 10"), text)
        XCTAssertTrue(text.contains("Page"), text)
        XCTAssertFalse(text.contains("Scribe"), text)
        XCTAssertTrue(text.contains("11,800") || text.contains("11.800"), text)
    }
}

final class MascotMotionTests: XCTestCase {
    func testLegsSwingOnASineAgainstEachOther() {
        let legs = stride(from: 0.0, to: 1.6, by: 1 / MascotMotion.fps).map { MascotMotion.idle(at: $0 + 0.001) }
        XCTAssertEqual(legs.map(\.legL).max()!, 12, accuracy: 0.5)
        XCTAssertEqual(legs.map(\.legL).min()!, -12, accuracy: 0.5)
        XCTAssertTrue(legs.allSatisfy { $0.legR == -$0.legL })
        // Stepped at 12 fps: within one frame nothing moves.
        XCTAssertEqual(MascotMotion.idle(at: 0.1).legL, MascotMotion.idle(at: 0.16).legL)
    }

    func testTheMotionTestsLoop() {
        let frames = stride(from: 0.0, to: 9, by: 1 / MascotMotion.fps).map { MascotMotion.idle(at: $0 + 0.001) }
        XCTAssertEqual(frames.filter(\.eyesClosed).count, 6, "three blinks of two frames")
        XCTAssertTrue(MascotMotion.idle(at: 1.26).eyesClosed)
        XCTAssertTrue(MascotMotion.idle(at: 2.5).mouthOpen)
        XCTAssertFalse(MascotMotion.idle(at: 2.95).mouthOpen)
        XCTAssertEqual(frames.map(\.cap).max()!, 5, accuracy: 0.5)
        XCTAssertEqual(frames.map(\.cap).min()!, -5, accuracy: 0.5)
        XCTAssertEqual(MascotMotion.idle(at: 3.5).ravenHead, -16)
        XCTAssertEqual(MascotMotion.idle(at: 3.95).ravenHead, 0)
        for t in [1.26, 2.5, 3.5] {
            let first = MascotMotion.idle(at: t), next = MascotMotion.idle(at: 9 + t)
            XCTAssertEqual([first.eyesClosed, first.mouthOpen], [next.eyesClosed, next.mouthOpen])
            XCTAssertEqual(first.ravenHead, next.ravenHead)
        }
        XCTAssertFalse(frames.contains { $0.blowing || $0.wingUp || $0.ruffled || $0.ravenPuffed })
    }

    func testWalkTakesEightSteps() {
        let steps = stride(from: 0.0, to: 1.2, by: 0.15).map { MascotMotion.walk(from: 0.2, to: 0.6, after: $0 + 0.01) }
        XCTAssertEqual(steps.count, 8)
        XCTAssertEqual(Set(steps).count, 8)
        XCTAssertEqual(steps.first!, 0.25, accuracy: 0.0001)
        XCTAssertEqual(steps.last!, 0.6, accuracy: 0.0001)
    }
}

final class LevelUpMotionTests: XCTestCase {
    private func at(_ f: Double) -> LevelUpFrame { LevelUpMotion.frame(at: LevelUpMotion.slide + f, from: 0) }

    func testSlidesToTheEndThenBlows() {
        let start = LevelUpMotion.frame(at: 0.01, from: 0.4)
        XCTAssertEqual(start.progress, 0.4 + 0.6 / 8, accuracy: 0.0001)
        XCTAssertFalse(start.pose.blowing)
        XCTAssertEqual(LevelUpMotion.frame(at: 1.19, from: 0.4).progress, 1, accuracy: 0.0001)
        XCTAssertTrue(at(0.01).pose.blowing)
        XCTAssertFalse(at(0.01).pose.mouthOpen)
        XCTAssertFalse(at(2.45).pose.blowing, "blows until 2.4 s")
        XCTAssertEqual(LevelUpMotion.duration, 1.2 + 2.9, accuracy: 0.0001)
    }

    func testOneHop() {
        XCTAssertEqual(at(0.01).pose.hop, 0)
        XCTAssertEqual(at(0.26).pose.hop, LevelUpMotion.hop.height, accuracy: 0.3)
        XCTAssertEqual(at(0.5).pose.hop, 0)
    }

    func testThreeStarsOneAfterAnother() {
        XCTAssertTrue(at(0.25).stars.isEmpty)
        XCTAssertEqual(at(0.34).stars.count, 1)
        XCTAssertEqual(at(0.52).stars.count, 2)
        XCTAssertEqual(at(0.6).stars.count, 3)
        // Each flies 0.9 s: the last is gone by 0.3 + 0.24 + 0.9.
        XCTAssertTrue(at(1.5).stars.isEmpty)
        let star = at(0.8).stars[0]
        XCTAssertGreaterThan(star.offset.width, 0)
        XCTAssertLessThan(star.offset.height, 0)
        // Grows from 0.35 to a visible star of about 15 pt (37 of 65 px).
        XCTAssertLessThan(at(0.34).stars[0].size, at(0.8).stars[0].size)
        XCTAssertEqual(at(1.15).stars[0].size * 37 / 65, 15, accuracy: 1.5)
    }

    func testTheRavenFluttersUpAndLandsRuffled() {
        XCTAssertEqual(at(0.1).pose.ravenLift, .zero)
        let up = at(0.62).pose
        XCTAssertEqual(up.ravenLift.height, -LevelUpMotion.raven.lift, accuracy: 1)
        XCTAssertTrue(up.wingUp)
        XCTAssertEqual(Set([0.5, 0.59].map { at($0).pose.wingAngle }), [-28, 12])
        XCTAssertEqual(at(1.0).feathers.count, 1)
        let landed = at(1.05).pose
        XCTAssertEqual(landed.ravenLift, .zero)
        XCTAssertTrue(landed.ruffled && landed.ravenPuffed)
        XCTAssertFalse(landed.wingUp)
        XCTAssertFalse(at(1.6).pose.ravenPuffed)
        XCTAssertTrue(at(2.8).pose.ruffled)
    }

    func testReducedMotionStarsStandStillAndFade() {
        let first = LevelUpMotion.reducedStars(at: 0.1)
        let later = LevelUpMotion.reducedStars(at: 0.9)
        XCTAssertEqual(first.count, 3)
        XCTAssertEqual(first.map(\.offset), later.map(\.offset))
        XCTAssertLessThan(later[0].opacity, first[0].opacity)
        XCTAssertTrue(LevelUpMotion.reducedStars(at: LevelUpMotion.reducedDuration).isEmpty)
    }
}
