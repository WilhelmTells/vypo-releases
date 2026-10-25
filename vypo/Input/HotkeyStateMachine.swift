import Foundation

/// The dictation-key gesture recognizer (§7.2), driven by timestamps so it can be unit-tested.
///
/// The driver feeds key presses, releases, other key-downs and timer ticks, and schedules a tick
/// at `deadline` whenever it is set.
struct HotkeyStateMachine: Sendable {
    static let holdThreshold: TimeInterval = 0.2
    static let doubleTapWindow: TimeInterval = 0.35
    /// Tolerance for timestamp arithmetic (1.2 − 1.0 < 0.2 in floating point).
    private static let epsilon: TimeInterval = 1e-9

    enum Effect: Equatable, Sendable {
        case startPushToTalk, stopPushToTalk, cancelPushToTalk
        case startHandsFree, stopHandsFree
        /// A press that may become a recording: start capturing now, so the 200 ms before
        /// `startPushToTalk` aren't lost. Only with `preRoll`.
        case prepare
        /// The press didn't become a recording; drop what `prepare` captured.
        case discardPrepared
    }

    enum State: Equatable, Sendable {
        case idle
        /// First press, not yet 200 ms.
        case firstDown(at: TimeInterval)
        /// Short tap released, waiting up to 350 ms for the second press.
        case awaitingSecond(releasedAt: TimeInterval)
        /// Second press of a possible double-tap.
        case secondDown(at: TimeInterval)
        case pushToTalk
        case handsFree
        /// A press while hands-free is running.
        case handsFreeDown(at: TimeInterval, cancelled: Bool)
        /// The press was cancelled or does nothing; wait for the release.
        case ignoringUntilRelease
    }

    var holdToTalk: Bool
    var doubleTapHandsFree: Bool
    /// Emit `prepare` and `discardPrepared`.
    var preRoll: Bool
    private(set) var state: State = .idle

    init(holdToTalk: Bool = true, doubleTapHandsFree: Bool = true, preRoll: Bool = false) {
        self.holdToTalk = holdToTalk
        self.doubleTapHandsFree = doubleTapHandsFree
        self.preRoll = preRoll
    }

    /// When the driver must call `tick(at:)`.
    var deadline: TimeInterval? {
        switch state {
        case .firstDown(let t), .secondDown(let t): t + Self.holdThreshold
        case .awaitingSecond(let r): r + Self.doubleTapWindow
        default: nil
        }
    }

    mutating func keyDown(at t: TimeInterval) -> [Effect] {
        var effects = tick(at: t)
        switch state {
        case .idle:
            state = .firstDown(at: t)
        case .awaitingSecond(let r):
            state = t - r < Self.doubleTapWindow - Self.epsilon ? .secondDown(at: t) : .firstDown(at: t)
        case .handsFree:
            state = .handsFreeDown(at: t, cancelled: false)
        default:
            break
        }
        // A first press records only if it's held; a second one always leads somewhere.
        switch state {
        case .firstDown where preRoll && holdToTalk, .secondDown where preRoll:
            effects.append(.prepare)
        default:
            break
        }
        return effects
    }

    mutating func keyUp(at t: TimeInterval) -> [Effect] {
        var effects = tick(at: t)
        switch state {
        case .firstDown:
            state = doubleTapHandsFree ? .awaitingSecond(releasedAt: t) : .idle
            if preRoll { effects.append(.discardPrepared) }
        case .secondDown:
            state = .handsFree
            effects.append(.startHandsFree)
        case .pushToTalk:
            state = .idle
            effects.append(.stopPushToTalk)
        case .handsFreeDown(let t0, let cancelled):
            if !cancelled && t - t0 < Self.holdThreshold - Self.epsilon {
                state = .idle
                effects.append(.stopHandsFree)
            } else {
                state = .handsFree
            }
        case .ignoringUntilRelease:
            state = .idle
        default:
            break
        }
        return effects
    }

    /// Any key-down while the dictation key is held cancels the press (§7.2).
    mutating func otherKey(at t: TimeInterval) -> [Effect] {
        var effects = tick(at: t)
        switch state {
        case .firstDown, .secondDown:
            state = .ignoringUntilRelease
            if preRoll { effects.append(.discardPrepared) }
        case .pushToTalk:
            state = .ignoringUntilRelease
            effects.append(.cancelPushToTalk)
        case .handsFreeDown(let t0, _):
            state = .handsFreeDown(at: t0, cancelled: true)
        default:
            break
        }
        return effects
    }

    mutating func tick(at t: TimeInterval) -> [Effect] {
        switch state {
        case .firstDown(let t0), .secondDown(let t0):
            guard t - t0 >= Self.holdThreshold - Self.epsilon else { return [] }
            if holdToTalk {
                state = .pushToTalk
                return [.startPushToTalk]
            }
            state = .ignoringUntilRelease
            if preRoll { return [.discardPrepared] }
        case .awaitingSecond(let r):
            if t - r >= Self.doubleTapWindow - Self.epsilon { state = .idle }
        default:
            break
        }
        return []
    }

    /// After a recording ended from outside (stop button, Esc, time limit, error).
    mutating func reset(keyIsDown: Bool = false) {
        state = keyIsDown ? .ignoringUntilRelease : .idle
    }
}
