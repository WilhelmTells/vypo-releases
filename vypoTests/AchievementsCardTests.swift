import AppKit
import XCTest
@testable import vypo

/// 0.4.0: the achievements card, what each place shows (CARD.md, MOTION.md).
@MainActor
final class AchievementsCardTests: XCTestCase {
    private let en = Locale(identifier: "en_US")

    /// A status as the store would give it.
    static func status(_ id: AchievementID, level: Int = 0, stamped: Int = 0, on day: String? = nil, value: Double? = nil) -> AchievementStatus {
        let d = Achievements.definition(id)
        return AchievementStatus(id: id, kind: d.kind, tiers: d.tiers, level: level, stampedLevel: stamped,
                                 stampedOn: stamped > 0 ? day ?? "2026-10-14" : nil,
                                 value: value ?? (level > 0 ? d.thresholds[level - 1] : 0),
                                 next: level < d.tiers ? d.thresholds[level] : nil)
    }

    private func all(_ some: [AchievementStatus]) -> [AchievementStatus] {
        AchievementID.allCases.map { id in some.first { $0.id == id } ?? Self.status(id) }
    }

    // MARK: Order, counter, secrets

    func testOrderHidesCuriousUntilFound() {
        let content = AchievementCardContent(all([Self.status(.wellTravelled, level: 1), Self.status(.nightOwl, level: 1, stamped: 1)]))
        XCTAssertEqual(content.slots.map(\.id), [.firstWords, .wordKeeper, .bookworm, .swapArtist, .rightTool, .handsFree, .secondThoughts,
                                                 .polyglot, .tales, .timeBack, .longBreath, .wordCollector, .bookshelf, .regular,
                                                 .nightOwl, .wellTravelled])
        XCTAssertEqual(content.secretsLeft, 4)
        XCTAssertEqual(content.secrets, "4 secrets left")
    }

    func testCuriousFollowTheirOwnOrderNotTheOrderFound() {
        let shuffled = all([Self.status(.wellTravelled, level: 1), Self.status(.earlyBird, level: 1)]).reversed()
        let content = AchievementCardContent(Array(shuffled))
        XCTAssertEqual(content.slots.suffix(2).map(\.id), [.earlyBird, .wellTravelled])
        XCTAssertEqual(content.slots.first?.id, .firstWords)
    }

    func testCounterCountsReachedAndReady() {
        let content = AchievementCardContent(all([
            Self.status(.firstWords, level: 1, stamped: 1), Self.status(.tales, level: 3, stamped: 1),
            Self.status(.regular, level: 1), Self.status(.nightOwl, level: 1, stamped: 1),
        ]))
        XCTAssertEqual(content.reached, 4)
        XCTAssertEqual(content.total, 20)
        XCTAssertEqual(content.ready, 2)
        XCTAssertEqual(content.counter, "4 of 20, 2 ready to stamp")
    }

    func testNothingReadyDropsTheSecondPart() {
        let content = AchievementCardContent(all([Self.status(.firstWords, level: 1, stamped: 1)]))
        XCTAssertEqual(content.counter, "1 of 20")
    }

    func testSecretsLineGoesWhenAllAreFound() {
        let curious: [AchievementID] = [.nightOwl, .earlyBird, .threeTongues, .chatterbox, .sayMyName, .wellTravelled]
        let content = AchievementCardContent(all(curious.map { Self.status($0, level: 1, stamped: 1) }))
        XCTAssertEqual(content.secretsLeft, 0)
        XCTAssertNil(content.secrets)
        XCTAssertEqual(content.slots.count, 20)
        let one = AchievementCardContent(all(curious.dropLast().map { Self.status($0, level: 1, stamped: 1) }))
        XCTAssertEqual(one.secrets, "1 secret left")
    }

