import Foundation
import Observation

/// A fix the user made that could become a glossary term (§11.1, §13): only the term, what vypo had heard instead and how
/// often. One per term: a name is rarely misheard the same way twice, so the corrections to it add up.
struct GlossarySuggestion: Codable, Identifiable, Hashable, Sendable {
    /// Where a correction was found. A fix in History is deliberate; one in an app has to happen twice.
    enum Source: Sendable {
        case history, app
    }

    /// A correction found in an app shows from this count on.
    static let threshold = 2

    /// The first spelling; 0.4.1 reads only this one.
    var heard: String
    var term: String
    var scope: GlossaryScope
    var count: Int
    var lastSeen: Date
    /// The spellings after `heard`; nil while there are none.
    var otherSpellings: [String]?
    /// At least one of the corrections was a pencil fix in History.
    var historyFix: Bool
    /// The Words pane has shown it, or History has offered it. Keeps the dot in the sidebar away.
    var seen: Bool

    var id: String { term }
    var isVisible: Bool { historyFix || count >= Self.threshold }
    /// Everything vypo heard for this term, each spelling once in any case.
    var spellings: [String] { [heard] + (otherSpellings ?? []) }

    /// The spellings for a row: the first few, and how many more.
    var spellingsLine: String {
        let shown = spellings.prefix(Self.shownSpellings).map(Self.unbroken).joined(separator: " / ")
        let more = spellings.count - Self.shownSpellings
        return more > 0 ? "\(shown) +\(more)" : shown
    }

    private static let shownSpellings = 4

    /// German text hyphenates, and “Zwie-belics” reads like another spelling: a word joiner between all letters.
    private static func unbroken(_ spelling: String) -> String {
        spelling.split(separator: " ").map { $0.map(String.init).joined(separator: "\u{2060}") }.joined(separator: " ")
    }

    /// `heard` in any case, `term` with its own: “Vypo” and “VYPO” are different corrections.
    static func key(heard: String, term: String) -> String { heard.lowercased() + "→" + term }

    init(heard: String, term: String, scope: GlossaryScope, count: Int, lastSeen: Date, historyFix: Bool, seen: Bool) {
        self.heard = heard
        self.term = term
        self.scope = scope
        self.count = count
        self.lastSeen = lastSeen
        self.historyFix = historyFix
        self.seen = seen
    }

    /// Before 0.5.0 every suggestion came from History, so an old one shows at once and without a dot.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        heard = try c.decode(String.self, forKey: .heard)
        term = try c.decode(String.self, forKey: .term)
        scope = try c.decode(GlossaryScope.self, forKey: .scope)
        count = try c.decode(Int.self, forKey: .count)
        lastSeen = try c.decode(Date.self, forKey: .lastSeen)
        otherSpellings = try c.decodeIfPresent([String].self, forKey: .otherSpellings)
        historyFix = try c.decodeIfPresent(Bool.self, forKey: .historyFix) ?? true
        seen = try c.decodeIfPresent(Bool.self, forKey: .seen) ?? true
    }

    /// Takes in another correction of the same term.
    mutating func add(spelling: String) {
        guard !spellings.contains(where: { $0.caseInsensitiveCompare(spelling) == .orderedSame }) else { return }
        otherSpellings = (otherSpellings ?? []) + [spelling]
    }

    /// A term corrected in two languages is suggested for both.
    mutating func widen(to other: GlossaryScope) {
        if scope != other { scope = .all }
    }

    /// One suggestion per term; until the fix-up of 0.5.0 there was one per word pair. The oldest pair's spelling comes first.
    static func merged(_ suggestions: [GlossarySuggestion]) -> [GlossarySuggestion] {
        var result: [GlossarySuggestion] = []
        for s in suggestions.sorted(by: { $0.lastSeen < $1.lastSeen }) {
            guard let i = result.firstIndex(where: { $0.term == s.term }) else {
                result.append(s)
                continue
            }
            s.spellings.forEach { result[i].add(spelling: $0) }
            result[i].widen(to: s.scope)
            result[i].count += s.count
            result[i].lastSeen = s.lastSeen
            result[i].historyFix = result[i].historyFix || s.historyFix
            result[i].seen = result[i].seen && s.seen
        }
        return result.sorted { $0.lastSeen > $1.lastSeen }
    }
}

/// A suggestion the user turned down. Never suggested again.
struct IgnoredSuggestion: Codable, Hashable, Sendable {
    var heard: String
    var term: String
    /// True: the whole term is turned down, whatever vypo hears for it. Missing in the pairs ignored before the fix-up
    /// of 0.5.0, which block only their pair.
    var wholeTerm: Bool?
}

/// A named group of terms (§23.9).
struct GlossarySet: Codable, Identifiable, Hashable, Sendable {
    static let generalID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    var id: UUID
    var name: String
    var isActive: Bool

