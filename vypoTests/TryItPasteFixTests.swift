import XCTest
@testable import vypo

/// 0.4.1: the onboarding's Try it dictation belongs to its own field and never pastes into another app.
@MainActor
final class TryItPasteFixTests: XCTestCase {
    // MARK: Result line

    private func state(ax: Bool, outcome: TryItOutcome?) -> TryItState {
        TryItState(model: .ready, focused: true, activity: .idle, outcome: outcome, accessibilityTrusted: ax)
    }

    func testPasteFailedWithAccessibilityOnShowsNoAccessibilityHint() {
        let line = state(ax: true, outcome: .couldntPaste(heard: "Hi")).resultLine
        XCTAssertEqual(line, .didntArrive(heard: "Hi"))
        let mapped = TryItState.outcome(for: .pasted("Hi"), accessibilityTrusted: true) { _ in false }
        XCTAssertEqual(state(ax: true, outcome: mapped).resultLine, .didntArrive(heard: "Hi"))
    }

    func testPasteFailedWithAccessibilityOffKeepsTheOldLineWithItsButton() {
        let mapped = TryItState.outcome(for: .pasted("Hi"), accessibilityTrusted: false) { _ in false }
        XCTAssertEqual(mapped, .couldntPaste(heard: "Hi"))
        XCTAssertEqual(state(ax: false, outcome: mapped).resultLine, .couldntPaste(heard: "Hi"))
        // Revoked after the failure: the hint appears then, too.
        XCTAssertEqual(state(ax: false, outcome: .didntArrive(heard: "Hi")).resultLine, .couldntPaste(heard: "Hi"))
    }

    func testAnotherWindowLineIsNotChangedByAccessibility() {
        XCTAssertEqual(state(ax: true, outcome: .anotherWindowInFront(heard: "Hi")).resultLine, .anotherWindowInFront(heard: "Hi"))
        XCTAssertEqual(state(ax: false, outcome: .anotherWindowInFront(heard: "Hi")).resultLine, .anotherWindowInFront(heard: "Hi"))
    }

    func testQuoteIsShortenedButNeverTheExplanation() {
        let long = String(repeating: "word ", count: 30)
        let shortened = TryItStep.shorten(long)
        XCTAssertLessThanOrEqual(shortened.count, 41)
        XCTAssertTrue(shortened.hasSuffix("…"))
    }

    // MARK: Waiting for the text

    func testTextThatArrivesLateButBeforeTheRestoreFinishedCountsAsInserted() async {
        var elapsed = Duration.zero
        var contains: Bool { elapsed >= .milliseconds(900) }          // later than the old single check at 700 ms
        var settled: Bool { elapsed >= .milliseconds(1200) }          // the restore finishes after that
        let arrived = await TryItWatch.textArrived(contains: { contains }, settled: { settled }, sleep: { elapsed += $0 })
        XCTAssertTrue(arrived)
    }

    func testTextThatNeverArrivesFailsSoonAfterTheRestoreFinished() async {
        var elapsed = Duration.zero
        let arrived = await TryItWatch.textArrived(contains: { false }, settled: { elapsed >= .milliseconds(80) }, sleep: { elapsed += $0 })
        XCTAssertFalse(arrived)
        XCTAssertLessThan(elapsed, .milliseconds(400))
    }

    func testAPasteThatNeverSettlesStopsAtTheCap() async {
        var elapsed = Duration.zero
        let arrived = await TryItWatch.textArrived(contains: { false }, settled: { false }, sleep: { elapsed += $0 })
        XCTAssertFalse(arrived)
        XCTAssertGreaterThanOrEqual(elapsed, TryItWatch.cap)
    }

    // MARK: Decisions

    func testRoutingDecisions() {
        // Outside Try it nothing changes.
        XCTAssertEqual(TryItRouting.action(tryItOpen: false, vypoFrontmost: false, fieldFocused: false), .proceed)
        XCTAssertEqual(TryItRouting.action(tryItOpen: true, vypoFrontmost: true, fieldFocused: true), .proceed)
        XCTAssertEqual(TryItRouting.action(tryItOpen: true, vypoFrontmost: false, fieldFocused: false), .bringForward)
        XCTAssertEqual(TryItRouting.action(tryItOpen: true, vypoFrontmost: false, fieldFocused: true), .bringForward)
        XCTAssertEqual(TryItRouting.action(tryItOpen: true, vypoFrontmost: true, fieldFocused: false), .bringForward)
        XCTAssertEqual(TryItRouting.route(reachedFront: true), .broughtForward)
        XCTAssertEqual(TryItRouting.route(reachedFront: false), .refused)
    }

    /// A gate with a fake window: `activation` decides whether bringing it forward works.
    private func gate(open: Bool = true, front: TryItGate.Front, activation: Bool, app: String = "com.apple.systempreferences")
        -> (TryItGate, () -> Int) {
        var current = front
        var calls = 0
        let g = TryItGate()
        g.isOpen = { open }
        g.front = { current }
        g.bringForward = { calls += 1; if activation { current = .init(vypoFrontmost: true, fieldFocused: true) } }
        g.frontBundleID = { current.vypoFrontmost ? "com.wilhelmtells.vypo.testapp" : app }
        g.sleep = { _ in }
        return (g, { calls })
    }

