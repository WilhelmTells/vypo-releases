import XCTest
@testable import vypo

final class TextFieldProbeTests: XCTestCase {
    private func element(_ role: String?, range: Bool = false, editable: Bool = false) -> TextFieldProbe.Focus {
        .element(role: role, hasSelectedRange: range, editable: editable)
    }

    func testTextRolesTakeText() {
        for role in ["AXTextField", "AXTextArea", "AXComboBox"] {
            XCTAssertTrue(TextFieldProbe.acceptsText(element(role)), role)
        }
    }

    /// Web editors and Electron report a group or web area with a cursor.
    func testCursorOrEditableTakesText() {
        XCTAssertTrue(TextFieldProbe.acceptsText(element("AXWebArea", range: true)))
        XCTAssertTrue(TextFieldProbe.acceptsText(element("AXGroup", editable: true)))
    }

    func testOtherElementsDont() {
        XCTAssertFalse(TextFieldProbe.acceptsText(element("AXList")))
        XCTAssertFalse(TextFieldProbe.acceptsText(element("AXButton")))
        XCTAssertFalse(TextFieldProbe.acceptsText(element(nil)))
    }

    /// The Desktop, Finder without a selection.
    func testNothingFocusedDoesnt() {
        XCTAssertFalse(TextFieldProbe.acceptsText(.nothing))
    }

    /// A slow app that doesn't answer in time is treated as a text field, so the clipboard comes back as before.
    func testNoAnswerTakesText() {
        XCTAssertTrue(TextFieldProbe.acceptsText(.unknown(AXError.cannotComplete.rawValue)))
    }

    func testTextFieldPastes() {
        XCTAssertEqual(TextFieldProbe.output(for: element("AXTextArea"), app: "com.apple.TextEdit"), .paste)
        XCTAssertEqual(TextFieldProbe.output(for: element("AXTextField"), app: "com.apple.finder"), .paste)
    }

    /// Accessibility may be wrong (Electron), so other apps still get ⌘V.
    func testNoTextFieldPastesAndKeeps() {
        XCTAssertEqual(TextFieldProbe.output(for: element("AXWebArea"), app: "com.tinyspeck.slackmacgap"), .pasteAndKeep)
        XCTAssertEqual(TextFieldProbe.output(for: .nothing, app: nil), .pasteAndKeep)
    }

    /// The Finder and the Desktop turn pasted text into a file.
    func testFinderOnlyKeeps() {
        XCTAssertEqual(TextFieldProbe.output(for: element("AXList"), app: "com.apple.finder"), .keep)
        XCTAssertEqual(TextFieldProbe.output(for: .nothing, app: "com.apple.finder"), .keep)
    }

    /// The Desktop reports a group with a selected text range (2026-10-23), so in the Finder only a text role counts.
    func testFinderNeedsTextRole() {
        XCTAssertEqual(TextFieldProbe.output(for: element("AXGroup", range: true), app: "com.apple.finder"), .keep)
        XCTAssertEqual(TextFieldProbe.output(for: element("AXGroup", editable: true), app: "com.apple.finder"), .keep)
        XCTAssertEqual(TextFieldProbe.output(for: .unknown(AXError.cannotComplete.rawValue), app: "com.apple.finder"), .keep)
    }
}