    var isGeneral: Bool { id == Self.generalID }

    /// The name on screen: the default set in vypo's language while it has its default name. The stored name stays.
    var displayName: String { isGeneral && name == Self.general.name ? String(localized: "General") : name }

    static let general = GlossarySet(id: generalID, name: "General", isActive: true)
}

/// The export/import file format.
struct GlossaryFile: Codable {
    var sets: [GlossarySet]?
    var entries: [GlossaryEntry]
}

/// Glossary entries, sets and suggestions, stored as JSON (§11.1).
@MainActor
@Observable
final class GlossaryStore {
    private(set) var entries: [GlossaryEntry] = []
    private(set) var suggestions: [GlossarySuggestion] = []
    private(set) var sets: [GlossarySet] = [.general]
    @ObservationIgnored private var ignored: Set<String> = []
    @ObservationIgnored private var ignoredTerms: Set<String> = []
    @ObservationIgnored private var ignoredList: [IgnoredSuggestion] = []

    @ObservationIgnored private let store: Store
    /// After every change of the entries, with their number (Word Keeper, Word Collector).
    @ObservationIgnored var onEntriesChanged: (Int) -> Void = { _ in }

    init(store: Store = .shared) {
        self.store = store
        entries = store.load([GlossaryEntry].self, from: "glossary.json") ?? []
        suggestions = GlossarySuggestion.merged(store.load([GlossarySuggestion].self, from: "suggestions.json") ?? [])
        ignoredList = store.load([IgnoredSuggestion].self, from: "ignoredSuggestions.json") ?? []
        ignored = Set(ignoredList.map { GlossarySuggestion.key(heard: $0.heard, term: $0.term) })
        ignoredTerms = Set(ignoredList.filter { $0.wholeTerm == true }.map(\.term))
        let savedSets = store.load([GlossarySet].self, from: "glossarySets.json") ?? []
        sets = [savedSets.first(where: \.isGeneral) ?? .general] + savedSets.filter { !$0.isGeneral }
        sets[0].name = GlossarySet.general.name
    }

    // MARK: Entries

    /// Entries used while dictating in `lang`: matching scope, active sets.
    func entries(for lang: Lang) -> [GlossaryEntry] {
        let active = Set(sets.filter(\.isActive).map(\.id))
        return entries.filter { $0.scope.applies(to: lang) && active.contains($0.setID ?? GlossarySet.generalID) }
    }

    func contains(term: String) -> Bool { entries.contains { $0.term == term } }

    /// Adds a term unless it already exists (exact, case-sensitive). Returns false for duplicates.
    @discardableResult
    func add(term: String, soundsLike: [String] = [], scope: GlossaryScope = .all, setID: UUID? = nil) -> Bool {
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, !contains(term: term) else { return false }
        entries.append(GlossaryEntry(term: term, soundsLike: soundsLike, scope: scope,
                                     setID: setID == GlossarySet.generalID ? nil : setID))
        saveEntries()
        return true
    }

    func update(_ entry: GlossaryEntry) {
        guard let i = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var e = entry
        if e.setID == GlossarySet.generalID { e.setID = nil }
        entries[i] = e
        saveEntries()
    }

    func delete(_ id: UUID) {
        entries.removeAll { $0.id == id }
        saveEntries()
    }

    private func saveEntries() {
        entries.sort { $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending }
        store.save(entries, to: "glossary.json")
        onEntriesChanged(entries.count)
    }

    // MARK: Suggestions

    /// What the Words pane shows: a fix from History at once, a correction in an app once it was seen twice.
    var visibleSuggestions: [GlossarySuggestion] { suggestions.filter(\.isVisible) }

    /// A suggestion the user hasn't seen yet: the dot on “Words” in the sidebar.
    var hasUnseenSuggestions: Bool { suggestions.contains { $0.isVisible && !$0.seen } }

    /// The Words pane is on screen.
    func markSuggestionsSeen() {
        guard hasUnseenSuggestions else { return }
        for i in suggestions.indices where suggestions[i].isVisible { suggestions[i].seen = true }
        saveSuggestions()
    }

    /// Adds a correction to the term's suggestion and returns it; nil for a term or a pair the user ignored.
    @discardableResult
    func suggest(heard: String, term: String, scope: GlossaryScope, source: GlossarySuggestion.Source = .history) -> GlossarySuggestion? {
        guard !ignoredTerms.contains(term), !ignored.contains(GlossarySuggestion.key(heard: heard, term: term)) else { return nil }
        let isHistory = source == .history
        if let i = suggestions.firstIndex(where: { $0.term == term }) {
            suggestions[i].add(spelling: heard)
            suggestions[i].widen(to: scope)
            suggestions[i].count += 1
            suggestions[i].lastSeen = Date()
            if isHistory {
                suggestions[i].historyFix = true
                suggestions[i].seen = true
            }
            let s = suggestions[i]
            saveSuggestions()
            return s
        }
        let s = GlossarySuggestion(heard: heard, term: term, scope: scope, count: 1, lastSeen: Date(),
                                   historyFix: isHistory, seen: isHistory)
        suggestions.append(s)
        saveSuggestions()
        return s
    }