    func testFreshInstallShowsOnlyPrePrints() {
        let content = AchievementCardContent(all([]))
        XCTAssertEqual(content.slots.count, 14)
        XCTAssertTrue(content.slots.allSatisfy { $0.art.state == "locked" && $0.face == nil })
        XCTAssertEqual(content.counter, "0 of 20")
        XCTAssertEqual(content.secrets, "6 secrets left")
    }

    // MARK: What a place shows

    func testLockedShowsThePrePrint() {
        let slot = AchievementSlot(status: Self.status(.timeBack))
        XCTAssertEqual(slot.art.state, "locked")
        XCTAssertNil(slot.face)
        XCTAssertFalse(slot.isReady)
    }

    func testFirstReadyWaitsOverThePrePrintWithTheVermilionTool() {
        let slot = AchievementSlot(status: Self.status(.polyglot, level: 1))
        XCTAssertEqual(slot.art.state, "locked")
        XCTAssertEqual(slot.stampedArt.state, "unlocked")
        XCTAssertEqual(slot.face, .vermilion)
    }

    func testTierUpWaitsOverTheOldPrintWithTheBronzeTool() {
        let slot = AchievementSlot(status: Self.status(.timeBack, level: 4, stamped: 1))
        XCTAssertEqual(slot.art.state, "tier1")
        XCTAssertEqual(slot.stampedArt.state, "tier4", "one click stamps every ready tier; the highest is printed")
        XCTAssertEqual(slot.face, .bronze)
    }

    func testSeveralFirstTiersReadyPrintTheHighest() {
        let slot = AchievementSlot(status: Self.status(.tales, level: 3))
        XCTAssertEqual(slot.art.state, "locked")
        XCTAssertEqual(slot.stampedArt.state, "tier3")
        XCTAssertEqual(slot.face, .vermilion)
    }

    func testStampedShowsItsKindOfPrint() {
        XCTAssertEqual(AchievementSlot(status: Self.status(.firstWords, level: 1, stamped: 1)).art.state, "unlocked")
        XCTAssertEqual(AchievementSlot(status: Self.status(.regular, level: 2, stamped: 2)).art.state, "tier2")
        XCTAssertEqual(AchievementSlot(status: Self.status(.sayMyName, level: 1, stamped: 1)).art.state, "found")
        // Chatterbox has tiers but one seal: a tier-up presses the bronze tool on the same seal.
        let chatter = AchievementSlot(status: Self.status(.chatterbox, level: 2, stamped: 1))
        XCTAssertEqual(chatter.art.state, "found")
        XCTAssertEqual(chatter.stampedArt.state, "found")
        XCTAssertEqual(chatter.face, .bronze)
    }

    /// The package has no pre-print for Curious: a found one waits over the dashed circle of the secrets line.
    func testFoundCuriousWaitsOverADashedCircle() {
        let slot = AchievementSlot(status: Self.status(.threeTongues, level: 1))
        XCTAssertTrue(slot.art.isSecret)
        XCTAssertEqual(slot.art.layers, [])
        XCTAssertEqual(slot.face, .vermilion)
        XCTAssertFalse(slot.stampedArt.isSecret)
        XCTAssertFalse(AchievementArt(id: .tales, stamped: 0).isSecret)
    }

    func testLayersStackInThePackagesOrder() {
        XCTAssertEqual(AchievementArt(id: .firstWords, stamped: 0).layers, ["shadow", "shape", "motif"])
        XCTAssertEqual(AchievementArt(id: .firstWords, stamped: 1).layers, ["shape", "motif"])
        XCTAssertEqual(AchievementArt(id: .tales, stamped: 1).layers, ["shape", "ring1", "motif"])
        XCTAssertEqual(AchievementArt(id: .tales, stamped: 3).layers, ["shadow", "shape", "ring1", "ring2", "ring3", "motif"])
        XCTAssertEqual(AchievementArt(id: .timeBack, stamped: 5).layers,
                       ["ground", "shadow", "shape", "ring1", "ring2", "ring3", "ring4", "ring5", "motif"])
        XCTAssertEqual(AchievementArt(id: .nightOwl, stamped: 1).layers, ["shadow", "paperEdge", "shape", "recess", "motif", "outline"])
    }

