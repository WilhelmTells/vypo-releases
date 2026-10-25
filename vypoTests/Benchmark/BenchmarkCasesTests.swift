import XCTest
@testable import vypo

final class BenchmarkCasesTests: XCTestCase {
    func testLoadsFortyCases() throws {
        let set = try BenchmarkSet.load()
        XCTAssertEqual(set.cases.count, 40)
        XCTAssertEqual(set.glossary.count, 23)
        XCTAssertEqual(set.cases.filter { $0.kind == .hit }.count, 25)
        XCTAssertEqual(set.cases.filter { $0.kind == .trap }.count, 10)
        XCTAssertEqual(Set(set.cases.map(\.id)).count, 40)
    }

    func testCasesAreConsistent() throws {
        let set = try BenchmarkSet.load()
        let terms = Set(set.glossary.map(\.term))
        for c in set.cases {
            for t in c.terms {
                XCTAssertTrue(terms.contains(t), c.id)
                XCTAssertTrue(c.text.contains(t), c.id)
            }
            for k in c.keep { XCTAssertTrue(c.text.contains(k), c.id) }
            for f in c.forbid { XCTAssertTrue(terms.contains(f), c.id) }
            XCTAssertEqual(c.kind == .hit, !c.terms.isEmpty, c.id)
            XCTAssertEqual(c.kind == .trap, !c.keep.isEmpty, c.id)
        }
    }

    func testEntriesKeepAliases() throws {
        let entries = try BenchmarkSet.load().entries
        let claus = try XCTUnwrap(entries.first { $0.term == "Claus" })
        XCTAssertEqual(claus.soundsLike, ["Kloot", "Clot", "Klod"])
        XCTAssertEqual(Set(entries.map(\.createdAt)).count, entries.count)
    }
}
