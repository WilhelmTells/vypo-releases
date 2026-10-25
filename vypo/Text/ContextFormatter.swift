import Foundation

/// What surrounds the insertion point (§23.1).
struct InsertionContext: Equatable, Sendable {
    /// Up to two characters before the cursor ("" at the start of the field).
    var before: String
    /// The character after the cursor, if any.
    var after: Character?
}

/// Smart spacing and capitalization, computed right before pasting (§23.1).
enum ContextFormatter {
    private static let spaceAfter: Set<Character> = [".", ",", ";", ":", "!", "?", ")", "]", "}", "\"", "'", "”", "»"]
    private static let noSpaceAfter: Set<Character> = ["(", "[", "{", "„", "“", "«", "‘"]

    static let germanLowercaseStarters: Set<String> = {
        guard let url = Bundle.main.url(forResource: "GermanLowercaseStarters", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return Set(text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") })
    }()

    /// Returns `text` adjusted to its context; unchanged when the context couldn't be read.
    static func format(_ text: String, context: InsertionContext?, language: Lang, glossaryTerms: Set<String>,
                       germanLowercase: Set<String> = germanLowercaseStarters) -> String {
        guard let context, !text.isEmpty else { return text }
        var result = text
        let prev = context.before.last
        let lastNonSpace = context.before.last { !$0.isWhitespace || $0.isNewline }

        // Trailing period before a letter or digit.
        if let after = context.after, after.isLetter || after.isNumber, result.hasSuffix("."), result.count > 1 {
            result.removeLast()
        }

        // Capitalization.
        let firstWord = String(result.prefix { !$0.isWhitespace })
        let atStart = context.before.isEmpty
        if atStart || prev?.isNewline == true || (lastNonSpace.map { ".!?".contains($0) } ?? false) {
            result = FillerRemover.capitalizedFirst(result)
        } else if let l = lastNonSpace, l.isLetter || l.isNumber || ",;:".contains(l),
                  shouldLowercase(firstWord, language: language, glossaryTerms: glossaryTerms, germanLowercase: germanLowercase) {
            result = lowercasedFirst(result)
        }

        // Leading space.
        if let prev, !prev.isWhitespace, !noSpaceAfter.contains(prev),
           prev.isLetter || prev.isNumber || spaceAfter.contains(prev),
           let first = result.first, first.isLetter || first.isNumber {
            result = " " + result
        }
        return result
    }

    private static func shouldLowercase(_ word: String, language: Lang, glossaryTerms: Set<String>, germanLowercase: Set<String>) -> Bool {
        let bare = word.trimmingCharacters(in: .punctuationCharacters)
        guard let first = bare.first, first.isUppercase else { return false }
        if glossaryTerms.contains(bare) { return false }
        if language == .en && (bare == "I" || bare.hasPrefix("I'") || bare.hasPrefix("I’")) { return false }
        if bare.filter(\.isUppercase).count >= 2 { return false }
        if language == .de && !germanLowercase.contains(bare.lowercased()) { return false }
        return true
    }

    private static func lowercasedFirst(_ s: String) -> String {
        guard let f = s.first else { return s }
        return f.lowercased() + s.dropFirst()
    }
}
