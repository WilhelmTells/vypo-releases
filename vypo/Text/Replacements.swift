import Foundation
import Observation

/// Where an entry works in the middle of a sentence. Said on its own, every enabled entry works in every app.
enum SentenceScope: String, Codable, CaseIterable, Sendable {
    case everywhere
    case promptOnly
    case never
}

/// What you say (one or more spellings) and what it becomes (§11.5).
struct Replacement: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var spoken: [String]
    var output: String
    var enabled = true
    var inSentence: SentenceScope = .everywhere

    init(id: UUID = UUID(), spoken: [String], output: String, enabled: Bool = true, inSentence: SentenceScope = .everywhere) {
        self.id = id
        self.spoken = spoken
        self.output = output
        self.enabled = enabled
        self.inSentence = inSentence
    }

    /// `spoken` as typed in the field: spellings separated by commas.
    init(spoken: String, output: String, enabled: Bool = true, inSentence: SentenceScope = .everywhere) {
        self.init(spoken: Replacements.variants(spoken), output: output, enabled: enabled, inSentence: inSentence)
    }

    private enum CodingKeys: String, CodingKey { case id, spoken, output, enabled, inSentence }

    /// Older files hold one string in `spoken` (and none of `inSentence`, which then is “everywhere”).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        if let list = try? c.decode([String].self, forKey: .spoken) {
            spoken = list
        } else {
            spoken = Replacements.variants(try c.decode(String.self, forKey: .spoken))
        }
        output = try c.decode(String.self, forKey: .output)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        inSentence = try c.decodeIfPresent(SentenceScope.self, forKey: .inSentence) ?? .everywhere
    }

    /// The spellings as typed in the field.
    var spokenText: String { spoken.joined(separator: ", ") }

    /// The first two spellings for the list: `"Slash", "Schrägstrich"…`.
    var summary: String {
        spoken.prefix(2).map { "“\($0)”" }.joined(separator: ", ") + (spoken.count > 2 ? " …" : "")
    }
}

enum Replacements {
    /// Written after the word before it: no space before, one after.
    static let attachingOutputs: Set<String> = [",", ";", ":", ".", "?", "!"]
    /// Written between the words around it: no space on either side.
    static let connectingOutputs: Set<String> = ["/", "\\", "_", "~", "-"]

    enum Join { case attach, connect }

    /// How an entry's output is spaced: decided by the output alone.
    static func join(for output: String) -> Join? {
        if attachingOutputs.contains(output) { return .attach }
        if connectingOutputs.contains(output) { return .connect }
        return nil
    }

    /// The entries every installation starts with, and `Restore default entries` brings back.
    /// “Colon” is left out on purpose: in English it is also an organ, and the entry has one rule for all spellings.
    static var defaults: [Replacement] {
        [
            Replacement(spoken: ["new line", "neue Zeile"], output: "\n"),
            Replacement(spoken: ["new paragraph", "neuer Absatz"], output: "\n\n"),
            Replacement(spoken: ["Slash", "Schrägstrich"], output: "/", inSentence: .promptOnly),
            // Semi-Kolon … Siemikulon: what Parakeet wrote for “Semikolon” in the owner's history.
            Replacement(spoken: ["Semikolon", "Semicolon", "Semi-Kolon", "Semi Kolon", "Semikolen", "Sammy Colon", "Semikodon", "Siemikulon"],
                        output: ";", inSentence: .promptOnly),
            Replacement(spoken: ["Doppelpunkt"], output: ":", inSentence: .promptOnly),
            Replacement(spoken: ["Punkt", "Period", "Full stop"], output: ".", inSentence: .never),
            Replacement(spoken: ["Komma", "Comma"], output: ",", inSentence: .never),
            Replacement(spoken: ["Bindestrich", "Dash", "Strich"], output: "-", inSentence: .never),
        ]
    }

    /// Whether `entry` is the user's version of the default `standard`: same output and a spelling in common.
    static func isVersion(_ entry: Replacement, of standard: Replacement) -> Bool {
        let own = Set(entry.spoken.map { normalized($0) })
        return entry.output == standard.output && standard.spoken.contains { own.contains(normalized($0)) }
    }

    /// Whether a text is a single symbol or punctuation mark, e.g. a dictated “Slash” that became `/`.
    static func isLoneSymbol(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count == 1, let c = t.first else { return false }
        return c.isPunctuation || c.isSymbol
    }

