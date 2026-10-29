import XCTest
@testable import vypo

@MainActor
final class LanguageChoiceTests: XCTestCase {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "vypo.test.\(UUID().uuidString)")! }

    func testPreselectionFromMacLanguages() {
        XCTAssertEqual(Lang.preselection(preferred: ["fr-CH", "de-DE", "fr-FR", "ja-JP"]), [.fr, .de])
        XCTAssertEqual(Lang.preselection(preferred: ["ja-JP"]), [.en])
        // Slovenian isn't offered.
        XCTAssertEqual(Lang.preselection(preferred: ["sl-SI", "pt-BR"]), [.pt])
    }

    func testFirstRunIsTheMacLanguagesPlusEnglish() {
        XCTAssertEqual(Preferences(defaults: defaults(), preferredLanguages: ["de-DE"]).languages, [.de, .en])
        XCTAssertEqual(Preferences(defaults: defaults(), preferredLanguages: ["en-US"]).languages, [.en])
        XCTAssertEqual(Preferences(defaults: defaults(), preferredLanguages: ["tr-TR"]).languages, [.en])
        XCTAssertEqual(Preferences(defaults: defaults(), preferredLanguages: ["fr-FR", "en-GB", "de-DE"]).languages, [.fr, .en, .de])
    }

    func testFirstRunChoiceIsKeptWhenItIsLaterRead() {
        let d = defaults()
        _ = Preferences(defaults: d, preferredLanguages: ["de-DE"])
        // A later start with another Mac language list reads what was stored.
        XCTAssertEqual(Preferences(defaults: d, preferredLanguages: ["fr-FR"]).languages, [.de, .en])
    }

    func testSavedLanguagesAreNotChangedByTheNewDefault() {
        let d = defaults()
        d.set(["de"], forKey: DefaultsKey.languages)
        XCTAssertEqual(Preferences(defaults: d, preferredLanguages: ["de-DE"]).languages, [.de])
    }

    func testExistingInstallKeepsEnglishAndGerman() {
        let d = defaults()
        d.set(true, forKey: DefaultsKey.onboardingCompleted)
        XCTAssertEqual(Preferences(defaults: d).languages, [.en, .de])
    }

    /// A new user who keeps the preselection must still have it after onboarding and a relaunch.
    func testPreselectionSurvivesOnboarding() {
        let d = defaults()
        let prefs = Preferences(defaults: d)
        let preselected = prefs.languages
        prefs.onboardingCompleted = true
        XCTAssertEqual(Preferences(defaults: d).languages, preselected)
        XCTAssertEqual(d.stringArray(forKey: DefaultsKey.languages), preselected.map(\.rawValue))
    }

    func testStoredChoiceLoads() {
        let d = defaults()
        d.set(["fr", "xx"], forKey: DefaultsKey.languages)
        XCTAssertEqual(Preferences(defaults: d).languages, [.fr])
    }

    func testLastLanguageCannotBeUnchosen() {
        let d = defaults()
        d.set(["en"], forKey: DefaultsKey.languages)
        let prefs = Preferences(defaults: d)
        prefs.setChosen(.en, false)
        XCTAssertEqual(prefs.languages, [.en])
        prefs.setChosen(.fr, true)
        prefs.setChosen(.en, false)
        XCTAssertEqual(prefs.languages, [.fr])
        XCTAssertEqual(Preferences(defaults: d).languages, [.fr])
    }

    func testNoFillerWordsWithoutExtras() {
        XCTAssertEqual(Preferences(defaults: defaults()).fillerWords(for: .fr), [])
    }
}