    /// Every layer the card can draw is in the catalog, and the catalog holds nothing else (no composites, no owl).
    func testEveryLayerIsInTheCatalogAndNothingMore() throws {
        var names = Set<String>()
        for id in AchievementID.allCases {
            let d = Achievements.definition(id)
            let states = (d.kind == .curious ? [] : [0]) + (d.kind == .discover || d.kind == .curious ? [1] : Array(1...d.tiers))
            for stamped in states {
                let art = AchievementArt(id: id, stamped: stamped)
                for layer in art.layers { for dark in [false, true] { names.insert(art.image(layer, dark: dark)) } }
            }
        }
        for face in [StampFace.vermilion, .bronze] {
            for part in StampFace.parts { for dark in [false, true] { names.insert(face.image(part, dark: dark)) } }
        }
        names.insert("Achievements/star")
        for name in names { XCTAssertNotNil(NSImage(named: name), name) }

        let catalog = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Assets.xcassets/Achievements")
        let sets = try FileManager.default.contentsOfDirectory(atPath: catalog.path).filter { $0.hasSuffix(".imageset") }
        XCTAssertEqual(Set(sets.map { "Achievements/" + $0.replacingOccurrences(of: ".imageset", with: "") }), names)
    }

    // MARK: The press

    func testReadyIsStill() {
        let ready = StampMotion.ready
        XCTAssertFalse(ready.stamped)
        XCTAssertEqual(ready.tool, StampMotion.Tool(padBottom: 0.45, width: 0.68))
        XCTAssertEqual(ready.readyStar, StampMotion.Star(center: CGPoint(x: 0.80, y: -0.22), size: 0.18))
        XCTAssertTrue(ready.stars.isEmpty)
        // At S = 60 the tool's canvas starts at (9.6, -26.4), as in MOTION.md (−26.6 there, rounded from the canvas).
        let k = 0.68 * 60 / StampToolView.canvas.width
        XCTAssertEqual(30 - StampToolView.origin.x * k, 9.6, accuracy: 0.01)
        XCTAssertEqual(0.45 * 60 - StampToolView.origin.y * k, -26.4, accuracy: 0.1)
    }

    func testThePressStepByStep() {
        let lift = StampMotion.frame(at: 0)
        XCTAssertEqual(lift.tool?.padBottom, 0.33)
        XCTAssertEqual(lift.tool?.width, 1.23)
        XCTAssertEqual(lift.ground?.radii, CGSize(width: 0.40, height: 0.06))
        XCTAssertTrue(lift.stars.isEmpty)
        XCTAssertNil(lift.readyStar, "the ready star goes with the click")
        XCTAssertEqual(StampMotion.frame(at: 0.08), lift)
        let down = StampMotion.frame(at: 0.17)
        XCTAssertEqual(down.tool?.padBottom, 0.85)
        XCTAssertNil(down.ground)
        for t in [0.25, 0.34, 0.42] {
            let pressed = StampMotion.frame(at: t)
            XCTAssertEqual(pressed.tool?.padBottom, 0.88, "\(t)")
            XCTAssertEqual(pressed.tool?.squashed, true)
            XCTAssertTrue(pressed.pressLines)
            XCTAssertFalse(pressed.stamped, "the old print stays until the lift")
        }
        let up = StampMotion.frame(at: 0.5)
        XCTAssertTrue(up.stamped)
        XCTAssertEqual(up.tool?.padBottom, 0.06)
        XCTAssertEqual(up.tool?.rotation, -4)
        let burst = StampMotion.frame(at: 7 / 12)
        XCTAssertNil(burst.tool)
        XCTAssertEqual(burst.stars.count, 5)
        XCTAssertEqual(burst.stars[0].center.x, 0.5 - 0.58, accuracy: 1e-9)
        XCTAssertEqual(burst.stars[1].size, 0.42, accuracy: 1e-9)
        let late = StampMotion.frame(at: 1.0)
        XCTAssertEqual(late.stars[1].size, 0.42 * 0.5, accuracy: 1e-9)
        XCTAssertEqual(late.stars[1].center.y, 0.5 - 0.83 + 0.2, accuracy: 1e-9)
        let rest = StampMotion.frame(at: 1.09)
        XCTAssertEqual(rest, StampMotion.Frame(stamped: true))
        XCTAssertEqual(StampMotion.duration, 13 / 12, accuracy: 1e-9)
    }

