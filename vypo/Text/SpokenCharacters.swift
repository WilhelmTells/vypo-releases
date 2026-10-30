import Foundation
import Observation

/// Which Words page a Mac has, decided once at the first launch of 0.4.0 (`wordsLayout`).
/// `spokenCharacters`: a new installation. Every spoken character is an entry of Words → Spoken characters, and
/// Replacements starts empty. `legacy`: vypo ran here before. Replacements keeps its default entries and Writing apps
/// keep “Spoken punctuation”, exactly as in 0.3.0; nothing of theirs is moved or changed.
enum WordsLayout: String, Sendable {
    case spokenCharacters
    case legacy

    /// The stored verdict, or a new one: a Mac is new when `replacements.json` is missing (looked up on disk before
    /// `ReplacementStore` writes it; a broken file still counts as there), or when `spokenCharacters.json` exists, which
    /// only this layout writes. Stored at once and kept for good.
    static func resolve(store: Store, defaults: UserDefaults) -> WordsLayout {
        if let stored = defaults.string(forKey: DefaultsKey.wordsLayout).flatMap(WordsLayout.init(rawValue:)) { return stored }
        let files = FileManager.default
        let fresh = !files.fileExists(atPath: store.url(ReplacementStore.file).path)
            || files.fileExists(atPath: store.url(SpokenCharacterStore.file).path)
        let layout: WordsLayout = fresh ? .spokenCharacters : .legacy
        defaults.set(layout.rawValue, forKey: DefaultsKey.wordsLayout)
        Log.store.notice("Words layout: \(layout.rawValue, privacy: .public)")
        return layout
    }
}

/// A word you say for a character (Words → Spoken characters): its spellings, the character, on/off, and the modes in
/// which it works in the middle of a sentence. Said on its own it works in every app.
struct SpokenCharacter: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var spoken: [String]
    var output: String
    var enabled = true
    /// Default, Prompt and Writing; none means only on its own.
    var inSentence: Set<AppMode>

    init(id: UUID = UUID(), spoken: [String], output: String, enabled: Bool = true, inSentence: Set<AppMode>) {
        self.id = id
        self.spoken = spoken
        self.output = output
        self.enabled = enabled
        self.inSentence = inSentence
    }

    private enum CodingKeys: String, CodingKey { case id, spoken, output, enabled, inSentence }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        spoken = try c.decode([String].self, forKey: .spoken)
        output = try c.decode(String.self, forKey: .output)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        inSentence = Set(try c.decodeIfPresent([AppMode].self, forKey: .inSentence) ?? [])
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(spoken, forKey: .spoken)
        try c.encode(output, forKey: .output)
        try c.encode(enabled, forKey: .enabled)
        // In the order of the modes, so the file doesn't change from one save to the next.
        try c.encode(SpokenCharacters.modes.filter(inSentence.contains), forKey: .inSentence)
    }

    var spokenText: String { spoken.joined(separator: ", ") }

    var summary: String {
        spoken.prefix(2).map { "“\($0)”" }.joined(separator: ", ") + (spoken.count > 2 ? " …" : "")
    }
}

enum SpokenCharacters {
    /// The modes an entry can work in, in a sentence.
    static let modes: [AppMode] = [.standard, .prompt, .writing]

    /// Opening and closing quote: in Writing apps they become the language's quotes (“Typographic quotes”) or `"`.
    static let openQuote = "“"
    static let closeQuote = "”"

    /// What a new installation starts with and “Restore default characters” brings back: the eight default entries of
    /// Replacements before 0.4.0 and the words of `SpokenPunctuation`, each working where one of the two made it work.
    /// “Colon” is left out on purpose: in English it is also an organ.
    static var defaults: [SpokenCharacter] {
        [
            SpokenCharacter(spoken: ["new line", "neue Zeile"], output: "\n", inSentence: [.standard, .prompt, .writing]),
            SpokenCharacter(spoken: ["new paragraph", "neuer Absatz"], output: "\n\n", inSentence: [.standard, .prompt, .writing]),
            SpokenCharacter(spoken: ["Punkt", "Period", "Full stop"], output: ".", inSentence: [.writing]),
            SpokenCharacter(spoken: ["Komma", "Comma"], output: ",", inSentence: [.writing]),
            SpokenCharacter(spoken: ["Fragezeichen", "Question mark"], output: "?", inSentence: [.writing]),
            SpokenCharacter(spoken: ["Ausrufezeichen", "Exclamation mark", "Exclamation point"], output: "!", inSentence: [.writing]),
            SpokenCharacter(spoken: ["Doppelpunkt"], output: ":", inSentence: [.prompt, .writing]),
            // Semi-Kolon … Siemikulon: what Parakeet wrote for “Semikolon” in the owner's history.
            SpokenCharacter(spoken: ["Semikolon", "Semicolon", "Semi-Kolon", "Semi Kolon", "Semikolen", "Semi colon", "Semi-colon",
                                     "Sammy Colon", "Semikodon", "Siemikulon"],
                            output: ";", inSentence: [.prompt, .writing]),
            SpokenCharacter(spoken: ["Anführungszeichen auf", "Open quote"], output: openQuote, inSentence: [.writing]),
            SpokenCharacter(spoken: ["Anführungszeichen zu", "Close quote"], output: closeQuote, inSentence: [.writing]),
            SpokenCharacter(spoken: ["Slash", "Schrägstrich"], output: "/", inSentence: [.prompt]),
            SpokenCharacter(spoken: ["Bindestrich", "Dash", "Strich"], output: "-", inSentence: []),
        ]
    }

