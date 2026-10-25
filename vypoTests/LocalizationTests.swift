import XCTest

/// Every string vypo shows has a German translation (Settings → General → App language).
final class LocalizationTests: XCTestCase {
    private func catalog(_ name: String) throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("vypo/\(name).xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return try XCTUnwrap(json?["strings"] as? [String: Any])
    }

    func testEveryStringHasAGermanTranslation() throws {
        for name in ["Localizable", "InfoPlist"] {
            let strings = try catalog(name)
            XCTAssertFalse(strings.isEmpty, name)
            let untranslated = strings.filter { _, value in
                let entry = value as? [String: Any]
                let de = (entry?["localizations"] as? [String: Any])?["de"] as? [String: Any]
                // A plain string, or plural variants that are all translated.
                let plural = (de?["variations"] as? [String: Any])?["plural"] as? [String: Any]
                let units = plural.map { $0.values.map { ($0 as? [String: Any])?["stringUnit"] as? [String: Any] } }
                    ?? [de?["stringUnit"] as? [String: Any]]
                return units.contains { $0?["state"] as? String != "translated" }
            }
            XCTAssertTrue(untranslated.isEmpty, "\(name): no German for \(untranslated.keys.sorted())")
        }
    }

    func testPlaceholdersSurviveTranslation() throws {
        let pattern = try NSRegularExpression(pattern: "%(\\d\\$)?(lld|@|%)")
        func placeholders(_ s: String) -> [String] {
            pattern.matches(in: s, range: NSRange(s.startIndex..., in: s)).map {
                String(s[Range($0.range(at: 2), in: s)!])
            }.sorted()
        }
        for (key, value) in try catalog("Localizable") {
            let entry = value as? [String: Any]
            let unit = ((entry?["localizations"] as? [String: Any])?["de"] as? [String: Any])?["stringUnit"] as? [String: Any]
            guard let german = unit?["value"] as? String else { continue }
            XCTAssertEqual(placeholders(key), placeholders(german), "“\(key)” → “\(german)”")
        }
    }
}