    func testTiltFollowsThePointerInTwoSteps() {
        XCTAssertEqual(HoverTilt.angles(pointer: CGPoint(x: 1, y: 0), phase: 1).y, -10)
        XCTAssertEqual(HoverTilt.angles(pointer: CGPoint(x: 0, y: -1), phase: 1).x, -10)
        XCTAssertEqual(HoverTilt.angles(pointer: CGPoint(x: 3, y: 0), phase: 0.5).y, -5)
        XCTAssertEqual(HoverTilt.angles(pointer: CGPoint(x: 1, y: 1), phase: 1).scale, 1.05, accuracy: 1e-9)
        XCTAssertEqual(HoverTilt.angles(pointer: CGPoint(x: 1, y: 1), phase: 0).scale, 1)
    }

    // MARK: Texts

    func testPopoverOfAStampedTier() {
        let s = Self.status(.timeBack, level: 2, stamped: 2, on: "2026-10-14", value: 1_440 - 12 * 60 - 49)
        let text = AchievementText.popover(s, locale: en)
        XCTAssertEqual(text.name, "Time Back")
        XCTAssertEqual(text.tier, "Tier 2 of 5, bronze")
        XCTAssertEqual(text.condition, "10 hours saved by dictating instead of typing.")
        XCTAssertEqual(text.date, "Stamped Oct 14, 2026")
        XCTAssertEqual(text.next, "Next tier at 24 hours, 12 h 49 min to go.")
    }

    func testPopoverOfALockedOneHasNoDate() {
        let text = AchievementText.popover(Self.status(.bookworm), locale: en)
        XCTAssertEqual(text.name, "Bookworm")
        XCTAssertNil(text.tier)
        XCTAssertEqual(text.condition, "Glossary words taken from a document.")
        XCTAssertNil(text.date)
        XCTAssertNil(text.next)
    }

    func testPopoverOfAReadyOneShowsTheReachedTier() {
        let text = AchievementText.popover(Self.status(.regular, level: 2, stamped: 1, value: 31), locale: en)
        XCTAssertEqual(text.name, "Familiar Voice")
        XCTAssertEqual(text.tier, "Tier 2 of 3, silver")
        XCTAssertEqual(text.condition, "Dictated on 30 different days.")
        XCTAssertEqual(text.date, "Ready to stamp.")
        XCTAssertEqual(text.next, "Next tier at 100 days, 69 days to go.")
    }

    func testNextLines() {
        XCTAssertEqual(AchievementText.next(Self.status(.tales, value: 7), locale: en), "3 dictations to go.")
        XCTAssertEqual(AchievementText.next(Self.status(.tales, level: 2, value: 146), locale: en), "Next tier at 1,000 dictations, 854 dictations to go.")
        XCTAssertEqual(AchievementText.next(Self.status(.longBreath, level: 1, value: 74), locale: en),
                       "Next tier at one dictation over 3 min. Longest so far: 1 min 14 s.")
        XCTAssertNil(AchievementText.next(Self.status(.longBreath), locale: en), "nothing recorded yet")
        XCTAssertEqual(AchievementText.next(Self.status(.bookshelf, level: 1, value: 55_542), locale: en),
                       "Next tier: as many words as The Hobbit. 39,458 words to go.")
        XCTAssertEqual(AchievementText.next(Self.status(.chatterbox, level: 1, value: 61), locale: en),
                       "Next tier at 100 dictations in one day. Record so far: 61 dictations.")
        XCTAssertEqual(AchievementText.next(Self.status(.wellTravelled, level: 1, value: 3), locale: en), "Next tier at 5 apps, 2 apps to go.")
        XCTAssertNil(AchievementText.next(Self.status(.wellTravelled, level: 3, value: 16), locale: en), "no tier left")
        XCTAssertNil(AchievementText.next(Self.status(.polyglot, value: 1), locale: en), "no tiers")
    }

