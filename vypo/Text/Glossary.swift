import Foundation
import Observation

/// A fix the user made that could become a glossary term (§11.1, §13).
struct GlossarySuggestion: Codable, Identifiable, Hashable, Sendable {
    var heard: String
    var term: String
    var scope: GlossaryScope
    var count: Int
    var lastSeen: Date

    var id: String { heard.lowercased() + "→" + term }
}

/// A named group of terms (§23.9).
struct GlossarySet: Codable, Identifiable, Hashable, Sendable {
    static let generalID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    var id: UUID
    var name: String
    var isActive: Bool

    var isGeneral: Bool { id == Self.generalID }

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

    @ObservationIgnored private let store: Store
    /// After every change of the entries, with their number (Word Keeper, Word Collector).
    @ObservationIgnored var onEntriesChanged: (Int) -> Void = { _ in }

    init(store: Store = .shared) {
        self.store = store
        entries = store.load([GlossaryEntry].self, from: "glossary.json") ?? []
        suggestions = store.load([GlossarySuggestion].self, from: "suggestions.json") ?? []
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

    /// Adds or increments a suggestion; returns it.
    @discardableResult
    func suggest(heard: String, term: String, scope: GlossaryScope) -> GlossarySuggestion {
        if let i = suggestions.firstIndex(where: { $0.heard.lowercased() == heard.lowercased() && $0.term == term }) {
            suggestions[i].count += 1
            suggestions[i].lastSeen = Date()
            saveSuggestions()
            return suggestions[i]
        }
        let s = GlossarySuggestion(heard: heard, term: term, scope: scope, count: 1, lastSeen: Date())
        suggestions.append(s)
        saveSuggestions()
        return s
    }

    /// Creates the entry with `soundsLike = [heard]` in General and drops the suggestion.
    func accept(_ suggestion: GlossarySuggestion) {
        if let i = entries.firstIndex(where: { $0.term == suggestion.term }) {
            if !entries[i].soundsLike.contains(suggestion.heard) { entries[i].soundsLike.append(suggestion.heard) }
            saveEntries()
        } else {
            add(term: suggestion.term, soundsLike: [suggestion.heard], scope: suggestion.scope)
        }
        ignore(suggestion)
    }

    func ignore(_ suggestion: GlossarySuggestion) {
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