    /// Lowercase, single spaces.
    static func normalized(_ phrase: String) -> String {
        phrase.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    /// The whole text as one phrase when it has no punctuation of its own except what the model put at the ends
    /// (`Semikolon.` → `semikolon`); nil for several sentences or a text with inner punctuation (`Full, stop`).
    static func alonePhrase(_ text: String) -> String? {
        let words = Tokenized(text).words
        guard let first = words.first, !first.core.isEmpty else { return nil }
        for (i, w) in words.enumerated() {
            if w.core.isEmpty { return nil }
            if i > 0 && !w.lead.isEmpty { return nil }
            if i < words.count - 1 && !w.trail.isEmpty { return nil }
        }
        return words.map { $0.core.lowercased() }.joined(separator: " ")
    }

    /// Said on its own, an enabled entry works in every app. In a sentence: as set per entry
    /// (`inSentence`; “Prompt apps only” in `mode == .prompt`). Case-insensitive, whole words, also with a trailing
    /// "." or "," the model added. Longest first. Outputs of `, ; : . ? !` attach to the word before, outputs of
    /// `/ \ _ ~ -` join the words around them.
    static func apply(_ replacements: [Replacement], to text: String, mode: AppMode = .standard) -> String {
        let active = replacements.filter { $0.enabled && $0.spoken.contains { !normalized($0).isEmpty } }
        if let phrase = alonePhrase(text),
           let hit = active.first(where: { $0.spoken.contains { normalized($0) == phrase } }) {
            return hit.output
        }
        let here = active.filter { $0.inSentence == .everywhere || ($0.inSentence == .promptOnly && mode == .prompt) }
        let pairs = here.flatMap { r in r.spoken.map { (spelling: $0, entry: r) } }
            .filter { !normalized($0.spelling).isEmpty }
            .sorted { $0.spelling.count > $1.spelling.count }
        var result = text
        for (spelling, r) in pairs where join(for: r.output) == nil {
            let words = spelling.split(whereSeparator: \.isWhitespace).map { NSRegularExpression.escapedPattern(for: String($0)) }
            let phrase = words.joined(separator: "\\s+")
            let newline = r.output.first?.isNewline == true || r.output.last?.isNewline == true
            // Around a line break the surrounding spaces go too, and a comma the model put right before it
            // (not a period, question or exclamation mark).
            let pattern = newline
                ? ",?[ \\t]*(?<![\\p{L}\\p{N}])\(phrase)[.,]?(?![\\p{L}\\p{N}])[ \\t]*"
                : "(?<![\\p{L}\\p{N}])\(phrase)[.,]?(?![\\p{L}\\p{N}])"
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let template = NSRegularExpression.escapedTemplate(for: r.output)
            result = re.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: template)
        }
        let symbols = pairs.compactMap { p -> (words: [String], char: String, join: Join)? in
            guard let j = join(for: p.entry.output) else { return nil }
            return (normalized(p.spelling).split(separator: " ").map(String.init), p.entry.output, j)
        }
        guard !symbols.isEmpty else { return result }
        // Line breaks (a spoken "new line" became one) stay: each line on its own.
        return result.components(separatedBy: "\n").map { applySymbols($0, symbols) }.joined(separator: "\n")
    }

    private enum Item {
        case word(TextWord)
        case symbol(String, Join)
    }

    /// A symbol word right after an article or possessive (the same list as the glossary's) stays a word.
    /// `Projekte slash vypo` → `Projekte/vypo`; `Begriffserklärung, Doppelpunkt, Zero` → `Begriffserklärung: Zero`.
    /// A symbol the model wrote itself is kept once: `Anna/slash` → `Anna/`.
    private static func applySymbols(_ text: String, _ table: [(words: [String], char: String, join: Join)]) -> String {
        let table = table.sorted { $0.words.count > $1.words.count }
        let words = Tokenized(text).words
        var items: [Item] = []
        var i = 0
        outer: while i < words.count {
            for entry in table where i + entry.words.count <= words.count {
                let window = words[i..<(i + entry.words.count)]
                guard zip(window, entry.words).allSatisfy({ $0.core.lowercased() == $1 }) else { continue }
                // “the slash command”, “der Doppelpunkt”: after an article or possessive it is a noun, not a symbol.
                if i > 0, GlossaryCorrector.determiners.contains(words[i - 1].core.lowercased()) { continue }
                if let lead = window.first?.lead, !lead.isEmpty {
                    var w = TextWord(Substring(lead)); w.lead = lead; w.core = ""; w.trail = ""
                    items.append(.word(w))
                }
                items.append(.symbol(entry.char, entry.join))
                i += entry.words.count
                continue outer
            }
            let w = words[i]
            let lower = w.core.lowercased()
            if let hit = table.first(where: { $0.join == .connect && $0.words.count == 1 && lower.count > $0.words[0].count + 1
                                              && lower.hasSuffix($0.char + $0.words[0]) }) {
                var kept = w
                kept.core = String(w.core.dropLast(hit.words[0].count))   // keeps the symbol: "Anna/"
                kept.trail = ""
                items.append(.word(kept))
                items.append(.symbol(hit.char, hit.join))
            } else {
                items.append(.word(w))
            }
            i += 1
        }

        var out = ""
        var glue = true   // no space before the next word
        for item in items {
            switch item {
            case .word(let w):
                if !glue && !out.isEmpty { out += " " }
                out += w.text
                glue = false
            case .symbol(let char, let join):
                while let last = out.last, last == " " || last == "\t" { out.removeLast() }
                // The comma or period the model put there goes; any other symbol before it stays.
                if let last = out.last, ",.".contains(last) { out.removeLast() }
                if !out.hasSuffix(char) { out += char }
                glue = join == .connect
            }
        }
        return out
    }

