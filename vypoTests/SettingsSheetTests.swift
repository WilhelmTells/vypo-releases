import AppKit
import SwiftUI
import XCTest
@testable import vypo

private final class SheetOpen: ObservableObject { @Published var value = true }

private struct SheetHost<C: View>: View {
    @ObservedObject var open: SheetOpen
    var content: C
    var body: some View { Color.clear.sheet(isPresented: $open.value) { content } }
}

private final class ShownLanguage: ObservableObject { @Published var language: Lang? }

private struct SwitchingFillerSheet: View {
    @ObservedObject var shown: ShownLanguage
    var app: AppState
    var body: some View { FillerWordsSheet(language: shown.language).environment(app) }
}

/// The pattern of the Settings sheets: what they save and when, how they close, and their wording.
@MainActor
final class SettingsSheetTests: XCTestCase {
    private func sampleApp() -> AppState {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vypo-sheets-\(UUID().uuidString)")
        let prefs = Preferences(defaults: UserDefaults(suiteName: "vypo.sheets.\(UUID().uuidString)")!)
        prefs.languages = [.en, .de]
        return AppState(prefs: prefs, store: Store(directory: dir))
    }

    private func spin(_ seconds: TimeInterval = 0.2) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

    private func textViews(in view: NSView) -> [NSTextView] {
        view.subviews.flatMap { sub in ((sub as? NSTextView).map { [$0] } ?? []) + textViews(in: sub) }
    }

    /// A sheet on a window, for as long as `body` runs. `isOpen` turns false when the sheet closes itself.
    private func present<V: View>(_ view: V, _ body: (NSWindow, () -> Bool) throws -> Void) throws {
        let open = SheetOpen()
        let parent = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 900, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        parent.contentView = NSHostingView(rootView: SheetHost(open: open, content: view))
        parent.makeKeyAndOrderFront(nil)
        let deadline = Date().addingTimeInterval(4)
        while parent.attachedSheet == nil, Date() < deadline { spin(0.05) }
        let sheet = try XCTUnwrap(parent.attachedSheet)
        sheet.makeKey()
        spin(0.4)
        defer {
            open.value = false
            spin(0.3)
            parent.contentView = nil
            parent.close()
        }
        try body(sheet) { open.value }
    }

