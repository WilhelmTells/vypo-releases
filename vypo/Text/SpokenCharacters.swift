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

/// A word you say for a character (Words → Spoken characters): its spellings, the character, on/off, and whether it also
/// works in the middle of a sentence. Said on its own it always works. The same in every app, except Off apps, where
/// vypo doesn't dictate.
struct SpokenCharacter: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var spoken: [String]
    var output: String
    var enabled = true
    /// false: only on its own.
    var alsoInSentence: Bool

    init(id: UUID = UUID(), spoken: [String], output: String, enabled: Bool = true, alsoInSentence: Bool) {
        self.id = id
        self.spoken = spoken
        self.output = output
        self.enabled = enabled
        self.alsoInSentence = alsoInSentence
    }

    /// `inSentence` is the list of modes up to 0.4.1, read when `alsoInSentence` is missing and still written, so 0.4.1
    /// can read the file: all three modes when on, none when off.
    private enum CodingKeys: String, CodingKey { case id, spoken, output, enabled, alsoInSentence, inSentence }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        spoken = try c.decode([String].self, forKey: .spoken)
        output = try c.decode(String.self, forKey: .output)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        alsoInSentence = try c.decodeIfPresent(Bool.self, forKey: .alsoInSentence)
            ?? !(try c.decodeIfPresent([AppMode].self, forKey: .inSentence) ?? []).isEmpty
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(spoken, forKey: .spoken)
        try c.encode(output, forKey: .output)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(alsoInSentence, forKey: .alsoInSentence)
        try c.encode(alsoInSentence ? SpokenCharacters.modes : [], forKey: .inSentence)
    }

    var spokenText: String { spoken.joined(separator: ", ") }

    /// The first two spellings for the list, those of vypo's language first (“Comma” before “Komma” in English).
    var summary: String { summary(for: Lang(rawValue: String(Formatting.uiLocale.identifier.prefix(2))) ?? .en) }

    /// The first two spellings, those of `language` first, then the ones of no known language, then the others. Only
    /// the display: the stored order stays.
    func summary(for language: Lang) -> String {
        let rank = { (s: String) in SpokenCharacters.language(of: s).map { $0 == language ? 0 : 2 } ?? 1 }
        let shown = spoken.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
        return shown.prefix(2).map(Formatting.quoted).joined(separator: ", ") + (spoken.count > 2 ? " …" : "")
    }
}

enum SpokenCharacters {
    /// What the file says in the old `inSentence`, in this order.
    static let modes: [AppMode] = [.standard, .prompt, .writing]

    /// Opening and closing quote as stored: they are written in the forms of the detected language.
    static let openQuote = "“"
    static let closeQuote = "”"

    /// What a new installation starts with and “Restore Defaults” brings back: the eight default entries of
    /// Replacements before 0.4.0 and the words of `SpokenPunctuation`. The hyphen stays on its own: “Strich” and “Dash”
    /// are too often plain words.
    /// “Colon” is left out on purpose: in English it is also an organ.
    static var defaults: [SpokenCharacter] {
        [
            SpokenCharacter(spoken: ["new line", "neue Zeile"], output: "\n", alsoInSentence: true),
            SpokenCharacter(spoken: ["new paragraph", "neuer Absatz"], output: "\n\n", alsoInSentence: true),
            SpokenCharacter(spoken: ["Punkt", "Period", "Full stop"], output: ".", alsoInSentence: true),
            SpokenCharacter(spoken: ["Komma", "Comma"], output: ",", alsoInSentence: true),
            SpokenCharacter(spoken: ["Fragezeichen", "Question mark"], output: "?", alsoInSentence: true),
            SpokenCharacter(spoken: ["Ausrufezeichen", "Exclamation mark", "Exclamation point"], output: "!", alsoInSentence: true),
            SpokenCharacter(spoken: ["Doppelpunkt"], output: ":", alsoInSentence: true),
            // Semi-Kolon … Siemikulon: what Parakeet wrote for “Semikolon” in the owner's history.
            SpokenCharacter(spoken: ["Semikolon", "Semicolon", "Semi-Kolon", "Semi Kolon", "Semikolen", "Semi colon", "Semi-colon",
                                     "Sammy Colon", "Semikodon", "Siemikulon"],
                            output: ";", alsoInSentence: true),
            SpokenCharacter(spoken: ["Anführungszeichen auf", "Open quote"], output: openQuote, alsoInSentence: true),
            SpokenCharacter(spoken: ["Anführungszeichen zu", "Close quote"], output: closeQuote, alsoInSentence: true),
            SpokenCharacter(spoken: ["Slash", "Schrägstrich"], output: "/", alsoInSentence: true),
            SpokenCharacter(spoken: ["Bindestrich", "Dash", "Strich"], output: "-", alsoInSentence: false),
        ]
    }

