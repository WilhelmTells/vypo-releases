import ApplicationServices
import Synchronization

/// Whether the focused element takes text (§12). When it doesn't, the dictation is pasted anyway but
/// stays on the clipboard, and the pill says so.
enum TextFieldProbe {
    enum Focus: Equatable {
        /// Nothing has focus: the Desktop, Finder without a selection.
        case nothing
        case element(role: String?, hasSelectedRange: Bool, editable: Bool)
        /// The app didn't answer in time, or Accessibility failed.
        case unknown(AXError.RawValue)
    }

    static let textRoles: Set<String> = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole]

    /// No answer counts as a text field, so a slow app keeps today's behaviour.
    static func acceptsText(_ focus: Focus) -> Bool {
        switch focus {
        case .nothing: false
        case .unknown: true
        case let .element(role, hasSelectedRange, editable):
            role.map(textRoles.contains) == true || hasSelectedRange || editable
        }
    }

    enum Output: Equatable {
        /// ⌘V, then the clipboard comes back.
        case paste
        /// ⌘V, and the text stays on the clipboard.
        case pasteAndKeep
        /// No ⌘V, only the clipboard.
        case keep
    }

    /// Apps where ⌘V without a text field does something else: the Finder (and the Desktop) makes a file of the text.
    /// The Desktop reports a group with a selected text range, so there only a text role counts.
    static let keepOnlyApps: Set<String> = ["com.apple.finder"]

    static func output(for focus: Focus, app bundleID: String?) -> Output {
        guard bundleID.map(keepOnlyApps.contains) == true else { return acceptsText(focus) ? .paste : .pasteAndKeep }
        if case let .element(role?, _, _) = focus, textRoles.contains(role) { return .paste }
        return .keep
    }

    /// Electron and Chromium apps (Slack, VS Code, Discord) build their accessibility tree only when
    /// asked; until then they report no focused element and every dictation there looked like
    /// “not in a text field”. Asked once per process; other apps ignore the attribute.
    static func enableAccessibility(pid: pid_t) {
        guard askedPIDs.withLock({ $0.insert(pid).inserted }) else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        let result = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        Log.output.notice("AXManualAccessibility for pid \(pid): \(result == .success ? "on" : "error \(result.rawValue)", privacy: .public)")
    }

    private static let askedPIDs = Mutex<Set<pid_t>>([])

    /// Asks Accessibility, at most `timeout` seconds per call. Callable off the main thread.
    static func focus(timeout: Float = 0.1) -> Focus {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, timeout)
        var ref: CFTypeRef?
        switch AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &ref) {
        case .success: break
        case .noValue, .attributeUnsupported: return .nothing
        case let error: return .unknown(error.rawValue)
        }
        guard let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return .nothing }
        let element = ref as! AXUIElement
        AXUIElementSetMessagingTimeout(element, timeout)

        var roleRef: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        if roleResult == .cannotComplete { return .unknown(roleResult.rawValue) }
        var rangeRef: CFTypeRef?
        let hasRange = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success
        var settable: DarwinBoolean = false
        let editable = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success
            && settable.boolValue
        return .element(role: roleRef as? String, hasSelectedRange: hasRange, editable: editable)
    }
}
