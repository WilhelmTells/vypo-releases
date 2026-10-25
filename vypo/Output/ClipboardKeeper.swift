import AppKit
import Carbon.HIToolbox

/// A dictation that found no text field stays on the clipboard until you paste it once yourself
/// with ⌘V; shortly after, what was on the clipboard before comes back (§12). Only with
/// “Restore clipboard”; without it the dictation simply stays.
@MainActor
final class ClipboardKeeper {
    private let pasteboard: NSPasteboard
    private let policy: RestorePolicy
    /// The dictation on the clipboard, with the clipboard from before.
    private var pending: ClipboardRestorer?

    init(pasteboard: NSPasteboard = .general, policy: RestorePolicy = .standard) {
        self.pasteboard = pasteboard
        self.policy = policy
    }

    var policyForTests: RestorePolicy { policy }
    var isHolding: Bool { pending != nil }

    /// Puts `text` on the clipboard, and with `paste` presses ⌘V too (Accessibility may be wrong).
    /// Without “Restore clipboard” the dictation is plain text that simply stays.
    func keep(_ text: String, restoreAfterPaste: Bool, paste: Bool) {
        // A dictation still waiting keeps the clipboard from before the first one.
        let saved = pending.flatMap { $0.stillOurs ? $0.saved : nil } ?? Paster.snapshot(pasteboard)
        pending?.abandon()
        pending = nil
        if restoreAfterPaste {
            pending = ClipboardRestorer(text: text, saved: saved, pasteboard: pasteboard, policy: policy)
        } else {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
        // Not armed: this ⌘V is vypo's, the restore is timed from yours.
        if paste { Paster.postKey(kVK_ANSI_V, flags: .maskCommand) }
    }

    /// Before the next dictation is pasted or copied: the clipboard from before comes back now,
    /// unless something else was copied in the meantime.
    func settle() {
        guard let pending else { return }
        self.pending = nil
        pending.settle()
    }

    /// You pressed ⌘V: once the app has read the dictation, the clipboard from before comes back.
    /// A read that already happened (vypo's own ⌘V, a clipboard manager) can't be told from yours, so then
    /// the fixed fallback wait applies.
    func userPasted() {
        guard let pending, !pending.isWaiting else { return }
        guard pending.stillOurs else {
            self.pending = nil
            pending.settle()
            return
        }
        pending.pasted { [weak self] in
            if self?.pending === pending { self?.pending = nil }
        }
    }
}
