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
    /// The move, a pure function of the old list and the “Spoken punctuation” switch:
    /// - An entry that is a version of a default of Replacements (`Replacements.isVersion`) becomes the default of
    ///   Spoken characters with the same output: the user's spellings in their order, plus only the spellings of the new
    ///   default that no old default had (one the user removed stays removed; a list that still holds exactly the old
    ///   default's spellings gets the new default's order); the user's on/off; the new default's “Also in a sentence” if
    ///   “in a sentence” was left as it came, otherwise `SentenceScope.alsoInSentence`. Two versions of one default
    ///   become one entry (spellings together, on if either was on, “Also in a sentence” if an entry that was on had it).
    /// - “Spoken punctuation” on: a mark entry is “Also in a sentence” whatever the scope was, because the separate table
    ///   did that in Writing apps. One that was off stays off: there is no “Writing only” any more, and on would bring
    ///   the word back in every app.
    /// - “Spoken punctuation” off: marks stayed out of Writing sentences, so a mark entry goes by its own scope, whatever
    ///   the new default says, and a mark Replacements never had is “Only on its own”.
    /// - A default with no version in the list was deleted and stays deleted.
    /// - Defaults Replacements never had are added.
    /// - Everything else stays in Replacements, also an own symbol entry (“Punkt” → “.” that is no version).
    static func migration(from items: [Replacement], spokenPunctuation: Bool) -> SpokenCharactersMigration {
        let legacy = Replacements.defaults
        var result = SpokenCharactersMigration(characters: [], ownReplacements: [], moved: [], added: [], merged: [])
        for d in defaults {
            guard let old = legacy.first(where: { $0.output == d.output }) else {
                var c = d
                if !spokenPunctuation && mark(for: c.output) != nil { c.alsoInSentence = false }
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
            if mark(for: c.output) == nil {
                c.alsoInSentence = counted.contains { $0.inSentence == old.inSentence ? d.alsoInSentence : $0.inSentence.alsoInSentence }
            } else {
                c.alsoInSentence = spokenPunctuation || counted.contains(where: \.inSentence.alsoInSentence)
            }
            result.moved.append(c)
            result.characters.append(c)
        }
        result.ownReplacements = items.filter { r in !legacy.contains { Replacements.isVersion(r, of: $0) } }.map(\.inEveryApp)
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
