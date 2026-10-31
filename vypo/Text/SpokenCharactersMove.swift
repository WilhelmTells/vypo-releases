import Foundation

/// What the move from the `legacy` layout to Spoken characters does with a Mac's replacements (`SpokenCharacters.migration`).
struct SpokenCharactersMigration: Sendable, Equatable {
    /// The new `spokenCharacters.json`, in the order of `SpokenCharacters.defaults`.
    var characters: [SpokenCharacter]
    /// What stays in Replacements: every entry that is no default's version, in its order.
    var ownReplacements: [Replacement]
    /// “Moves to Spoken characters”: the defaults the user had, with their changes.
    var moved: [SpokenCharacter]
    /// “New in Spoken characters”: the defaults Replacements never had (“?”, “!”, the quotes).
    var added: [SpokenCharacter]
    /// The outputs of defaults that had two or more versions in the list; each became one entry.
    var merged: [String]
}

extension SpokenCharacters {
    /// The modes of a changed “in a sentence” of a replacement.
    static func modes(for scope: SentenceScope) -> Set<AppMode> {
        switch scope {
        case .everywhere: [.standard, .prompt, .writing]
        case .promptOnly: [.prompt]
        case .never: []
        }
    }

    /// The move, a pure function of the old list and the “Spoken punctuation” switch:
    /// - An entry that is a version of a default of Replacements (`Replacements.isVersion`) becomes the default of
    ///   Spoken characters with the same output: the user's spellings in their order, plus only the spellings of the new
    ///   default that no old default had (one the user removed stays removed; a list that still holds exactly the old
    ///   default's spellings gets the new default's order); the user's on/off; the new default's modes if “in a
    ///   sentence” was left as it came, otherwise `modes(for:)`. Two versions of one default become one entry
    ///   (spellings together, on if either was on, the modes of the entries that were on together).
    /// - “Spoken punctuation” on: a mark entry keeps Writing whatever the scope was, because the separate table did
    ///   that in 0.4.0. One that was off is on in Writing apps only.
    /// - A default with no version in the list was deleted and stays deleted.
    /// - Defaults Replacements never had are added.
    /// - “Spoken punctuation” off: no punctuation or quote works in a Writing sentence, as before.
    /// - Everything else stays in Replacements, also an own symbol entry (“Punkt” → “.” that is no version).
    static func migration(from items: [Replacement], spokenPunctuation: Bool) -> SpokenCharactersMigration {
        let legacy = Replacements.defaults
        let fitted = { (c: SpokenCharacter) -> SpokenCharacter in
            var c = c
            if !spokenPunctuation && mark(for: c.output) != nil { c.inSentence.remove(.writing) }
            return c
        }
        var result = SpokenCharactersMigration(characters: [], ownReplacements: [], moved: [], added: [], merged: [])
        for d in defaults {
            guard let old = legacy.first(where: { $0.output == d.output }) else {
                let c = fitted(d)
                result.added.append(c)
                result.characters.append(c)
                continue
            }
            let versions = items.filter { Replacements.isVersion($0, of: old) }
            guard let first = versions.first else { continue }
            if versions.count > 1 { result.merged.append(d.output) }
            var c = d
            c.id = first.id
            let own = versions.reduce([String]()) { Replacements.union($0, $1.spoken) }
            let ownSet = Set(own.map(Replacements.normalized))
            if ownSet == Set(old.spoken.map(Replacements.normalized)) {
                c.spoken = d.spoken
            } else {
                // Only a spelling that is new in this default comes back, not one the user removed from the old one.
                let known = Set(old.spoken.map(Replacements.normalized))
                c.spoken = Replacements.union(own, d.spoken.filter { !known.contains(Replacements.normalized($0)) })
            }
            c.enabled = versions.contains(where: \.enabled)
            let counted = c.enabled ? versions.filter(\.enabled) : versions
            c.inSentence = counted.reduce(into: Set<AppMode>()) {
                $0.formUnion($1.inSentence == old.inSentence ? d.inSentence : modes(for: $1.inSentence))
            }
            if spokenPunctuation && mark(for: c.output) != nil {
                c.inSentence.insert(.writing)
                if !c.enabled {
                    c.enabled = true
                    c.inSentence = [.writing]
                }
            }
            c = fitted(c)
            result.moved.append(c)
            result.characters.append(c)
        }
        result.ownReplacements = items.filter { r in !legacy.contains { Replacements.isVersion(r, of: $0) } }
        return result
    }
}

/// The copy made before the move: `replacements.json` and the Words and Writing preferences, in
/// `Backups/spoken-characters-<yyyy-MM-dd-HHmmss>/` of vypo's data folder. Restored by hand (see the 0.4.1 report).
enum SpokenCharactersBackup {
    static let folder = "Backups"
    static let preferencesFile = "preferences.json"
    static let preferenceKeys = [DefaultsKey.wordsLayout, DefaultsKey.spokenPunctuation, DefaultsKey.spokenCharacters,
                                 DefaultsKey.typographicQuotes]

    /// Writes the backup and returns its folder; throws if any part of it couldn't be written. The file is copied as it
    /// is on disk; without one, `replacements` (the list in memory) is written. Preferences as they read now (also a
    /// value that was never changed, from the registered defaults).
    static func write(store: Store, defaults: UserDefaults, replacements: [Replacement], now: Date = Date(),
                      timeZone: TimeZone = .current) throws -> URL {
        let files = FileManager.default
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        let parent = store.directory.appendingPathComponent(folder, isDirectory: true)
        try files.createDirectory(at: parent, withIntermediateDirectories: true)
        let name = "spoken-characters-\(f.string(from: now))"
        var dir = parent.appendingPathComponent(name, isDirectory: true)
        var n = 2
        while files.fileExists(atPath: dir.path) {
            dir = parent.appendingPathComponent("\(name)-\(n)", isDirectory: true)
            n += 1
        }
        try files.createDirectory(at: dir, withIntermediateDirectories: false)
        let source = store.url(ReplacementStore.file)
        let target = dir.appendingPathComponent(ReplacementStore.file)
        if files.fileExists(atPath: source.path) {
            try files.copyItem(at: source, to: target)
        } else {
            try Store.encoder.encode(replacements).write(to: target, options: .atomic)
        }
        var prefs: [String: Any] = [:]
        for key in preferenceKeys { if let value = defaults.object(forKey: key) { prefs[key] = value } }
        let data = try JSONSerialization.data(withJSONObject: prefs, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: dir.appendingPathComponent(preferencesFile), options: .atomic)
        return dir
    }
}