    func testEveryAchievementHasItsWords() {
        for id in AchievementID.allCases {
            let d = Achievements.definition(id)
            for tier in 1...d.tiers {
                let condition = AchievementText.condition(id, tier: tier, locale: en)
                XCTAssertTrue(condition.hasSuffix("."), "\(id) \(tier): \(condition)")
                XCTAssertFalse(condition.contains("—") || condition.contains("–") || condition.contains("·"), condition)
            }
            XCTAssertFalse(AchievementText.name(id).isEmpty)
        }
        XCTAssertEqual(AchievementText.condition(.bookshelf, tier: 3, locale: en), "As many words as the Bible.")
        XCTAssertEqual(AchievementText.condition(.longBreath, tier: 1, locale: en), "One dictation over 1 min.")
        XCTAssertEqual(AchievementText.condition(.timeBack, tier: 1, locale: en), "1 hour saved by dictating instead of typing.")
        XCTAssertEqual([1, 2, 3].map { AchievementText.name(.regular, tier: $0) }, ["Regular", "Familiar Voice", "Old Friend"])
        XCTAssertEqual([1, 2, 3, 4, 5].map { AchievementText.material(tier: $0, of: 5) }, ["ink", "bronze", "silver", "gold", "gold"])
        XCTAssertEqual([1, 2, 3].map { AchievementText.material(tier: $0, of: 3) }, ["ink", "silver", "gold"])
    }

    /// Minutes and seconds are written as on the Stats pane (“38 min”, “12 h 49 min”, “14 s”): no abbreviation point,
    /// so no line ends in two.
    func testUnitsAsOnTheStatsPaneAndNoDoublePoints() {
        XCTAssertEqual(AchievementText.length(seconds: 34), "34 s")
        XCTAssertEqual(AchievementText.length(seconds: 74), "1 min 14 s")
        XCTAssertEqual(AchievementText.length(seconds: 180), "3 min")
        XCTAssertEqual(AchievementText.minutes(seconds: 300), "5 min")
        XCTAssertEqual(AchievementText.next(Self.status(.longBreath, value: 34), locale: en), "Longest so far: 34 s.")
        XCTAssertEqual(AchievementText.next(Self.status(.timeBack, value: 22), locale: en), "38 min to go.")
    }

    /// Any language (run with `-testLanguage de` too): no line has two points in a row or a spelled-out unit.
    func testNoDoublePointsInAnyLine() {
        let locale = Formatting.uiLocale
        for id in AchievementID.allCases {
            let d = Achievements.definition(id)
            for level in 0...d.tiers {
                for value in [0.0, 34, 74, 1_000] {
                    let text = AchievementText.popover(Self.status(id, level: level, stamped: level, value: value), locale: locale)
                    for line in [text.name, text.tier, text.condition, text.date, text.next].compactMap({ $0 }) {
                        XCTAssertFalse(line.contains(".."), line)
                        for unit in ["sec", "Sek", "minute", "Minute", "Min."] { XCTAssertFalse(line.contains(unit), line) }
                    }
                }
            }
        }
    }

