import Foundation

/// How vypo behaves in an app (§23.5).
enum AppMode: String, Codable, CaseIterable, Sendable {
    case standard = "default"
    case prompt
    case writing
    case excluded

    var title: String {
        switch self {
        case .standard: String(localized: "Default")
        case .prompt: String(localized: "Prompt")
        case .writing: String(localized: "Writing")
        case .excluded: String(localized: "Off")
        }
    }

    var symbol: String {
        switch self {
        case .standard: "text.cursor"
        case .prompt: "terminal"
        case .writing: "doc.text"
        case .excluded: "nosign"
        }
    }

    /// What the mode does and where it fits, for Settings → Apps. Prompt points to where its characters are set.
    func explanation(_ layout: WordsLayout) -> String {
        switch self {
        case .standard: String(localized: "Plain dictation, as in every app you haven’t added.")
        case .prompt where layout == .spokenCharacters:
            String(localized: "For AI chats, terminals and code editors: no final period, so you can keep typing; can send automatically. Spoken characters set for Prompt, such as “slash”, work in a sentence here.")
        case .prompt: String(localized: "For AI chats, terminals and code editors: no final period, so you can keep typing; can send automatically. Replacements set to “Prompt apps only” work in a sentence here.")
        case .writing: String(localized: "For documents and notes: say “comma” or “new paragraph”, and quotes become typographic.")
        case .excluded: String(localized: "vypo doesn’t dictate here, e.g. in apps with confidential content.")
        }
    }
}
