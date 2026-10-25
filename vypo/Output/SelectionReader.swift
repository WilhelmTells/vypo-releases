import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Reads the selected text in the focused app (§11.6).
@MainActor
enum SelectionReader {
    static let maxLength = 60

    /// AX selected text, else ⌘C through the pasteboard; first 60 characters, trimmed.
    static func selectedText() async -> String {
        var text = axSelectedText() ?? ""
        if text.isEmpty { text = await copySelection() ?? "" }
        return String(text.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return (ref as! AXUIElement)
    }

    static func axSelectedText() -> String? {
        guard let element = focusedElement() else { return nil }
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    /// Saves the pasteboard, posts ⌘C, waits 120 ms, reads the string, restores the pasteboard.
    private static func copySelection() async -> String? {
        let pb = NSPasteboard.general
        let saved = Paster.snapshot(pb)
        let before = pb.changeCount
        Paster.postKey(kVK_ANSI_C, flags: .maskCommand)
        try? await Task.sleep(for: .milliseconds(120))
        let copied = pb.changeCount != before ? pb.string(forType: .string) : nil
        if pb.changeCount != before { Paster.restore(saved, pb) }
        return copied
    }
}

/// Reads the text around the insertion point via Accessibility (§23.1). Callable off the main
/// thread, so a slow app (Electron) doesn't hold up the pill.
enum ContextReader {
    static func insertionContext() -> InsertionContext? {
        guard let element = SelectionReader.focusedElement() else { return nil }
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &range) else { return nil }

        var countRef: CFTypeRef?
        let count = AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString, &countRef) == .success
            ? (countRef as? Int) : nil

        let start = max(0, range.location - 2)
        let length = range.location - start
        var before = ""
        if length > 0 {
            guard let s = string(element, CFRange(location: start, length: length)) else { return nil }
            before = s
        }
        var after: Character?
        let afterLocation = range.location + range.length
        if count == nil || afterLocation < count! {
            after = string(element, CFRange(location: afterLocation, length: 1))?.first
        }
        return InsertionContext(before: before, after: after)
    }

    static func string(_ element: AXUIElement, _ range: CFRange) -> String? {
        var r = range
        guard let value = AXValueCreate(.cfRange, &r) else { return nil }
        var out: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, value, &out) == .success else { return nil }
        return out as? String
    }
}