    /// English or German for a spelling of the defaults (the words of `SpokenPunctuation` and the symbol words), nil
    /// for any other, also the model's mishearings (“Sammy Colon”).
    static func language(of spelling: String) -> Lang? {
        let s = Replacements.normalized(spelling)
        return [Lang.en, .de].first { knownSpellings($0).contains(s) }
    }

    private static func knownSpellings(_ language: Lang) -> Set<String> {
        let symbols: [String] = switch language {
        case .en: ["slash", "dash"]
        case .de: ["schrägstrich", "bindestrich", "strich"]
        default: []
        }
        return Set(SpokenPunctuation.phrases(language).map { $0.words.joined(separator: " ") } + symbols)
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

    /// The mark `SpokenPunctuation` writes for an output; nil for line breaks and everything else,
    /// which are replaced like replacements.
    static func mark(for output: String) -> SpokenPunctuation.Mark? {
        if output == openQuote { return .openQuote }
        if output == closeQuote { return .closeQuote }
        if Replacements.attachingOutputs.contains(output) { return .punct(output) }
        return nil
    }

    /// Runs after the user's own replacements, so theirs win. Any language: the spellings are words of one language
    /// each, and a dictation's detected language isn't always right. The same in every app:
    /// - Said on its own, an enabled entry works (`Replacements.apply`).
    /// - In a sentence, if it is set to. Punctuation and quotes go through `SpokenPunctuation` (a capital after . ? !,
    ///   a mark the model wrote is replaced, `staysWord`, quote pairs), each line on its own; line breaks and other
    ///   outputs as replacements.
    /// Spoken quotes are always the forms of `language`; “Typographic quotes” is about the `"` the model wrote.
    static func apply(_ entries: [SpokenCharacter], to text: String, language: Lang, terms: Set<String> = []) -> String {
        let on = entries.filter(\.enabled)
        let marked = { (e: SpokenCharacter) in e.alsoInSentence && mark(for: e.output) != nil }
        let quotes = language.quotes(typographic: true)
        let replacements = on.filter { !marked($0) }.map { e in
            let output = e.output == openQuote ? quotes.open : e.output == closeQuote ? quotes.close : e.output
            return Replacement(id: e.id, spoken: e.spoken, output: output, inSentence: e.alsoInSentence ? .everywhere : .never)
        }
        let result = Replacements.apply(replacements, to: text, language: language)
        let table = on.filter(marked).flatMap { e in
            e.spoken.map { (words: Replacements.normalized($0).split(separator: " ").map(String.init), mark: mark(for: e.output)!) }
        }
        .filter { !$0.words.isEmpty }
        .sorted { $0.words.count > $1.words.count }
        // Also with an empty table: a capital after the model's own . ? !
        return result.components(separatedBy: "\n").map {
            SpokenPunctuation.apply($0, table: table, language: language, typographic: true, terms: terms)
        }.joined(separator: "\n")
    }

    /// Whether `text` ends in a word that `spellings` turn into a period. A Prompt app keeps that period: the user said it.
    static func endsInSpokenPeriod(_ text: String, spellings: [String], language: Lang) -> Bool {
        let words = Tokenized(text.components(separatedBy: "\n").last ?? text).words
        return spellings.contains { spelling in
            let parts = Replacements.normalized(spelling).split(separator: " ").map(String.init)
            let start = words.count - parts.count
            guard !parts.isEmpty, start >= 0, zip(words[start...], parts).allSatisfy({ $0.core.lowercased() == $1 }) else { return false }
            return !SpokenPunctuation.staysWord(words, at: start, count: parts.count, output: ".", language: language)
        }
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
