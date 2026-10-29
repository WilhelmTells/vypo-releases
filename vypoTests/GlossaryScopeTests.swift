import XCTest
@testable import vypo

final class GlossaryScopeTests: XCTestCase {
    private func entry(_ term: String, scope: String) -> String {
        #"{"createdAt":"2026-10-23T15:22:54Z","id":"\#(UUID().uuidString)","scope":"\#(scope)","soundsLike":[],"term":"\#(term)"}"#
    }

    /// `glossary.json` as written before the language choice.
    func testOldScopesDecode() throws {
        let json = "[\(entry("Klaro", scope: "all")),\(entry("Kubernetes", scope: "en")),\(entry("Bahn", scope: "de"))]"
        let entries = try Store.decoder.decode([GlossaryEntry].self, from: Data(json.utf8))
        XCTAssertEqual(entries.map(\.scope), [.all, .only(.en), .only(.de)])
        let written = String(decoding: try Store.encoder.encode(entries[1]), as: UTF8.self)
        XCTAssertTrue(written.contains(#""scope" : "en""#) || written.contains(#""scope":"en""#), written)
    }

    func testNewScope() throws {
        let fr = try Store.decoder.decode(GlossaryEntry.self, from: Data(entry("Mistral", scope: "fr").utf8))
        XCTAssertEqual(fr.scope, .only(.fr))
        let back = try Store.decoder.decode(GlossaryEntry.self, from: try Store.encoder.encode(fr))
        XCTAssertEqual(back.scope, .only(.fr))
        let unknown = try Store.decoder.decode(GlossaryEntry.self, from: Data(entry("X", scope: "xx").utf8))
        XCTAssertEqual(unknown.scope, .all)
    }

    func testApplies() {
        XCTAssertTrue(GlossaryScope.only(.fr).applies(to: .fr))
        XCTAssertFalse(GlossaryScope.only(.fr).applies(to: .en))
        XCTAssertTrue(Lang.allCases.allSatisfy(GlossaryScope.all.applies))
    }

    /// An entry for a language that's no longer chosen keeps its scope when edited.
    func testPickerScopesKeepUnchosenCurrent() {
        XCTAssertEqual(GlossaryScope.pickerScopes(chosen: [.en, .de], current: .only(.fr)), [.all, .only(.en), .only(.de), .only(.fr)])
        XCTAssertEqual(GlossaryScope.pickerScopes(chosen: [.en, .de], current: .all), [.all, .only(.en), .only(.de)])
    }
}