    func testKeyPressWithAnotherAppInFrontBringsVypoForward() {
        let (g, calls) = gate(front: .init(vypoFrontmost: false, fieldFocused: false), activation: true)
        g.keyPressed()
        XCTAssertEqual(calls(), 1)
        XCTAssertEqual(g.trace.frontAtKeyPress, "com.apple.systempreferences")
        XCTAssertTrue(g.trace.broughtForward)
    }

    func testKeyPressWithTheFieldFocusedLeavesEverythingAlone() {
        let (g, calls) = gate(front: .init(vypoFrontmost: true, fieldFocused: true), activation: true)
        g.keyPressed()
        XCTAssertEqual(calls(), 0)
        XCTAssertFalse(g.trace.broughtForward)
    }

    func testPasteTimeBringsVypoForwardFirstThenPastesNormally() async {
        let (g, calls) = gate(front: .init(vypoFrontmost: false, fieldFocused: false), activation: true)
        let route = await g.beforePaste()
        XCTAssertEqual(route, .broughtForward)
        XCTAssertEqual(calls(), 1)
        XCTAssertEqual(g.trace.frontAtPaste, "com.apple.systempreferences")
    }

    func testPasteTimeWithVypoInFrontJustPastes() async {
        let (g, calls) = gate(front: .init(vypoFrontmost: true, fieldFocused: true), activation: true)
        let route = await g.beforePaste()
        XCTAssertEqual(route, .normal)
        XCTAssertEqual(calls(), 0)
    }

    func testRefusedActivationMeansNoPasteAtAll() async {
        let (g, calls) = gate(front: .init(vypoFrontmost: false, fieldFocused: false), activation: false)
        let route = await g.beforePaste()
        // `.refused` is what stops the coordinator before the ⌘V: it keeps the text on the clipboard and
        // reports `.anotherWindowInFront`, which the step turns into the line "Another window was in front".
        XCTAssertEqual(route, .refused)
        XCTAssertEqual(calls(), 1)
        let mapped = TryItState.outcome(for: .anotherWindowInFront("Hi"), accessibilityTrusted: true) { _ in false }
        XCTAssertEqual(mapped, .anotherWindowInFront(heard: "Hi"))
    }

    func testOutsideTryItTheGateNeverTouchesAnything() async {
        let (g, calls) = gate(open: false, front: .init(vypoFrontmost: false, fieldFocused: false), activation: false)
        g.keyPressed()
        let route = await g.beforePaste()
        XCTAssertEqual(route, .normal)
        XCTAssertEqual(calls(), 0)
    }

    // MARK: Retry of the ⌘V (Try it only)

    private func retry(open: Bool = true, retried: Bool = false, since: Duration = .seconds(1), read: Bool = false,
                       front: Bool = true, focused: Bool = true, ours: Bool = true) -> Bool {
        TryItRouting.shouldRetryPaste(tryItOpen: open, alreadyRetried: retried, sincePaste: since, wasRead: read,
                                      vypoFrontmost: front, fieldFocused: focused, clipboardStillOurs: ours)
    }

    func testRetryHappensWhenTheItemIsStillUnreadAfterASecond() {
        XCTAssertTrue(retry())
        XCTAssertTrue(retry(since: .seconds(2)))
    }

    func testNoRetryOutsideTryItOrTooEarlyOrAfterARead() {
        XCTAssertFalse(retry(open: false))
        XCTAssertFalse(retry(since: .milliseconds(999)))
        XCTAssertFalse(retry(read: true))
    }

    func testNoRetryWhenVypoOrTheFieldIsNotInFrontOrTheClipboardMovedOn() {
        XCTAssertFalse(retry(front: false))
        XCTAssertFalse(retry(focused: false))
        XCTAssertFalse(retry(ours: false))
    }

    func testTheRetryHappensExactlyOnce() {
        XCTAssertFalse(retry(retried: true))
    }

    func testRestorerRepastesOnceAndRestartsItsTimeout() async {
        let pb = NSPasteboard(name: NSPasteboard.Name("vypo.test.retry.\(UUID().uuidString)"))
        let policy = RestorePolicy(afterPaste: .milliseconds(10), afterRead: .milliseconds(10), timeout: .milliseconds(300), fallback: .milliseconds(10))
        let restorer = ClipboardRestorer(text: "Hi", saved: Paster.snapshot(pb), pasteboard: pb, policy: policy)
        restorer.pasted()
        var posts = 0
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(restorer.repaste { posts += 1 })
        XCTAssertFalse(restorer.repaste { posts += 1 })
        XCTAssertEqual(posts, 1)
        // The original timeout (300 ms after the first paste) has passed, the new one (from the retry) has not.
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(restorer.finishReason)
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(restorer.finishReason, .timeout)
    }
}
