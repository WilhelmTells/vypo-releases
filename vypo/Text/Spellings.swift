import Foundation

/// Spellings (Settings → Words): abbreviations, file formats and product names that come out right every time,
/// whatever capitals the model chose. One list for all languages; each line is just the correct spelling.
enum Spellings {
    /// The built-in list. It lives in the app, never in a user's files: only a user's own edits are stored.
    static let defaultList: [String] = [
        // File formats
        "PDF", "ZIP", "PNG", "JPG", "JPEG", "GIF", "SVG", "CSV", "JSON", "XML", "HTML", "CSS", "YAML", "SQL", "MP3", "MP4", "WAV", "DMG",
        // Tech
        "API", "URL", "USB", "SSD", "RAM", "CPU", "GPU", "FAQ", "SDK", "UI",
        // Platforms and products
        "macOS", "iOS", "iPadOS", "iPhone", "iPad", "iCloud", "GitHub", "YouTube", "WhatsApp", "LinkedIn",
        // Keys
        "fn",
    ]

    /// The guards for words that are also ordinary words (see `GlossaryCorrector.ExactRules`). “Zip your jacket”,
    /// “Don't ram the door” and “Ui, das ist schön” stay as they are; “the zip file”, “Zip-Datei” and “RAM-Speicher” are fixed.
    static let rules = GlossaryCorrector.ExactRules(
        ambiguous: ["zip", "ram", "ui"],
        nouns: ["file", "files", "archive", "archives", "folder", "folders", "datei", "dateien", "ordner", "archiv",
                "memory", "speicher", "usage", "design", "designs", "kit", "component", "components", "test", "tests",
                "element", "elemente", "komponente", "komponenten"],
        noGlueAfter: ["in", "on", "at", "to", "of", "the", "a", "an", "it", "you", "me", "my", "is", "and", "or", "for", "no", "so",
                      "der", "die", "das", "und", "oder", "ist", "ein", "eine", "im", "zu", "an", "auf"],
        noGlueBefore: ["i"])

    /// The user's own glossary wins: a spelling the glossary has as a term or a “sounds like” (case and spaces aside) is
    /// not applied, so a glossary entry “zip” keeps “zip” lowercase.
    static func active(_ list: [String], glossary: [GlossaryEntry], language: Lang) -> [String] {
        let taken = Set(glossary.filter { $0.scope.applies(to: language) }
            .flatMap { [$0.term] + $0.soundsLike }.map(TextSimilarity.normalize))
        return list.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !taken.contains(TextSimilarity.normalize($0)) }
    }

    /// Writes every word (and every part of a hyphen compound) that equals a spelling, ignoring case and spaces, exactly
    /// like the spelling: “pdf-Export” is “PDF-Export”, “Mac OS” is “macOS”. It is the glossary's matcher in its exact
    /// mode, so a spelling's own capitals win at the start of a sentence too (see `ContextFormatter`).
    static func apply(_ text: String, list: [String], glossary: [GlossaryEntry], language: Lang) -> String {
        let spellings = active(list, glossary: glossary, language: language)
        guard !spellings.isEmpty else { return text }
        return GlossaryCorrector.correct(text, entries: spellings.map { GlossaryEntry(term: $0) }, language: language,
                                         strength: .normal, matching: .exact(rules))
    }
}
