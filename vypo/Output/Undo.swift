import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// The last pasted dictation (§23.4).
struct LastInsertion: Equatable, Sendable {
    var text: String
    var pid: pid_t?
    var date: Date
    var language: Lang
    var historyID: UUID?
    var words: Int = 0
    var recordingSeconds: TimeInterval = 0
    var bundleID: String?
}

/// Keeps the last insertion and its recording in RAM only, for 5 minutes (§23.4).
@MainActor
final class DictationMemory {
    static let lifetime: TimeInterval = 300

    private(set) var last: LastInsertion?
    /// The last recording's samples. Never written to disk.
    private(set) var samples: [Float]?
    private var samplesDate: Date?

    func recordingStarted() {
        samples = nil
        samplesDate = nil
    }

    func store(samples: [Float], at date: Date = Date()) {
        self.samples = samples
        samplesDate = date
    }

    func store(_ insertion: LastInsertion) {
        last = insertion
    }

    /// Clears what is older than 5 minutes.
    func expire(now: Date = Date()) {
        if let d = samplesDate, now.timeIntervalSince(d) >= Self.lifetime {
            samples = nil
            samplesDate = nil
        }
        if let l = last, now.timeIntervalSince(l.date) >= Self.lifetime {
            last = nil
        }
    }

    /// After an undo, the insertion is gone; the samples stay for Debug → Save last recording.
    func forgetLast() {
        last = nil
    }

    /// System sleep and quit.
    func clear() {
        samples = nil
        samplesDate = nil
        last = nil
    }

    /// The insertion that undo may act on: within 5 minutes and in the same app.
    func usable(frontPID: pid_t?, now: Date = Date()) -> LastInsertion? {
        expire(now: now)
        guard let last, last.pid == nil || last.pid == frontPID else { return nil }
        return last
    }
}

/// Access to the focused text, mocked in tests.
@MainActor
protocol InsertionAccess {
    /// The selected range in the focused element (UTF-16 units).
    func selectedRange() -> NSRange?
    func text(in range: NSRange) -> String?
    func select(_ range: NSRange) -> Bool
    func pressDelete()
    func pressUndo()
}

@MainActor
enum UndoPerformer {
    enum Action: Equatable {
        case deletedRange(NSRange)
        case commandZ
    }

    /// Deletes the inserted text if it's right before the cursor, else sends ⌘Z once.
    @discardableResult
    static func undo(_ inserted: String, access: InsertionAccess) -> Action {
        let length = (inserted as NSString).length
        if length > 0, let sel = access.selectedRange(), sel.length == 0, sel.location >= length {
            let range = NSRange(location: sel.location - length, length: length)
            if access.text(in: range) == inserted, access.select(range) {
                access.pressDelete()
                return .deletedRange(range)
            }
        }
        access.pressUndo()
        return .commandZ
    }
}

/// The real Accessibility implementation.
@MainActor
struct AXInsertionAccess: InsertionAccess {
    let element: AXUIElement?

    init() { element = SelectionReader.focusedElement() }

    func selectedRange() -> NSRange? {
        guard let element else { return nil }
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(ref as! AXValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    func text(in range: NSRange) -> String? {
        guard let element else { return nil }
        return ContextReader.string(element, CFRange(location: range.location, length: range.length))
    }

    func select(_ range: NSRange) -> Bool {
        guard let element else { return false }
        var r = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &r) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success
    }

    func pressDelete() { Paster.postKey(kVK_Delete) }
    func pressUndo() { Paster.postKey(kVK_ANSI_Z, flags: .maskCommand) }
}
