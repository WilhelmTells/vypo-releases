import XCTest
@testable import vypo

/// 0.6.0: Try it never raises a false alarm. If ⌘V doesn't bring the text into vypo's own field although
/// Accessibility is on, the step writes it there itself, says “Recognized”, and a late ⌘V doesn't double it.
@MainActor
final class TryItFallbackTests: XCTestCase {
    private func state(ax: Bool = true, outcome: TryItOutcome?) -> TryItState {
        TryItState(model: .ready, focused: true, activity: .idle, outcome: outcome, accessibilityTrusted: ax)
    }

    // MARK: Outcome mapping

    func testPastedAndArrivedIsInserted() {
        let o = TryItState.outcome(for: .pasted("Hi"), accessibilityTrusted: true) { _ in true }
        XCTAssertEqual(o, .inserted("Hi"))
        XCTAssertFalse(TryItState.needsFallback(o))
        XCTAssertEqual(state(outcome: o).resultLine, .inserted("Hi"))
    }

    func testPastedNotArrivedWithAccessibilityOnIsRecognizedAndWritten() {
        let o = TryItState.outcome(for: .pasted("Hi"), accessibilityTrusted: true) { _ in false }
        XCTAssertEqual(o, .recognized("Hi"))
        XCTAssertTrue(TryItState.needsFallback(o))
        XCTAssertEqual(state(outcome: o).resultLine, .recognized("Hi"))
    }

    func testAccessibilityOffStaysCouldntPasteWithoutFallback() {
        let o = TryItState.outcome(for: .pasted("Hi"), accessibilityTrusted: false) { _ in false }
        XCTAssertEqual(o, .couldntPaste(heard: "Hi"))
        XCTAssertFalse(TryItState.needsFallback(o))
        XCTAssertEqual(state(ax: false, outcome: o).resultLine, .couldntPaste(heard: "Hi"))
    }

    func testRealProblemsStayUnchanged() {
        func map(_ r: DictationOutcome) -> TryItOutcome { TryItState.outcome(for: r, accessibilityTrusted: true) { _ in false } }
        XCTAssertEqual(map(.nothingHeard), .nothingHeard)
        XCTAssertEqual(map(.notInYourLanguages(heard: "Hallo")), .notInYourLanguages(heard: "Hallo"))
        XCTAssertEqual(map(.modelFailed), .modelFailed)
        XCTAssertEqual(map(.anotherWindowInFront("Hi")), .anotherWindowInFront(heard: "Hi"))
        for o in [map(.nothingHeard), map(.notInYourLanguages(heard: "x")), map(.modelFailed), map(.anotherWindowInFront("Hi"))] {
            XCTAssertFalse(TryItState.needsFallback(o))
        }
    }

    // MARK: Writing the text

    func testFallbackAppendsWithASpace() {
        XCTAssertEqual(TryItFallback.write(" Hello. ", into: ""), "Hello.")
        XCTAssertEqual(TryItFallback.write("Hello.", into: "First."), "First. Hello.")
        XCTAssertEqual(TryItFallback.write("Hello.", into: "First.\n"), "First.\nHello.")
        XCTAssertEqual(TryItFallback.write("  ", into: "First."), "First.")
    }

    // MARK: No double text

    func testLateCommandVAfterTheFallbackLeavesTheTextOnce() {
        let wanted = "vypo turns my voice into text on my own Mac."
        let afterFallback = TryItFallback.write(wanted, into: "")
        // The late paste lands at the end, at the start, with smart spacing's leading space, or in the middle.
        for late in [afterFallback + wanted, wanted + afterFallback, afterFallback + " " + wanted, " " + wanted + afterFallback] {
            XCTAssertEqual(TryItFallback.withoutLatePaste(old: afterFallback, new: late, wanted: wanted), afterFallback, late)
        }
        let earlier = TryItFallback.write(wanted, into: "Earlier text.")
        let middle = "Earlier text. " + wanted + " " + wanted
        XCTAssertEqual(TryItFallback.withoutLatePaste(old: earlier, new: middle, wanted: wanted), earlier)
    }

    func testTheGuardKeepsTheFallbackItselfAndDropsTheLatePasteOnce() {
        let wanted = "Hello there."
        let now = ContinuousClock.now
        let written = TryItFallback.write(wanted, into: "Before.")
        let g = TryItFallback.LatePasteGuard(text: wanted, written: written, now: now)
        // The fallback's own write is an insertion of the same text: never undone.
        XCTAssertNil(g.fix(old: "Before.", new: written, now: now))
        // The late ⌘V a second later: the field goes back to the text once.
        let late = written + " " + wanted
        XCTAssertEqual(g.fix(old: written, new: late, now: now + .seconds(1)), written)
        // Setting it back is a deletion: left alone, so nothing loops.
        XCTAssertNil(g.fix(old: late, new: written, now: now + .seconds(1)))
        // After the window the guard is off.
        XCTAssertNil(g.fix(old: written, new: late, now: now + TryItFallback.lateWindow))
    }

    func testOtherChangesAreLeftAlone() {
        let wanted = "Hello."
        // Typing, deleting and a different text are not a late paste.
        XCTAssertNil(TryItFallback.withoutLatePaste(old: "Hello.", new: "Hello. x", wanted: wanted))
        XCTAssertNil(TryItFallback.withoutLatePaste(old: "Hello.", new: "Hello", wanted: wanted))
        XCTAssertNil(TryItFallback.withoutLatePaste(old: "Hello.", new: "Hello. Goodbye.", wanted: wanted))
        XCTAssertNil(TryItFallback.withoutLatePaste(old: "Hello.", new: "Hello.", wanted: wanted))
        XCTAssertNil(TryItFallback.withoutLatePaste(old: "", new: "Hello.", wanted: ""))
    }

    // MARK: Preparing

    func testPreparingLocksTheFieldWithoutAPercentage() {
        let preparing = TryItState(model: .preparing, focused: false)
        XCTAssertEqual(preparing.area, .locked(.preparing))
        XCTAssertNil(preparing.resultLine)
        XCTAssertEqual(TryItState(model: .loading(percent: 64)).area, .locked(.download(percent: 64)))
        // From the model's real state, as the path bar reads it.
        let compiling = ModelBadge.make(state: .downloading(0.95), loadFailed: false, failure: nil)
        XCTAssertEqual(TryItState.modelStatus(for: compiling), .preparing)
        let downloading = ModelBadge.make(state: .downloading(0.58), loadFailed: false, failure: nil)
        XCTAssertEqual(TryItState.modelStatus(for: downloading), .loading(percent: 64))
    }
}