    /// Every word pair the filter let through goes to its term's suggestion; returns the last one.
    @discardableResult
    func learn(from pairs: [WordDiff.Substitution], scope: GlossaryScope, source: GlossarySuggestion.Source) -> GlossarySuggestion? {
        var latest: GlossarySuggestion?
        for pair in pairs {
            latest = suggest(heard: pair.heard, term: pair.term, scope: scope, source: source) ?? latest
        }
        return latest
    }

    /// Creates the entry with every heard spelling as “sounds like” in General and drops the suggestion.
    func accept(_ suggestion: GlossarySuggestion) {
        // The banner in History holds a copy; more spellings may have come in since.
        let current = suggestions.first { $0.id == suggestion.id } ?? suggestion
        if let i = entries.firstIndex(where: { $0.term == current.term }) {
            for spelling in current.spellings
            where !entries[i].soundsLike.contains(where: { $0.caseInsensitiveCompare(spelling) == .orderedSame }) {
                entries[i].soundsLike.append(spelling)
            }
            saveEntries()
        } else {
            add(term: current.term, soundsLike: current.spellings, scope: current.scope)
        }
        drop(current)
    }

    /// Turns a term down for good, with every spelling and any that comes later.
    func ignore(_ suggestion: GlossarySuggestion) {
        let current = suggestions.first { $0.id == suggestion.id } ?? suggestion
        drop(current)
        ignoredTerms.insert(current.term)
        ignoredList.removeAll { $0.term == current.term }
        for spelling in current.spellings {
            ignored.insert(GlossarySuggestion.key(heard: spelling, term: current.term))
            ignoredList.append(IgnoredSuggestion(heard: spelling, term: current.term, wholeTerm: true))
        }
        store.save(ignoredList, to: "ignoredSuggestions.json")
    }

    private func drop(_ suggestion: GlossarySuggestion) {
        suggestions.removeAll { $0.id == suggestion.id }
        saveSuggestions()
    }

    private func saveSuggestions() {
        suggestions.sort { $0.lastSeen > $1.lastSeen }
        store.save(suggestions, to: "suggestions.json")
    }

    // MARK: Sets (§23.9)

    func set(for entry: GlossaryEntry) -> GlossarySet {
        sets.first { $0.id == (entry.setID ?? GlossarySet.generalID) } ?? .general
    }

    func count(in set: GlossarySet) -> Int {
        entries.filter { ($0.setID ?? GlossarySet.generalID) == set.id }.count
    }

    @discardableResult
    func addSet(named name: String) -> GlossarySet {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = sets.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { return existing }
        let s = GlossarySet(id: UUID(), name: name, isActive: true)
        sets.append(s)
        saveSets()
        return s
    }

    func setActive(_ id: UUID, _ active: Bool) {
        guard let i = sets.firstIndex(where: { $0.id == id }) else { return }
        sets[i].isActive = active
        saveSets()
    }

    func rename(_ id: UUID, to name: String) {
        guard let i = sets.firstIndex(where: { $0.id == id }), !sets[i].isGeneral else { return }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        sets[i].name = name
        saveSets()
    }

    /// Deletes a set and its terms. General can't be deleted.
    func deleteSet(_ id: UUID) {
        guard id != GlossarySet.generalID else { return }
        sets.removeAll { $0.id == id }
        entries.removeAll { $0.setID == id }
        saveSets()
        saveEntries()
    }

    private func saveSets() {
        store.save(sets, to: "glossarySets.json")
    }

    // MARK: Import / export

    func exportData() throws -> Data {
        try Store.encoder.encode(GlossaryFile(sets: sets, entries: entries))
    }

    /// Merges sets by name and adds new terms.
    func importData(_ data: Data) throws {
        let file: GlossaryFile
        if let f = try? Store.decoder.decode(GlossaryFile.self, from: data) {
            file = f
        } else {
            file = GlossaryFile(sets: nil, entries: try Store.decoder.decode([GlossaryEntry].self, from: data))
        }
        var setMap: [UUID: UUID] = [:]
        for s in file.sets ?? [] {
            setMap[s.id] = s.isGeneral || s.name == GlossarySet.general.name ? GlossarySet.generalID : addSet(named: s.name).id
        }
        for e in file.entries where !contains(term: e.term) {
            var new = e
            new.id = UUID()
            new.setID = e.setID.flatMap { setMap[$0] }
            if new.setID == GlossarySet.generalID { new.setID = nil }
            entries.append(new)
        }
        saveEntries()
    }
}
