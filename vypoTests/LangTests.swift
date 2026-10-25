import NaturalLanguage
import XCTest
@testable import vypo

final class LangTests: XCTestCase {
    func testTwentyLanguages() {
        XCTAssertEqual(Lang.allCases.count, 20)
        XCTAssertEqual(Set(Lang.allCases.map(\.rawValue)),
                       ["bg", "cs", "da", "de", "el", "en", "es", "fi", "fr", "hr", "hu", "it", "nl", "pl", "pt", "ro", "ru", "sk", "sv", "uk"])
    }

    /// History, Stats and undo memory stored `en`/`de` before.
    func testStoredCodesStillDecode() throws {
        let decoded = try JSONDecoder().decode([Lang].self, from: Data(#"["en","de"]"#.utf8))
        XCTAssertEqual(decoded, [.en, .de])
    }

    func testExtrasOnlyForEnglishAndGerman() {
        XCTAssertEqual(Set(Lang.allCases.filter(\.hasExtras)), [.en, .de])
        XCTAssertTrue(FillerRemover.defaultWords(.fr).isEmpty)
        XCTAssertTrue(SpokenPunctuation.phrases(.fr).isEmpty)
        XCTAssertEqual(SpokenPunctuation.apply("bonjour virgule ça va", language: .fr), "bonjour virgule ça va")
    }

    func testQuotes() {
        XCTAssertTrue(Lang.de.quotes(typographic: true) == ("„", "“"))
        XCTAssertTrue(Lang.en.quotes(typographic: true) == ("“", "”"))
        XCTAssertEqual(Lang.fr.quotes(typographic: true).open, "«")
        XCTAssertTrue(Lang.en.quotes(typographic: false) == ("\"", "\""))
    }

    func testNamesAndNLLanguages() {
        for lang in Lang.allCases {
            XCTAssertFalse(lang.name.isEmpty, lang.rawValue)
            XCTAssertNotEqual(lang.nlLanguage, .undetermined, lang.rawValue)
        }
        XCTAssertEqual(Lang.fr.nlLanguage, .french)
    }
}
