import AppKit

/// Where a dictation goes while the onboarding's Try it step is open (0.4.1). Its dictation belongs to the
/// onboarding field: it never pastes into another app. These are the decisions, without any AppKit.
enum TryItRouting {
    enum Action: Equatable { case proceed, bringForward }

    /// At key press and again at paste time: vypo must be in front with the field focused, or it is brought there.
    /// Outside the Try it step nothing changes.
    static func action(tryItOpen: Bool, vypoFrontmost: Bool, fieldFocused: Bool) -> Action {
        guard tryItOpen else { return .proceed }
        return vypoFrontmost && fieldFocused ? .proceed : .bringForward
    }

    enum Route: Equatable {
        /// Paste the normal way.
        case normal
        /// Vypo was behind another window and is in front now; paste the normal way.
        case broughtForward
        /// vypo could not get to the front: no ⌘V, the text stays on the clipboard.
        case refused
    }

    /// After the window was asked to come forward: did it arrive?
    static func route(reachedFront: Bool) -> Route { reachedFront ? .broughtForward : .refused }

    /// Try it only: how long a paste may stay unread before the ⌘V is sent once more.
    static let retryAfter: Duration = .seconds(1)

    /// Whether to post the ⌘V a second time (exactly once, only in Try it): the field has not read the pasted item
    /// after `retryAfter`, vypo is in front with the field focused, and our item is still on the pasteboard.
    static func shouldRetryPaste(tryItOpen: Bool, alreadyRetried: Bool, sincePaste: Duration, wasRead: Bool,
                                 vypoFrontmost: Bool, fieldFocused: Bool, clipboardStillOurs: Bool) -> Bool {
        tryItOpen && !alreadyRetried && !wasRead && sincePaste >= retryAfter
            && vypoFrontmost && fieldFocused && clipboardStillOurs
    }

    /// What a check waits for before it gives up on the window coming forward.
    static let activationWait: Duration = .milliseconds(600)
    static let activationStep: Duration = .milliseconds(25)
}

/// The window facts and actions the gate needs; the coordinator supplies the real ones, tests fake ones.
@MainActor
final class TryItGate {
    struct Front: Equatable {
        /// vypo is the active app and the onboarding window is key.
        var vypoFrontmost: Bool
        var fieldFocused: Bool
    }

    /// What the log says about one dictation, without any dictated text.
    struct Trace: Equatable {
        var frontAtKeyPress = "none"
        var frontAtPaste = "none"
        var broughtForward = false
        var retried = false
        var route: TryItRouting.Route = .normal
    }

    var isOpen: () -> Bool = { false }
    var front: () -> Front = { Front(vypoFrontmost: false, fieldFocused: false) }
    var bringForward: () -> Void = {}
    var frontBundleID: () -> String = { Paster.frontBundleID() }
    var sleep: (Duration) async -> Void = { try? await Task.sleep(for: $0) }

    private(set) var trace = Trace()

    /// The dictation key went down: if another app is in front, bring vypo forward now and record as usual.
    func keyPressed() {
        trace = Trace(frontAtKeyPress: frontBundleID())
        guard isOpen() else { return }
        let state = front()
        if TryItRouting.action(tryItOpen: true, vypoFrontmost: state.vypoFrontmost, fieldFocused: state.fieldFocused) == .bringForward {
            trace.broughtForward = true
            bringForward()
        }
    }

    /// Right before the paste. `.refused` means: do not post ⌘V anywhere.
    func beforePaste() async -> TryItRouting.Route {
        trace.frontAtPaste = frontBundleID()
        guard isOpen() else { return .normal }
        func needsFront() -> Bool {
            let state = front()
            return TryItRouting.action(tryItOpen: true, vypoFrontmost: state.vypoFrontmost, fieldFocused: state.fieldFocused) == .bringForward
        }
        guard needsFront() else { trace.route = .normal; return .normal }
        trace.broughtForward = true
        bringForward()
        var waited = Duration.zero
        while needsFront() && waited < TryItRouting.activationWait {
            await sleep(TryItRouting.activationStep)
            waited += TryItRouting.activationStep
        }
        let route = TryItRouting.route(reachedFront: !needsFront())
        trace.route = route
        return route
    }
}

extension TryItGate {
    /// One second after the paste: if the field has not read it yet, send the ⌘V once more (see `TryItRouting.shouldRetryPaste`).
    /// Returns whether it was sent.
    func retryPasteIfUnread(_ restorer: ClipboardRestorer, post: () -> Void) -> Bool {
        let state = front()
        guard TryItRouting.shouldRetryPaste(tryItOpen: isOpen(), alreadyRetried: restorer.retriedAt != nil,
                                            sincePaste: restorer.sincePaste, wasRead: restorer.wasRead,
                                            vypoFrontmost: state.vypoFrontmost, fieldFocused: state.fieldFocused,
                                            clipboardStillOurs: restorer.stillOurs) else { return false }
        return restorer.repaste(post: post)
    }
}
