import AppKit

/// Pill errors (§18, §23.11).
enum PillError: String, Equatable, Sendable, CaseIterable {
    case noMicrophone, micNotAllowed, noAccessibility, modelMissing, modelError, globeKeyInUse, secureInput
    case offInThisApp, noRecording, tooQuiet, notUnderstood

    var message: String {
        switch self {
        case .noMicrophone: String(localized: "No microphone")
        case .micNotAllowed: String(localized: "Mic not allowed")
        case .noAccessibility: String(localized: "No accessibility")
        case .modelMissing: String(localized: "Model missing")
        case .modelError: String(localized: "Model error")
        case .globeKeyInUse: String(localized: "Globe key in use")
        case .secureInput: String(localized: "Secure input on")
        case .offInThisApp: String(localized: "Off in this app")
        case .noRecording: String(localized: "No recording")
        case .tooQuiet: String(localized: "Too quiet")
        case .notUnderstood: String(localized: "Didn’t catch that")
        }
    }

    /// Permission errors stay until they're fixed; the rest time out.
    var isPersistent: Bool {
        switch self {
        case .micNotAllowed, .noAccessibility, .globeKeyInUse: true
        default: false
        }
    }

    var duration: TimeInterval { self == .offInThisApp ? 2 : 4 }
}

/// The short confirmation shown in the `added` state.
enum PillNotice: Equatable, Sendable {
    case termAdded(String)
    case copied
    /// Pasted where there was no text field: the text stays on the clipboard.
    case onClipboard
    case undone
    /// The language filter kept a transcript out of the field; it is in History.
    case savedToHistory
    /// “Copy Diagnostics…” is reading the log (a few seconds); “Copied” follows.
    case collectingDiagnostics
}

/// What the pill shows (§6.3).
enum PillMode: Equatable, Sendable {
    case collapsed
    case ready
    case listening
    case handsfree
    case processing
    case error(PillError)
    case add
    case added(PillNotice)

    var isRecording: Bool { self == .listening || self == .handsfree }

    var accessibilityLabel: String {
        switch self {
        case .collapsed: String(localized: "vypo idle")
        case .ready: String(localized: "Ready to dictate")
        case .listening: String(localized: "Listening")
        case .handsfree: String(localized: "Hands-free, listening")
        case .processing: String(localized: "Transcribing")
        case .error(let e): String(localized: "Error: \(e.message)")
        case .add: String(localized: "Add to glossary")
        case .added(.termAdded(let t)): String(localized: "\(t) added")
        case .added(.copied): String(localized: "Copied")
        case .added(.onClipboard): String(localized: "On clipboard")
        case .added(.undone): String(localized: "Undone")
        case .added(.savedToHistory): String(localized: "Saved to History")
        case .added(.collectingDiagnostics): String(localized: "Collecting diagnostics…")
        }
    }
}

/// Whether the floating pill shows a mode (§6.3). It never shows at rest. With the pill turned off
/// (Settings → Appearance → Pill), the menu bar mark is the signal; only states that need you still show.
enum PillVisibility {
    static func isVisible(_ mode: PillMode, showPill: Bool) -> Bool {
        guard mode != .ready && mode != .collapsed else { return false }
        return showPill || needsYou(mode)
    }

    /// Something to do or to know that the mark can't say: fix a permission or the setup, type a
    /// glossary term, or find the text on the clipboard after it couldn't be pasted.
    static func needsYou(_ mode: PillMode) -> Bool {
        switch mode {
        case .error(let e):
            switch e {
            case .micNotAllowed, .noAccessibility, .globeKeyInUse, .noMicrophone, .modelMissing: true
            case .modelError, .secureInput, .offInThisApp, .noRecording, .tooQuiet, .notUnderstood: false
            }
        // The user just asked for the diagnostics and waits a few seconds: shown even with the pill off.
        case .add, .added(.onClipboard), .added(.collectingDiagnostics): true
        case .collapsed, .ready, .listening, .handsfree, .processing, .added(.termAdded), .added(.copied), .added(.undone), .added(.savedToHistory): false
        }
    }
}

/// Fixed pill sizes and the measured sizes of auto-width states (§6.3). Listening and processing
/// share one size, so the pill never changes width when you let go.
enum PillMetrics {
    static let height: CGFloat = 34
    static let padding: CGFloat = 14
    static let gap: CGFloat = 8
    static let stopSize: CGFloat = 24
    /// Room around the pill inside its panel, for the shadow.
    static let margin: CGFloat = 12

    static var errorFont: NSFont { NSFont.systemFont(ofSize: 12, weight: .medium) }
    static var noticeFont: NSFont { NSFont.systemFont(ofSize: 12, weight: .regular) }
    static var noticeBoldFont: NSFont { NSFont.systemFont(ofSize: 12, weight: .semibold) }

    static func textWidth(_ s: String, _ font: NSFont) -> CGFloat {
        ceil((s as NSString).size(withAttributes: [.font: font]).width)
    }

    static func noticeWidth(_ notice: PillNotice) -> CGFloat {
        switch notice {
        case .termAdded(let term):
            // The translated sentence, with the term in bold.
            textWidth(term, noticeBoldFont)
                + textWidth(String(localized: "\(term) added").replacingOccurrences(of: term, with: ""), noticeFont)
        case .copied: textWidth(String(localized: "Copied"), noticeFont)
        case .onClipboard: textWidth(String(localized: "On clipboard"), noticeFont)
        case .undone: textWidth(String(localized: "Undone"), noticeFont)
        case .savedToHistory: textWidth(String(localized: "Saved to History"), noticeFont)
        case .collectingDiagnostics: textWidth(String(localized: "Collecting diagnostics…"), noticeFont)
        }
    }

    static func size(for mode: PillMode) -> CGSize {
        let bars = VoiceBars.width
        switch mode {
        case .collapsed, .ready:
            return CGSize(width: height, height: height)
        case .listening, .processing:
            return CGSize(width: padding + bars + padding, height: height)
        case .handsfree:
            return CGSize(width: padding + bars + gap + stopSize + 5, height: height)
        case .error(let e):
            return CGSize(width: padding + 14 + gap + textWidth(e.message, errorFont) + padding, height: height)
        case .add:
            return CGSize(width: 10 + 13 + 6 + 150 + 6 + 24 + 5, height: height)
        case .added(let notice):
            return CGSize(width: padding + 13 + 6 + noticeWidth(notice) + padding, height: height)
        }
    }
}
