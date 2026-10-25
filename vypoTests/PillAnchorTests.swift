import CoreGraphics
import XCTest
@testable import vypo

final class PillAnchorTests: XCTestCase {
    private let visible = CGRect(x: 0, y: 80, width: 1440, height: 800)
    private let small = CGSize(width: 56, height: 26)
    private let big = CGSize(width: 200, height: 32)

    /// Grows from `small` to `big` with the given edges and returns both frames.
    private func grow(_ edges: SnapEdges, at anchor: CGPoint) -> (CGRect, CGRect) {
        (PillGeometry.frame(size: small, anchor: anchor, edges: edges),
         PillGeometry.frame(size: big, anchor: anchor, edges: edges))
    }

    func testBottomGrowsUpAndToBothSides() {
        let (a, b) = grow([.bottom], at: CGPoint(x: 720, y: 92))
        XCTAssertEqual(a.minY, b.minY)
        XCTAssertEqual(a.midX, b.midX)
        XCTAssertGreaterThan(b.maxY, a.maxY)
    }

    func testTopGrowsDown() {
        let (a, b) = grow([.top], at: CGPoint(x: 720, y: 868))
        XCTAssertEqual(a.maxY, b.maxY)
        XCTAssertEqual(a.midX, b.midX)
        XCTAssertLessThan(b.minY, a.minY)
    }

    func testLeftGrowsRight() {
        let (a, b) = grow([.left], at: CGPoint(x: 12, y: 400))
        XCTAssertEqual(a.minX, b.minX)
        XCTAssertEqual(a.midY, b.midY)
        XCTAssertGreaterThan(b.maxX, a.maxX)
    }

    func testRightGrowsLeft() {
        let (a, b) = grow([.right], at: CGPoint(x: 1428, y: 400))
        XCTAssertEqual(a.maxX, b.maxX)
        XCTAssertLessThan(b.minX, a.minX)
    }

    func testCornersGrowInward() {
        let (a, b) = grow([.bottom, .left], at: CGPoint(x: 12, y: 92))
        XCTAssertEqual(a.origin, b.origin)
        let (c, d) = grow([.top, .right], at: CGPoint(x: 1428, y: 868))
        XCTAssertEqual(c.maxX, d.maxX)
        XCTAssertEqual(c.maxY, d.maxY)
        let (e, f) = grow([.top, .left], at: CGPoint(x: 12, y: 868))
        XCTAssertEqual(e.minX, f.minX)
        XCTAssertEqual(e.maxY, f.maxY)
        let (g, h) = grow([.bottom, .right], at: CGPoint(x: 1428, y: 92))
        XCTAssertEqual(g.maxX, h.maxX)
        XCTAssertEqual(g.minY, h.minY)
    }

    func testNotSnappedGrowsFromCenter() {
        let (a, b) = grow([], at: CGPoint(x: 500, y: 500))
        XCTAssertEqual(a.midX, b.midX)
        XCTAssertEqual(a.midY, b.midY)
    }

    func testClampInsideVisibleFrame() {
        let f = PillGeometry.clamp(CGRect(x: 1400, y: 60, width: 200, height: 32), in: visible)
        XCTAssertEqual(f.maxX, visible.maxX - 12)
        XCTAssertEqual(f.minY, visible.minY + 12)
        let g = PillGeometry.clamp(CGRect(x: -50, y: 900, width: 200, height: 32), in: visible)
        XCTAssertEqual(g.minX, visible.minX + 12)
        XCTAssertEqual(g.maxY, visible.maxY - 12)
    }

    func testSnapToEdgeAndCorner() {
        let (f, edges) = PillGeometry.snap(CGRect(x: 15, y: 400, width: 56, height: 26), in: visible)
        XCTAssertEqual(edges, [.left])
        XCTAssertEqual(f.minX, 12)
        let (g, corner) = PillGeometry.snap(CGRect(x: 1440 - 56 - 20, y: 80 + 10, width: 56, height: 26), in: visible)
        XCTAssertEqual(corner, [.right, .bottom])
        XCTAssertEqual(g.maxX, 1428)
        XCTAssertEqual(g.minY, 92)
        let (_, none) = PillGeometry.snap(CGRect(x: 600, y: 400, width: 56, height: 26), in: visible)
        XCTAssertEqual(none, [])
    }

    func testDefaultIsBottomCenter() {
        let p = PillGeometry.defaultPlacement(in: visible)
        XCTAssertEqual(p.anchor, CGPoint(x: 720, y: 92))
        XCTAssertEqual(p.edges, [.bottom])
    }
}
