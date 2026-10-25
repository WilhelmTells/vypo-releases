import XCTest
@testable import vypo


final class AppSharesTests: XCTestCase {
    private func apps(_ words: [Int]) -> [(app: String, words: Int)] { words.enumerated().map { ("app\($0.offset)", $0.element) } }

    func testUpToFiveAppsHaveNoOtherRow() {
        let s = StatsMath.appShares(apps([50, 30, 10, 6, 4]))
        XCTAssertEqual(s.rows.map(\.percent), [50, 30, 10, 6, 4])
        XCTAssertNil(s.other)
        XCTAssertEqual(StatsMath.appShares([]), AppShares(rows: [], other: nil))
    }

    func testTheRestIsOneOtherRowAndEverythingAddsUpTo100() {
        let s = StatsMath.appShares(apps([40, 20, 15, 10, 5, 4, 3, 3]))
        XCTAssertEqual(s.rows.count, 5)
        XCTAssertEqual(s.other, OtherApps(count: 3, percent: 10))
        XCTAssertEqual(s.rows.map(\.percent).reduce(0, +) + (s.other?.percent ?? 0), 100)
        // Rounding doesn't break the total.
        for words in [[1, 1, 1, 1, 1, 1, 1], [33, 33, 33, 1, 1, 1, 1, 1, 1], [7, 7, 7, 7, 7, 7]] {
            let r = StatsMath.appShares(apps(words))
            XCTAssertEqual(r.rows.map(\.percent).reduce(0, +) + (r.other?.percent ?? 0), 100, "\(words)")
        }
    }

    /// Six apps: the sixth one is shown with its name, not as “Other (1 app)”.
    func testSixAppsShowTheSixth() {
        let s = StatsMath.appShares(apps([30, 25, 20, 15, 5, 5]))
        XCTAssertEqual(s.rows.map(\.app), ["app0", "app1", "app2", "app3", "app4", "app5"])
        XCTAssertEqual(s.rows.map(\.percent), [30, 25, 20, 15, 5, 5])
        XCTAssertNil(s.other)
    }

    func testSevenAppsHaveOtherWithTwo() {
        let s = StatsMath.appShares(apps([30, 25, 20, 15, 5, 3, 2]))
        XCTAssertEqual(s.rows.count, 5)
        XCTAssertEqual(s.other, OtherApps(count: 2, percent: 5))
        XCTAssertEqual(s.rows.map(\.percent).reduce(0, +) + 5, 100)
    }

    func testAppsWithoutWordsDontCount() {
        let s = StatsMath.appShares(apps([10, 0, 0]))
        XCTAssertEqual(s.rows.map(\.percent), [100])
        XCTAssertNil(s.other)
    }
}
