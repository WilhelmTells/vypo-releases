import AppKit
import XCTest
@testable import vypo

/// The menu bar mark's timing functions and state sequence, as the animation spec of the mark defines them.
final class MenuBarIconTests: XCTestCase {
    func testStartRotation() {
        XCTAssertEqual(MenuBarMotion.startRotation(0), 0, accuracy: 1e-9)
        XCTAssertEqual(MenuBarMotion.startRotation(0.11), -14, accuracy: 1e-9)
        XCTAssertEqual(MenuBarMotion.startRotation(0.25), 4, accuracy: 1e-9)
        XCTAssertEqual(MenuBarMotion.startRotation(MenuBarMotion.startDuration), 0, accuracy: 1e-9)
        // Halfway through the first leg, eased out: 1 − 0.5³ = 0.875 of the way.
        XCTAssertEqual(MenuBarMotion.startRotation(0.055), -12.25, accuracy: 1e-9)
    }

    func testBellScale() {
        XCTAssertEqual(MenuBarMotion.bellScale(level: 0), 1.04, accuracy: 1e-9)
        XCTAssertEqual(MenuBarMotion.bellScale(level: 0.5), 1.095, accuracy: 1e-9)
        XCTAssertEqual(MenuBarMotion.bellScale(level: 1), 1.15, accuracy: 1e-9)
        XCTAssertEqual(MenuBarMotion.bellScale(level: 3), 1.15, accuracy: 1e-9)
    }

    func testCoaster() {
        let length = 300.0
        XCTAssertEqual(MenuBarMotion.coasterPhase(0, length: length), 20)
        XCTAssertEqual(MenuBarMotion.coasterPhase(0.5, length: length), -140)
        XCTAssertEqual(MenuBarMotion.coasterPhase(1, length: length), -300)
        XCTAssertEqual(MenuBarMotion.coasterOpacity(0), 0)
        XCTAssertEqual(MenuBarMotion.coasterOpacity(0.5), 1)
        XCTAssertEqual(MenuBarMotion.coasterOpacity(1), 0)
    }

    func testStar() {
        let start = MenuBarMotion.star(0), mid = MenuBarMotion.star(0.5), end = MenuBarMotion.star(1)
        XCTAssertEqual(start.distance, 2)
        XCTAssertEqual(start.radius, 3)
        XCTAssertEqual(start.opacity, 1)
        XCTAssertEqual(mid.distance, 23, accuracy: 1e-9)
        XCTAssertEqual(mid.radius, 9)
        XCTAssertEqual(mid.opacity, 1)
        XCTAssertEqual(end.distance, 26)
        XCTAssertEqual(end.opacity, 0)
    }

    func testShake() {
        XCTAssertEqual(MenuBarMotion.shake(0), 0, accuracy: 1e-9)
        XCTAssertEqual(MenuBarMotion.shake(0.5), 0, accuracy: 1e-9)
        XCTAssertEqual(MenuBarMotion.shake(1), 0, accuracy: 1e-9)
        XCTAssertEqual(MenuBarMotion.shake(1.0 / 12), 3.2 * 11 / 12, accuracy: 1e-9)
    }

    @MainActor func testCoasterTrackIsTheBandPlusTheLineIntoTheBell() {
        // The band (~155 units) plus ~75 from the tip up to the bell’s centre.
        XCTAssertGreaterThan(MenuBarMarkRenderer.coasterLength, 200)
        XCTAssertLessThan(MenuBarMarkRenderer.coasterLength, 260)
    }

    // MARK: Timeline

    func testRestsWithoutAnything() {
        var t = MenuBarMarkTimeline()
        XCTAssertEqual(t.advance(to: 10, level: 0), .rest)
        XCTAssertFalse(t.isAnimating)
    }

    func testWholeDictationUntinted() {
        var t = MenuBarMarkTimeline()
        t.beginRecording(at: 0)
        XCTAssertTrue(t.isAnimating)
        XCTAssertEqual(t.advance(to: 0.11, level: 0).rotation, -14, accuracy: 1e-9)
        // Listening keeps the link running and the bell enlarged, but never coloured.
        var f = t.advance(to: 1, level: 0)
        XCTAssertEqual(f.bell, 1.04, accuracy: 1e-6)
        XCTAssertEqual(f.tint, 0)
        XCTAssertTrue(t.isAnimating)

        t.beginProcessing(at: 2)
        _ = t.advance(to: 2, level: 0)
        f = t.advance(to: 2.1, level: 0)
        XCTAssertNotNil(f.coaster)
        // Laps repeat while processing.
        f = t.advance(to: 2.7, level: 0)
        XCTAssertNotNil(f.coaster)

        t.inserted(at: 3)
        f = t.advance(to: 3.1, level: 0)
        XCTAssertNotNil(f.star)
        t.ended(at: 3.1)
        // The lap and the star finish, then nothing runs.
        f = t.advance(to: 4, level: 0)
        XCTAssertEqual(f, .rest)
        XCTAssertFalse(t.isAnimating)
    }

    func testTintOptionColoursFromStartUntilAfterTheStar() {
        var t = MenuBarMarkTimeline()
        t.tintOption = true
        t.beginRecording(at: 0)
        for i in 0...20 { _ = t.advance(to: Double(i) * 0.016, level: 0) }
        XCTAssertEqual(t.advance(to: 0.33, level: 0).tint, 1)
        t.inserted(at: 1)
        _ = t.advance(to: 1, level: 0)
        XCTAssertEqual(t.advance(to: 1.2, level: 0).tint, 1, "waits for the star")
        var tint = 1.0
        for i in 0...30 { tint = t.advance(to: 1.22 + Double(i) * 0.016, level: 0).tint }
        XCTAssertEqual(tint, 0)
        _ = t.advance(to: 2, level: 0)
        XCTAssertFalse(t.isAnimating)
    }

    func testErrorShakesThenRests() {
        var t = MenuBarMarkTimeline()
        t.failed(at: 0)
        XCTAssertNotEqual(t.advance(to: 1.0 / 12 * MenuBarMotion.shakeDuration, level: 0).shake, 0)
        XCTAssertEqual(t.advance(to: 0.5, level: 0), .rest)
        XCTAssertFalse(t.isAnimating)
    }

    func testReduceMotionColoursInsteadOfMoving() {
        var t = MenuBarMarkTimeline()
        t.reduceMotion = true
        t.beginRecording(at: 0)
        var f = MenuBarMarkFrame()
        for i in 0...20 { f = t.advance(to: Double(i) * 0.016, level: 1) }
        XCTAssertEqual(f.rotation, 0)
        XCTAssertEqual(f.bell, 1)
        XCTAssertEqual(f.tint, 1)
        // Coloured and still: nothing left to animate while listening.
        XCTAssertFalse(t.isAnimating)
        t.beginProcessing(at: 1)
        XCTAssertNil(t.advance(to: 1.1, level: 0).coaster)
        t.inserted(at: 2)
        XCTAssertNil(t.advance(to: 2.1, level: 0).star)
        for i in 0...30 { f = t.advance(to: 2.3 + Double(i) * 0.016, level: 0) }
        XCTAssertEqual(f, .rest)
    }
}
