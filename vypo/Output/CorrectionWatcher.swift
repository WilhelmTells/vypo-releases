import ApplicationServices
import Foundation

/// Follows pasted text in the one field it went into, for a limited time, on a thread of its own: all Accessibility
/// calls happen there, so a slow app can never hold up the pill, the paste or the next dictation. Between changes of
/// the field it costs nothing, and no polling happens. Only the latest paste per app is watched.
///
/// Called “observed” in the log: the app gave us the field and tells us when it changes.
final class CorrectionWatcher: @unchecked Sendable {
    struct Request: Sendable {
        var pasted: String
        var pid: pid_t
        var bundleID: String?
        var language: Lang
        var continuesSentence: Bool
    }

    enum End: String, Sendable {
        case timeUp = "time up"
        case segmentLost = "segment lost"
        case otherField = "other field"
        case fieldGone = "field gone"
        case newDictation = "new dictation"
        case noField = "no text field"
        case tooLong = "field too long"
        case notObservable = "can't be observed"
        case notFound = "paste not found"
    }

    struct Result: Sendable {
        var request: Request
        var observed: Bool
        /// The latest version of the paste; nil if it was never found in the field, or the last one can't be trusted.
        var latest: String?
        /// The paste could still be followed when the watch ended (time up, other field, new dictation).
        var foundAtEnd: Bool
        var end: End
    }

    /// How long a paste is watched.
    static let timeLimit: TimeInterval = 120
    /// The paste can take a moment to arrive in the field.
    private static let attempts = 5
    private static let attemptInterval: TimeInterval = 0.15
    private static let messagingTimeout: Float = 0.1
    /// Above this many UTF-16 units a field isn't watched: every change would mean reading all of it.
    private static let maxFieldLength = 1_000_000
    /// Focus that moves this soon after a change may have cut a word in half: VS Code moves it while you type (measured,
    /// “Kubernet”). Such a version is dropped; a missed correction is fine, a wrong suggestion is not.
    private static let settleTime: TimeInterval = 1

    private let onFinish: @Sendable (Result) -> Void
    private var runLoop: CFRunLoop?
    /// Only touched on the watcher's thread.
    private var watches: [pid_t: Watch] = [:]

    init(onFinish: @escaping @Sendable (Result) -> Void) {
        self.onFinish = onFinish
    }

    func start(_ request: Request) {
        perform { [self] in
            if let old = watches[request.pid] { finish(old, .newDictation) }
            let watch = Watch(request: request, owner: self)
            watches[request.pid] = watch
            attach(watch, attempt: 1)
        }
    }

    /// Stops every watch; nothing is reported.
    func stopAll() {
        perform { [self] in
            for watch in watches.values { watch.tearDown() }
            watches = [:]
        }
    }