    /// Popovers open below (CARD.md); only the last row's opens above, and only when nothing is below the card.
    func testLastRowOpensThePopoverAboveOnlyWithoutRoomBelow() {
        let rows: [CGFloat] = [54, 146]
        let first = CGRect(x: 20, y: rows[0], width: 60, height: 60), last = CGRect(x: 100, y: rows[1], width: 60, height: 60)
        XCTAssertFalse(AchievementsCardLayout.opensAbove(first, lastRowTop: rows[1], roomBelow: false))
        XCTAssertTrue(AchievementsCardLayout.opensAbove(last, lastRowTop: rows[1], roomBelow: false))
        XCTAssertFalse(AchievementsCardLayout.opensAbove(last, lastRowTop: rows[1], roomBelow: true))
    }

    /// The folded header shows the counter in two parts; the second, in the accent colour, only when something is ready.
    func testCounterParts() {
        let ready = AchievementCardContent(all([Self.status(.firstWords, level: 1), Self.status(.tales, level: 1, stamped: 1)]))
        XCTAssertEqual(ready.reachedPart, "2 of 20")
        XCTAssertEqual(ready.readyPart, "1 ready to stamp")
        XCTAssertEqual(ready.counter, "2 of 20, 1 ready to stamp")
        XCTAssertNil(AchievementCardContent(all([])).readyPart)
    }

    /// What is left always names what it counts, in the singular for one.
    func testWhatIsLeftSaysWhatItCounts() {
        XCTAssertEqual(AchievementText.next(Self.status(.regular, value: 0), locale: en), "7 days to go.")
        XCTAssertEqual(AchievementText.next(Self.status(.regular, value: 6), locale: en), "1 day to go.")
        XCTAssertEqual(AchievementText.next(Self.status(.tales, value: 9), locale: en), "1 dictation to go.")
        XCTAssertEqual(AchievementText.next(Self.status(.wordCollector, value: 3), locale: en), "7 words to go.")
        XCTAssertEqual(AchievementText.next(Self.status(.wordCollector, level: 1, value: 49), locale: en),
                       "Next tier at 50 glossary words, 1 word to go.")
        XCTAssertEqual(AchievementText.next(Self.status(.bookshelf, value: 8_000), locale: en), "9,000 words to go.")
        XCTAssertEqual(AchievementText.next(Self.status(.wellTravelled, level: 1, value: 4), locale: en), "Next tier at 5 apps, 1 app to go.")
        // Every “to go” line of every achievement names a unit: a bare number never stands before “to go”.
        let bare = try! NSRegularExpression(pattern: "\\d to go")
        for id in AchievementID.allCases {
            let d = Achievements.definition(id)
            for level in 0..<d.tiers {
                for value in [0.0, 1, 7, 61] {
                    guard let line = AchievementText.next(Self.status(id, level: level, value: value), locale: en) else { continue }
                    XCTAssertNil(bare.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)), line)
                }
            }
        }
    }

    func testAccessibilityLabels() {
        XCTAssertEqual(AchievementText.accessibilityLabel(Self.status(.firstWords, level: 1)), "First Words, ready to stamp. Click to stamp.")
        XCTAssertEqual(AchievementText.accessibilityLabel(Self.status(.bookworm)), "Bookworm, locked.")
        XCTAssertEqual(AchievementText.accessibilityLabel(Self.status(.tales, level: 2, stamped: 2)), "Tales, stamped, tier 2 of 4.")
        XCTAssertEqual(AchievementText.accessibilityLabel(Self.status(.sayMyName, level: 1, stamped: 1)), "Say My Name, stamped.")
    }

    // MARK: With the store

    func testStampingThroughTheStoreLeavesTheHighestPrint() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vypo-ach-card-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        var seed = AchievementState()
        seed.dictations = 150
        let store = AchievementStore(store: Store(directory: dir), collecting: true) { seed }
        let before = AchievementCardContent(store.all)
        let tales = before.slots.first { $0.id == .tales }!
        XCTAssertEqual(tales.face, .vermilion)
        XCTAssertEqual(tales.stampedArt.state, "tier2")
        store.stamp(.tales)
        let after = AchievementCardContent(store.all).slots.first { $0.id == .tales }!
        XCTAssertNil(after.face)
        XCTAssertEqual(after.art, tales.stampedArt)
    }
}
