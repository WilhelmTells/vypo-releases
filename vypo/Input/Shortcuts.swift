import KeyboardShortcuts

/// User-changeable shortcuts (§7.3, §23.4).
extension KeyboardShortcuts.Name {
    /// The dictation key when it's set to `DictationKey.custom`. vypo never registers it as a hotkey;
    /// `HotkeyMonitor` matches it in its event tap so hold and double-tap work as with single keys.
    static let dictation = Self("dictation", initial: .init(.d, modifiers: [.control, .option]))
    static let addToGlossary = Self("addToGlossary", initial: .init(.g, modifiers: [.control, .option]))
    static let copyLastDictation = Self("copyLastDictation", initial: .init(.v, modifiers: [.control, .option]))
    static let undoDictation = Self("undoDictation", initial: .init(.z, modifiers: [.control, .option]))
}

extension KeyboardShortcuts.Shortcut {
    /// Key cap glyphs, e.g. ["⌃", "⌥", "L"].
    @MainActor var keyCaps: [String] {
        let modifiers: Set<Character> = ["⌃", "⌥", "⇧", "⌘"]
        var caps: [String] = []
        var key = ""
        for ch in description {
            if modifiers.contains(ch) { caps.append(String(ch)) } else { key.append(ch) }
        }
        if !key.isEmpty { caps.append(key) }
        return caps
    }
}
