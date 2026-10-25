import AppKit
import SwiftUI
import XCTest
@testable import vypo

/// The dots of “Collecting diagnostics…” really move: the wave is a function of time, each dot is a beat
/// behind the one before, and the hosted view draws differently a moment later.
@MainActor
final class WorkingDotsTests: XCTestCase {
    func testWaveIsZeroToOneAndShifted() {
        for t in stride(from: 0.0, to: 2.2, by: 0.05) {
            for dot in 0..<3 { XCTAssertTrue((0...1).contains(WorkingDots.lift(dot: dot, at: t))) }
        }
        // Dot 0 peaks at a quarter period; dot 1 later.
        let peak = WorkingDots.period / 4
        XCTAssertEqual(WorkingDots.lift(dot: 0, at: peak), 1, accuracy: 0.001)
        XCTAssertLessThan(WorkingDots.lift(dot: 1, at: peak), 0.9)
        XCTAssertEqual(WorkingDots.lift(dot: 0, at: 0), WorkingDots.lift(dot: 0, at: WorkingDots.period), accuracy: 0.001)
    }

    private func render(_ view: some View, wait: TimeInterval) throws -> Data {
        let size = CGSize(width: 40, height: 20)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height).background(Color.black))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(wait))
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        window.close()
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    func testLiveDotsChangeOverTime() throws {
        let early = try render(WorkingDots(color: .white), wait: 0.15)
        // Same clock, a quarter of a round later: sample both within one test, several tries to dodge a coincidence.
        var differs = false
        for _ in 0..<4 {
            let later = try render(WorkingDots(color: .white), wait: 0.3)
            if later != early { differs = true; break }
        }
        XCTAssertTrue(differs, "the dots look the same at different times")
    }

    func testFixedTimesDrawDifferently() throws {
        let a = try render(WorkingDots(color: .white, time: 0), wait: 0.1)
        let b = try render(WorkingDots(color: .white, time: WorkingDots.period / 4), wait: 0.1)
        XCTAssertNotEqual(a, b)
        if let dir = ProcessInfo.processInfo.environment["VYPO_SNAPSHOT_DIR"] {
            for (i, t) in [0.0, 0.14, 0.28, 0.42, 0.56, 0.7].enumerated() {
                try render(WorkingDots(color: .white, time: t), wait: 0.1).write(to: URL(fileURLWithPath: dir).appendingPathComponent("dots-\(i).png"))
            }
        }
    }
}