    /// The spellings in a "Spoken" field: split at commas, trimmed, without empty ones or repeats.
    static func variants(_ spoken: String) -> [String] {
        var seen = Set<String>()
        return spoken.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    /// "↵" for line breaks, for display.
    static func display(_ output: String) -> String {
        output.replacingOccurrences(of: "\n", with: "↵")
    }

    /// The one-time move to symbols as entries (flag `symbolsAreReplacements`), a pure function of the old list:
    /// 1. old entries work as before (“everywhere”), 2. entries with the same output, state and scope become one entry
    /// with several spellings, 3. the default entries are added, or merged into the user's version of them (spellings
    /// together, the default's “in a sentence”), 4. the two old switches turn off what they used to turn off.
    static func migrated(_ items: [Replacement], symbolsInSentence: Bool = true, symbolsAlone: Bool = true) -> [Replacement] {
        var merged: [Replacement] = []
        for r in items {
            if let i = merged.firstIndex(where: { $0.output == r.output && $0.enabled == r.enabled && $0.inSentence == r.inSentence }) {
                merged[i].spoken = union(merged[i].spoken, r.spoken)
            } else {
                merged.append(r)
            }
        }
        for d in defaults {
            var entry = d
            if let i = merged.firstIndex(where: { isVersion($0, of: d) }) {
                merged[i].spoken = union(merged[i].spoken, d.spoken)
                merged[i].inSentence = d.inSentence
                entry = merged[i]
            } else {
                merged.append(d)
                entry = d
            }
            guard let i = merged.firstIndex(where: { $0.id == entry.id }) else { continue }
            if !symbolsInSentence && merged[i].inSentence == .promptOnly { merged[i].inSentence = .never }
            if !symbolsAlone && d.inSentence == .never { merged[i].enabled = false }
        }
        return merged
    }

    private static func union(_ a: [String], _ b: [String]) -> [String] {
        var out = a
        for s in b where !out.contains(where: { normalized($0) == normalized(s) }) { out.append(s) }
        return out
    }
}

/// Stored replacements (`replacements.json`).
@MainActor
@Observable
final class ReplacementStore {
    private(set) var items: [Replacement]
    @ObservationIgnored private let store: Store

    init(store: Store = .shared, defaults: UserDefaults = AppDefaults.standard) {
        self.store = store
        items = store.load([Replacement].self, from: "replacements.json") ?? Replacements.defaults
        // Once: the symbol words become entries of this list (and the two old switches for them go).
        if !defaults.bool(forKey: DefaultsKey.symbolsAreReplacements) {
            defaults.set(true, forKey: DefaultsKey.symbolsAreReplacements)
            items = Replacements.migrated(items,
                                          symbolsInSentence: defaults.object(forKey: DefaultsKey.spokenSymbols) as? Bool ?? true,
                                          symbolsAlone: defaults.object(forKey: DefaultsKey.spokenSymbolsAlone) as? Bool ?? true)
            defaults.removeObject(forKey: DefaultsKey.spokenSymbols)
            defaults.removeObject(forKey: DefaultsKey.spokenSymbolsAlone)
            defaults.removeObject(forKey: DefaultsKey.replacementVariantsSplit)
            save()
        }
    }

    func upsert(_ r: Replacement) {
        if let i = items.firstIndex(where: { $0.id == r.id }) { items[i] = r } else { items.append(r) }
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

    /// Adds the default entries that are missing; entries you have (changed or not) stay as they are.
    @discardableResult
    func restoreDefaults() -> Int {
        let missing = Replacements.defaults.filter { d in !items.contains { Replacements.isVersion($0, of: d) } }
        items.append(contentsOf: missing)
        if !missing.isEmpty { save() }
        return missing.count
    }

    private func save() { store.save(items, to: "replacements.json") }
}