    private func perform(_ block: @escaping () -> Void) {
        let loop = startedRunLoop()
        CFRunLoopPerformBlock(loop, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(loop)
    }

    /// The thread starts with the first paste and then sleeps until something happens. Called on the main thread only.
    private func startedRunLoop() -> CFRunLoop {
        if let runLoop { return runLoop }
        let ready = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var started: CFRunLoop?
        let thread = Thread {
            started = CFRunLoopGetCurrent()
            // A run loop without a source would return at once.
            let keepAlive = CFRunLoopTimerCreateWithHandler(nil, .greatestFiniteMagnitude, 0, 0, 0) { _ in }
            CFRunLoopAddTimer(CFRunLoopGetCurrent(), keepAlive, .defaultMode)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "vypo corrections"
        thread.qualityOfService = .utility
        thread.start()
        ready.wait()
        runLoop = started
        return started!
    }

    // MARK: On the watcher's thread

    private func attach(_ watch: Watch, attempt: Int) {
        func retry(_ end: End) {
            guard attempt < Self.attempts else { return finish(watch, end) }
            watch.after(Self.attemptInterval) { [self] in attach(watch, attempt: attempt + 1) }
        }
        guard let field = FocusedField(pid: watch.request.pid, bundleID: watch.request.bundleID) else { return retry(.noField) }
        if field.isTooLong(than: Self.maxFieldLength) { return finish(watch, .tooLong) }
        guard case .text(let value) = field.read() else { return retry(.noField) }
        guard let segment = TrackedSegment(pasted: watch.request.pasted, in: value, caret: field.caret()) else { return retry(.notFound) }
        watch.segment = segment
        watch.field = field
        guard watch.observe() else { return finish(watch, .notObservable) }
        watch.after(Self.timeLimit) { [self] in finish(watch, .timeUp) }
    }

    fileprivate func fieldChanged(_ watch: Watch) {
        guard let field = watch.field, watch.segment != nil else { return }
        switch field.read() {
        case .gone: finish(watch, .fieldGone)
        case .busy: break
        case .text(let value):
            watch.lastChange = CFAbsoluteTimeGetCurrent()
            if watch.segment?.update(value) == false { finish(watch, .segmentLost) }
        }
    }

    fileprivate func focusChanged(_ watch: Watch) {
        guard let field = watch.field, let now = FocusedField(pid: watch.request.pid, bundleID: nil, anyRole: true) else { return }
        guard !CFEqual(now.element, field.element) else { return }
        if CFAbsoluteTimeGetCurrent() - watch.lastChange < Self.settleTime { watch.segment = nil }
        finish(watch, .otherField)
    }

    fileprivate func elementDestroyed(_ watch: Watch) { finish(watch, .fieldGone) }

    private func finish(_ watch: Watch, _ end: End) {
        guard watches[watch.request.pid] === watch else { return }
        watches[watch.request.pid] = nil
        let observed = watch.isObserving
        watch.tearDown()
        let stillThere = end == .timeUp || end == .otherField || end == .newDictation
        onFinish(Result(request: watch.request, observed: observed, latest: watch.segment?.text,
                        foundAtEnd: observed && stillThere, end: end))
    }
}

/// One watched paste.
private final class Watch {
    let request: CorrectionWatcher.Request
    weak var owner: CorrectionWatcher?
    var field: FocusedField?
    var segment: TrackedSegment?
    var lastChange: CFAbsoluteTime = 0
    private var observer: AXObserver?
    private var timers: [CFRunLoopTimer] = []

    var isObserving: Bool { observer != nil }

    init(request: CorrectionWatcher.Request, owner: CorrectionWatcher) {
        self.request = request
        self.owner = owner
    }

    func observe() -> Bool {
        guard let field else { return false }
        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, name, refcon in
            guard let refcon else { return }
            let watch = Unmanaged<Watch>.fromOpaque(refcon).takeUnretainedValue()
            switch name as String {
            case kAXValueChangedNotification: watch.owner?.fieldChanged(watch)
            case kAXFocusedUIElementChangedNotification: watch.owner?.focusChanged(watch)
            default: watch.owner?.elementDestroyed(watch)
            }
        }
        guard AXObserverCreate(request.pid, callback, &created) == .success, let created else { return false }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard AXObserverAddNotification(created, field.element, kAXValueChangedNotification as CFString, refcon) == .success else { return false }
        AXObserverAddNotification(created, field.element, kAXUIElementDestroyedNotification as CFString, refcon)
        AXObserverAddNotification(created, AXUIElementCreateApplication(request.pid), kAXFocusedUIElementChangedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
        return true
    }

    func after(_ seconds: TimeInterval, _ body: @escaping () -> Void) {
        let timer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent() + seconds, 0, 0, 0) { _ in body() }
        timers.append(timer!)
        CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, .defaultMode)
    }

    func tearDown() {
        for timer in timers { CFRunLoopTimerInvalidate(timer) }
        timers = []
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
    }
}

/// The app's focused element, if it is a field vypo may read.
private struct FocusedField {
    enum Reading {
        case text(String)
        /// The app didn't answer this time.
        case busy
        case gone
    }

    let element: AXUIElement
    /// Mail's message body is a web area: its text comes through text markers, not `AXValue`.
    private let readsMarkers: Bool

    private static let mailBundleID = "com.apple.mail"

    /// A secure field is never read. A web area can be a whole page with everything on it (one chat app's window was 11 000
    /// characters, measured), so only Mail's counts, where that element is the message itself.
    init?(pid: pid_t, bundleID: String?, anyRole: Bool = false) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        element = ref as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.1)
        let role = Self.string(element, kAXRoleAttribute)
        let isMailBody = role == "AXWebArea" && bundleID == Self.mailBundleID
        readsMarkers = isMailBody
        guard anyRole || isMailBody || (role.map(TextFieldProbe.textRoles.contains) == true
                                        && Self.string(element, kAXSubroleAttribute) != kAXSecureTextFieldSubrole) else { return nil }
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success ? ref as? String : nil
    }

    func isTooLong(than limit: Int) -> Bool {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString, &ref) == .success else { return false }
        return (ref as? Int ?? 0) > limit
    }

    func caret() -> Int? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        return AXValueGetValue(ref as! AXValue, .cfRange, &range) ? range.location + range.length : nil
    }

    func read() -> Reading {
        var ref: CFTypeRef?
        if readsMarkers {
            var range: CFTypeRef?
            let first = AXUIElementCopyParameterizedAttributeValue(element, "AXTextMarkerRangeForUIElement" as CFString, element, &range)
            guard first == .success, let range else { return Self.reading(first) }
            let second = AXUIElementCopyParameterizedAttributeValue(element, "AXStringForTextMarkerRange" as CFString, range, &ref)
            return second == .success ? (ref as? String).map(Reading.text) ?? .busy : Self.reading(second)
        }
        let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &ref)
        return result == .success ? (ref as? String).map(Reading.text) ?? .busy : Self.reading(result)
    }

    private static func reading(_ error: AXError) -> Reading { error == .invalidUIElement ? .gone : .busy }
}
