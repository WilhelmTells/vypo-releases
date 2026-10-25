import XCTest
@testable import vypo

/// The level card's scene (LAYERS.md, with the castle drawn smaller and the walk ending earlier so the
/// castle stands inside the card).
final class LevelSceneTests: XCTestCase {
    func testTheCastleStandsInsideTheCardAtEveryWidth() {
        for width: CGFloat in [560, 685, 760] {
            let castle = LevelSceneGeometry(width: width).castle
            let margin = LevelSceneGeometry.castleMargin
            XCTAssertGreaterThanOrEqual(castle.minX, margin, "\(width)")
            XCTAssertLessThanOrEqual(castle.maxX, width - margin, "\(width)")
            XCTAssertGreaterThanOrEqual(castle.minY, margin, "\(width)")
            XCTAssertLessThanOrEqual(castle.maxY, LevelSceneGeometry.height - margin, "\(width)")
            // The gate's threshold lies on the bar's top edge, and the road runs into it.
            XCTAssertEqual(castle.minX + LevelSceneGeometry.castleAnchor.x * LevelSceneGeometry.castleScale,
                           LevelSceneGeometry(width: width).gateX, accuracy: 0.001)
            XCTAssertEqual(castle.minY + LevelSceneGeometry.castleAnchor.y * LevelSceneGeometry.castleScale,
                           LevelSceneGeometry.barTop, accuracy: 0.001)
            XCTAssertEqual(LevelSceneGeometry(width: width).emptyBar.maxX, LevelSceneGeometry(width: width).gateX + 3, accuracy: 0.001)
        }
        XCTAssertGreaterThanOrEqual(LevelSceneGeometry.castleScale, 0.85)
    }

    func testTheBarAndTheBoyAt0And60And100Percent() {
        let g = LevelSceneGeometry(width: 685)
        XCTAssertEqual(g.x0, 60)
        XCTAssertEqual(g.x1, 609)
        XCTAssertEqual(g.boyX(0), 60)
        XCTAssertEqual(g.boyX(0.6), 389.4, accuracy: 0.001)
        XCTAssertEqual(g.boyX(1), 609)
        XCTAssertEqual(g.emptyBar, CGRect(x: 57, y: 205, width: 609 + 28 - 60 + 6, height: 18))
        // Never shorter than its two ends (11 + 9 pt with the overhang).
        XCTAssertEqual(g.fillBar(0), CGRect(x: 57, y: 205, width: 20, height: 18))
        XCTAssertEqual(g.fillBar(0.6).width, 389.4 - 60 + 6, accuracy: 0.001)
        XCTAssertEqual(g.fillBar(1).width, 609 - 60 + 6, accuracy: 0.001)
        for width: CGFloat in [560, 760] {
            let g = LevelSceneGeometry(width: width)
            XCTAssertEqual(g.boyX(1), width - 76)
            XCTAssertEqual(g.boyX(0), 60)
        }
    }

    func testTheArtIsCroppedFromTheMiddle() {
        XCTAssertEqual(LevelSceneGeometry(width: 560).artX, -100)
        XCTAssertEqual(LevelSceneGeometry(width: 685).artX, -37.5)
        XCTAssertEqual(LevelSceneGeometry(width: 760).artX, 0)
    }

    /// Boy and raven about 115 pt; the fanfare stars 26, 22 and 18 pt.
    func testTheFigureAndStarScale() {
        XCTAssertEqual(MascotCanvas.frame.height, 584 * 0.2323, accuracy: 0.01)
        XCTAssertEqual(MascotCanvas.starSize, 65 * 0.2323, accuracy: 0.01)
        let sizes = LevelUpMotion.reducedStars(at: 0).map(\.size)
        XCTAssertEqual(sizes.map { ($0).rounded() }, [26, 22, 18])
    }

    /// The level-up still: at 60 % of its flight each star is full size, opaque, at its distance from the bell.
    func testTheStarsPassTheirStillPositions() throws {
        let fanfare = LevelUpMotion.slide + LevelUpMotion.stars.start + 0.6 * LevelUpMotion.stars.life
        let star = try XCTUnwrap(LevelUpMotion.frame(at: fanfare, from: 0).stars.first)
        XCTAssertEqual(star.opacity, 1)
        // On the 12 fps grid, a moment short of 60 %.
        XCTAssertEqual(star.size, 1.75 * MascotCanvas.starSize, accuracy: 0.5)
        XCTAssertEqual(Double(hypot(star.offset.width, star.offset.height)), 17.2, accuracy: 1.5)
    }
}
