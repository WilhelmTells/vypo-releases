import XCTest
@testable import vypo

final class BenchmarkCasesTests: XCTestCase {
    func testLoadsTheCases() throws {
        let set = try BenchmarkSet.load()
        XCTAssertEqual(set.cases.count, 65)
        XCTAssertEqual(set.glossary.count, 24)
        XCTAssertEqual(set.cases.filter { $0.kind == .hit }.count, 42)
        XCTAssertEqual(set.cases.filter { $0.kind == .trap }.count, 18)
        XCTAssertEqual(Set(set.cases.map(\.id)).count, 65)
    }

    func testCasesAreConsistent() throws {
        let set = try BenchmarkSet.load()
        // Spellings (`Spellings.defaultList`) are checked like glossary terms.
        let terms = Set(set.glossary.map(\.term)).union(Spellings.defaultList)
        for c in set.cases {
            for t in c.terms {
                XCTAssertTrue(terms.contains(t), c.id)
                XCTAssertTrue(c.text.contains(t), c.id)
            }
            for k in c.keep { XCTAssertTrue(c.text.contains(k), c.id) }
            // A trap may also forbid the capitalised form of a word it keeps (“Pin” must not become “PIN”).
            for f in c.forbid { XCTAssertTrue(terms.contains(f) || c.keep.contains { $0.uppercased() == f }, c.id) }
            XCTAssertEqual(c.kind == .hit, !c.terms.isEmpty, c.id)
            XCTAssertEqual(c.kind == .trap, !c.keep.isEmpty, c.id)
        }
    }

    func testEntriesKeepAliases() throws {
        let entries = try BenchmarkSet.load().entries
        let klaro = try XCTUnwrap(entries.first { $0.term == "Klaro" })
        XCTAssertEqual(klaro.soundsLike, ["Claro", "Klaru", "Klaroh"])
        XCTAssertEqual(Set(entries.map(\.createdAt)).count, entries.count)
    }
}
