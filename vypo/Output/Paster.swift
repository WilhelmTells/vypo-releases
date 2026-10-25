import AppKit
import Carbon.HIToolbox

/// Puts text where the cursor is: pasteboard + ⌘V, then restores the clipboard (§12).
@MainActor
enum Paster {
    /// A copy of every pasteboard item with all its types.
    struct Snapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]

        /// Whether a file was copied (in the Finder, say): the clipboard holds a file URL, not text.
        var hasFileURL: Bool { items.contains { $0.keys.contains(.fileURL) } }
    }

    /// The rest of the restore rules (earliest, after the read, timeout) are `RestorePolicy`. This one is the
    /// fallback when the read can't be seen: something read the promised item before the ⌘V, so the pasteboard
    /// answers the app from its own copy. 250 ms was too short for a busy app (the diagnosis of 2026-10-25).
    static let restoreDelay: Duration = RestorePolicy.standard.fallback

    /// The bundle ID of the frontmost app, for the log.
    static func frontBundleID() -> String {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "no app"
    }

    /// One notice line per restore or decision not to: why, when the app read the dictation, when the clipboard
    /// came back, in which app, and whether the clipboard from before was a file. No content.
    static func logRestore(restored: Bool, reason: RestorePolicy.Reason?, start: ContinuousClock.Instant,
                           firstRead: ContinuousClock.Instant?, readBeforePaste: Bool, app: String, snapshot: Snapshot) {
        let now = ContinuousClock.now
        let ms = (now - start).milliseconds
        let file = snapshot.hasFileURL ? "yes" : "no"
        let what: String
        switch (restored, reason) {
        case (false, _): what = "kept (changed by someone else) \(ms) ms after paste"
        case (true, .afterRead?):
            let read = firstRead.map { ($0 - start).milliseconds } ?? 0
            what = "restored after read (read \(read) ms after paste, restored \(ms) ms after paste)"
        case (true, .timeout?): what = "restored on timeout (never read) \(ms) ms after paste"
        case (true, .fallback?): what = "restored after the fallback wait (read before the paste) \(ms) ms after paste"
        case (true, nil):
            what = "restored early for the next dictation \(ms) ms after paste" + (readBeforePaste ? " (read before the paste)" : "")
        }
        Log.output.notice("Clipboard \(what, privacy: .public) in \(app, privacy: .public) (file URL before: \(file, privacy: .public))")
    }

    static func snapshot(_ pb: NSPasteboard = .general) -> Snapshot {
        let items = (pb.pasteboardItems ?? []).map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { dict[type] = data }
            }
            return dict
        }
        return Snapshot(items: items)
    }

    static func restore(_ snapshot: Snapshot, _ pb: NSPasteboard = .general) {
        pb.clearContents()
        let items = snapshot.items.map { dict in
            let item = NSPasteboardItem()
            for (type, data) in dict { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pb.writeObjects(items) }
    }

    static func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// Pastes `text` into the focused app. The dictation is a promised item, so vypo sees when the app reads it;
    /// the clipboard comes back shortly after that on its own, so the caller (and the pill) doesn't wait for it.
    /// Without “Restore clipboard” the text is simply copied.
    static func paste(_ text: String, restoreClipboard: Bool, policy: RestorePolicy = .standard) {
        let pb = NSPasteboard.general
        guard restoreClipboard else {
            copy(text)
            postKey(kVK_ANSI_V, flags: .maskCommand)
            return
        }
        let restorer = ClipboardRestorer(text: text, saved: snapshot(pb), pasteboard: pb, policy: policy)
        restorer.pasted()
        postKey(kVK_ANSI_V, flags: .maskCommand)
    }

    /// Marks vypo's own key presses, so the event tap can tell them from yours.
    nonisolated static let syntheticMarker: Int64 = 0x7679_706F

    /// Posts a key press to the HID event tap.
    static func postKey(_ keyCode: Int, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
        up?.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