    /// Whether `entry` is the user's version of the default `standard`: same output and a spelling in common.
    static func isVersion(_ entry: SpokenCharacter, of standard: SpokenCharacter) -> Bool {
        let own = Set(entry.spoken.map { Replacements.normalized($0) })
        return entry.output == standard.output && standard.spoken.contains { own.contains(Replacements.normalized($0)) }
    }

    /// The entries without the spellings of the user's own enabled replacements: “Punkt” as an own entry replaces the
    /// default's “Punkt”, and the own entry's output isn't changed again afterwards.
    static func without(_ own: [Replacement], _ entries: [SpokenCharacter]) -> [SpokenCharacter] {
        let taken = Set(own.filter(\.enabled).flatMap(\.spoken).map(Replacements.normalized))
        guard !taken.isEmpty else { return entries }
        return entries.compactMap { e in
            var e = e
            e.spoken.removeAll { taken.contains(Replacements.normalized($0)) }
            return e.spoken.isEmpty ? nil : e
        }
    }

    /// The mark `SpokenPunctuation` writes for an output in a Writing app; nil for line breaks and everything else,
    /// which are replaced like replacements.
    static func mark(for output: String) -> SpokenPunctuation.Mark? {
        if output == openQuote { return .openQuote }
        if output == closeQuote { return .closeQuote }
        if Replacements.attachingOutputs.contains(output) { return .punct(output) }
        return nil
    }

    /// Runs after the user's own replacements, so theirs win. Any language: the spellings are words of one language
    /// each, and a dictation's detected language isn't always right.
    /// - Said on its own, an enabled entry works in every mode (`Replacements.apply`).
    /// - In a sentence, in the modes it is set for. Default and Prompt: as a replacement (spacing from the output, an
    ///   article before it keeps the word). Writing: punctuation and quotes go through `SpokenPunctuation` (a capital
    ///   after . ? !, a mark the model wrote is replaced, the noun rule, quote pairs), each line on its own; line breaks
    ///   and other outputs as replacements.
    static func apply(_ entries: [SpokenCharacter], to text: String, mode: AppMode, language: Lang,
                      typographic: Bool = true, terms: Set<String> = []) -> String {
        let on = entries.filter(\.enabled)
        let marked = { (e: SpokenCharacter) in mode == .writing && e.inSentence.contains(.writing) && mark(for: e.output) != nil }
        let replacements = on.filter { !marked($0) }.map {
            Replacement(id: $0.id, spoken: $0.spoken, output: $0.output, inSentence: $0.inSentence.contains(mode) ? .everywhere : .never)
        }
        let result = Replacements.apply(replacements, to: text, mode: .standard, language: language)
        guard mode == .writing else { return result }
        let table = on.filter(marked).flatMap { e in
            e.spoken.map { (words: Replacements.normalized($0).split(separator: " ").map(String.init), mark: mark(for: e.output)!) }
        }
        .filter { !$0.words.isEmpty }
        .sorted { $0.words.count > $1.words.count }
        // Also with an empty table, as “Spoken punctuation” did: a capital after the model's own . ? !
        return result.components(separatedBy: "\n").map {
            SpokenPunctuation.apply($0, table: table, language: language, typographic: typographic, terms: terms)
        }.joined(separator: "\n")
    }
}

/// Stored spoken characters (`spokenCharacters.json`), for the `spokenCharacters` layout only. A new installation
/// gets the file with the defaults.
@MainActor
@Observable
final class SpokenCharacterStore {
    nonisolated static let file = "spokenCharacters.json"

    private(set) var items: [SpokenCharacter]
    @ObservationIgnored private let store: Store

    init(store: Store = .shared) {
        self.store = store
        if let saved = store.load([SpokenCharacter].self, from: Self.file) {
            items = saved
        } else {
            items = SpokenCharacters.defaults
            // A broken file stays until the next change, as with the replacements.
            if !FileManager.default.fileExists(atPath: store.url(Self.file).path) { save() }
        }
    }

    func upsert(_ c: SpokenCharacter) {
        if let i = items.firstIndex(where: { $0.id == c.id }) { items[i] = c } else { items.append(c) }
        save()
    }

    func delete(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func setEnabled(_ id: UUID, _ on: Bool) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].enabled = on
        save()
    }

    /// Adds the default characters that are missing; entries you have (changed or not) stay as they are.
    @discardableResult
    func restoreDefaults() -> Int {
        let missing = SpokenCharacters.defaults.filter { d in !items.contains { SpokenCharacters.isVersion($0, of: d) } }
        items.append(contentsOf: missing)
        if !missing.isEmpty { save() }
        return missing.count
    }

    private func save() { store.save(items, to: Self.file) }
}
