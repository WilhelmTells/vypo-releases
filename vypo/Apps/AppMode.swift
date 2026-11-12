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

    /// What the mode does and where it fits, for Settings → Apps. With Spoken characters a mode only names what is its own;
    /// `legacy` still has spoken punctuation in Writing and “Prompt apps only”.
    func explanation(_ layout: WordsLayout) -> String {
        switch self {
        case .standard: String(localized: "Everything you set in Words, nothing extra. Apps you haven’t added work like this too.")
        case .prompt where layout == .spokenCharacters:
            String(localized: "For AI chats, terminals and code editors: no final period unless you say it, and it can send automatically.")
        case .prompt: String(localized: "For AI chats, terminals and code editors: no final period, so you can keep typing; can send automatically. Replacements set to “Prompt apps only” work in a sentence here.")
        case .writing where layout == .spokenCharacters:
            String(localized: "For documents and notes: typographic quotes, numbered lists, and a capital letter after every line break.")
        case .writing: String(localized: "For documents and notes: say “comma” or “new paragraph”, and quotes become typographic.")
        case .excluded: String(localized: "vypo doesn’t dictate here, e.g. in apps with confidential content.")
        }
    }
}