    private func press(_ keyCode: UInt16, _ characters: String, in window: NSWindow) throws {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                                                       windowNumber: window.windowNumber, context: nil, characters: characters,
                                                       charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode))
            NSApp.sendEvent(event)
        }
        spin(0.6)
    }

    // MARK: Lists save as you type

    func testSpellingsAreSavedAsYouType() throws {
        let app = sampleApp()
        try present(SpellingsSheet().environment(app)) { sheet, _ in
            let editor = try XCTUnwrap(textViews(in: try XCTUnwrap(sheet.contentView)).first)
            XCTAssertNil(app.prefs.spellingsEdited, "Opening the sheet stores nothing")
            editor.setSelectedRange(NSRange(location: 0, length: 0))
            editor.insertText("Vypo\n", replacementRange: NSRange(location: 0, length: 0))
            spin()
            XCTAssertEqual(app.prefs.spellings.first, "Vypo")
        }
    }

    func testFillerWordsAreSavedAsYouTypeForTheShownLanguage() throws {
        let app = sampleApp()
        let german = app.prefs.fillerWords(for: .de)
        try present(FillerWordsSheet().environment(app)) { sheet, _ in
            let editors = textViews(in: try XCTUnwrap(sheet.contentView))
            XCTAssertEqual(editors.count, 1, "One field, whatever the number of languages")
            let english = try XCTUnwrap(editors.first)
            XCTAssertTrue(english.string.contains("uhm"), "Starts on the first chosen language")
            XCTAssertNil(app.prefs.fillerWordsEdited[.en], "Opening the sheet stores nothing")
            english.setSelectedRange(NSRange(location: 0, length: 0))
            english.insertText("like\n", replacementRange: NSRange(location: 0, length: 0))
            spin()
            XCTAssertEqual(app.prefs.fillerWords(for: .en).first, "like")
            XCTAssertEqual(app.prefs.fillerWords(for: .de), german)
        }
    }

    /// The picker has no view to reach from a test (SwiftUI draws it on macOS 26), so this switches through `language`,
    /// the same path the picker takes.
    func testSwitchingLanguagesKeepsTheirListsApart() throws {
        let app = sampleApp()
        app.prefs.languages = [.fr, .en, .hr]
        let english = app.prefs.fillerWords(for: .en)
        let shown = ShownLanguage()
        try present(SwitchingFillerSheet(shown: shown, app: app)) { sheet, _ in
            let content = try XCTUnwrap(sheet.contentView)
            let french = try XCTUnwrap(textViews(in: content).first)
            XCTAssertEqual(french.string, "euh\nheu\nhum")
            french.setSelectedRange(NSRange(location: 0, length: 0))
            french.insertText("bah\n", replacementRange: NSRange(location: 0, length: 0))
            spin()
            XCTAssertEqual(app.prefs.fillerWords(for: .fr), ["bah", "euh", "heu", "hum"])

            shown.language = .hr
            spin(0.4)
            XCTAssertEqual(textViews(in: content).first?.string, "", "Croatian has no list")
            XCTAssertNil(app.prefs.fillerWordsEdited[.hr], "Showing a language writes nothing into it")

            shown.language = .en
            spin(0.4)
            XCTAssertEqual(textViews(in: content).first?.string, english.joined(separator: "\n"))
            XCTAssertNil(app.prefs.fillerWordsEdited[.en])
            XCTAssertEqual(app.prefs.fillerWords(for: .fr), ["bah", "euh", "heu", "hum"])

            shown.language = .fr
            spin(0.4)
            XCTAssertEqual(textViews(in: content).first?.string, "bah\neuh\nheu\nhum")
        }
    }

    func testOneLanguageHasNoPicker() throws {
        func height(_ languages: [Lang]) throws -> CGFloat {
            let app = sampleApp()
            app.prefs.languages = languages
            var result: CGFloat = 0
            try present(FillerWordsSheet().environment(app)) { sheet, _ in
                XCTAssertTrue(textViews(in: try XCTUnwrap(sheet.contentView)).first?.string.isEmpty == false)
                result = sheet.frame.height
            }
            return result
        }
        XCTAssertLessThan(try height([.fr]), try height([.fr, .en]), "The picker's row is gone")
    }

    // MARK: Closing

    func testEscClosesAList() throws {
        try present(LanguagesSheet().environment(sampleApp())) { sheet, isOpen in
            try press(53, "\u{1B}", in: sheet)
            XCTAssertFalse(isOpen())
        }
    }

    func testReturnClosesAList() throws {
        try present(LanguagesSheet().environment(sampleApp())) { sheet, isOpen in
            try press(36, "\r", in: sheet)
            XCTAssertFalse(isOpen())
        }
    }

    func testEscClosesFromInsideAWordEditorAndKeepsWhatWasTyped() throws {
        let app = sampleApp()
        try present(SpellingsSheet().environment(app)) { sheet, isOpen in
            let editor = try XCTUnwrap(textViews(in: try XCTUnwrap(sheet.contentView)).first)
            sheet.makeFirstResponder(editor)
            editor.setSelectedRange(NSRange(location: 0, length: 0))
            editor.insertText("Vypo\n", replacementRange: NSRange(location: 0, length: 0))
            spin()
            try press(53, "\u{1B}", in: sheet)
            XCTAssertFalse(isOpen())
            XCTAssertEqual(app.prefs.spellings.first, "Vypo")
        }
    }

    func testReturnInsideAWordEditorIsANewLine() throws {
        let app = sampleApp()
        try present(SpellingsSheet().environment(app)) { sheet, isOpen in
            let editor = try XCTUnwrap(textViews(in: try XCTUnwrap(sheet.contentView)).first)
            sheet.makeFirstResponder(editor)
            let before = editor.string.count
            try press(36, "\r", in: sheet)
            XCTAssertTrue(isOpen())
            XCTAssertEqual(editor.string.count, before + 1)
        }
    }

    // MARK: Wording

    func testTheDefaultSetIsOnlyTranslatedOnScreen() {
        XCTAssertEqual(GlossarySet.general.displayName, String(localized: "General"))
        XCTAssertEqual(GlossarySet.general.name, "General")
        var renamed = GlossarySet.general
        renamed.name = "Arbeit"
        XCTAssertEqual(renamed.displayName, "Arbeit")
        XCTAssertEqual(GlossarySet(id: UUID(), name: "General", isActive: true).displayName, "General", "Only the default set")
    }

    private var german: Bundle { Bundle(path: Bundle.main.path(forResource: "de", ofType: "lproj")!)! }

    func testTermCountsHaveASingular() {
        XCTAssertEqual(String(localized: "\(1) terms", bundle: german), "1 Begriff")
        XCTAssertEqual(String(localized: "\(2) terms", bundle: german), "2 Begriffe")
        XCTAssertEqual(String(localized: "Add \(1) Terms", bundle: german), "1 Begriff hinzufügen")
        XCTAssertEqual(String(localized: "Found \(1) Terms in \("a.pdf")", bundle: german), "1 Begriff in a.pdf gefunden")
        XCTAssertEqual(String(localized: "Found \(3) Terms in \("a.pdf")", bundle: german), "3 Begriffe in a.pdf gefunden")
        XCTAssertEqual(String(localized: "Delete “\("Thesis")” and its \(1) terms?", bundle: german), "„Thesis“ und seinen 1 Begriff löschen?")
        XCTAssertEqual(String(localized: "Glossary: \(1) terms, \(1) in active sets", bundle: german), "Glossar: 1 Begriff, 1 in aktiven Sets")
        XCTAssertEqual(String(localized: "Glossary: \(2) terms, \(1) in active sets", bundle: german), "Glossar: 2 Begriffe, 1 in aktiven Sets")
        XCTAssertEqual(String(localized: "\(1) days, longest \(2) days", bundle: german), "1 Tag in Folge, längste Serie 2 Tage")
    }

    func testAlertTitlesAreTranslated() {
        XCTAssertEqual(String(localized: "No new terms found in \("a.pdf").", bundle: german), "Keine neuen Begriffe in a.pdf gefunden.")
    }

    func testFillerWordStringsNameTheLanguage() {
        XCTAssertEqual(String(localized: "No filler words for \("Französisch") yet. Add one per line.", bundle: german),
                       "Noch keine Füllwörter für Französisch. Füge eins pro Zeile hinzu.")
        XCTAssertEqual(String(localized: "Restore the default filler words for \("Französisch")?", bundle: german),
                       "Standard-Füllwörter für Französisch wiederherstellen?")
    }

    func testSpellingsTakeTheQuotesOfTheLanguage() {
        XCTAssertEqual(String(localized: "“\("Komma")”", bundle: german), "„Komma“")
        XCTAssertEqual(Replacement(spoken: ["Komma"], output: ",").summary, Formatting.quoted("Komma"))
        XCTAssertEqual(SpokenCharacter(spoken: ["Komma"], output: ",", alsoInSentence: false).summary(for: .de), Formatting.quoted("Komma"))
    }
}
