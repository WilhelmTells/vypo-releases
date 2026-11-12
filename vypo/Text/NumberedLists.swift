import Foundation

/// Writing apps: a dictation that counts items with ordinal words (“erstens … zweitens …”, “first … second …”)
/// becomes a numbered list, one item per line. Rule based, German and English only.
/// See DECISIONS, “0.6.0: numbered lists in Writing apps”.
enum NumberedLists {
    /// The spoken forms per number, as Parakeet writes them. “sechtens” is how it writes “sechstens”, and it writes
    /// “siebentens” as “siebtens” (measured with `OrdinalASRProbeTests`); both spellings are kept.
    static let german: [[String]] = [
        ["erstens"], ["zweitens"], ["drittens"], ["viertens"], ["fünftens"], ["sechstens", "sechtens"],
        ["siebtens", "siebentens"], ["achtens"], ["neuntens"], ["zehntens"],
    ]
    /// “first of all” counts as “first”, so “of all” isn't left in the item.
    static let english: [[String]] = [
        ["first of all", "firstly", "first"], ["secondly", "second"], ["thirdly", "third"], ["fourthly", "fourth"],
        ["fifthly", "fifth"], ["sixthly", "sixth"], ["seventhly", "seventh"], ["eighthly", "eighth"],
        ["ninthly", "ninth"], ["tenthly", "tenth"],
    ]
    /// Words before a plain English ordinal that make it the start of an item (“milk and second eggs”).
    static let englishLeads: Set<String> = ["and", "then"]
    /// Removed from the end of an item when the next ordinal follows them (“Eier und drittens Brot”).
    static let connectors: Set<String> = ["und", "dann", "and", "then"]

    private static func forms(_ language: Lang) -> [[String]]? {
        switch language {
        case .de: german
        case .en: english
        default: nil
        }
    }

    /// Any ordinal as a whole word, then an optional comma or colon. Longer forms first, so “firstly” and “first of
    /// all” win over “first”. Where it may stand is checked in `counts`.
    private static let patterns: [Lang: NSRegularExpression] = {
        var result: [Lang: NSRegularExpression] = [:]
        for language in [Lang.de, .en] {
            let words = forms(language)!.flatMap { $0 }.sorted { $0.count > $1.count }
                .map { NSRegularExpression.escapedPattern(for: $0).replacingOccurrences(of: " ", with: "[ \\t]+") }
            let pattern = "(?<![\\p{L}\\p{N}])(\(words.joined(separator: "|")))(?![\\p{L}\\p{N}])(?:[ \\t]*[,:])?[ \\t]*"
            result[language] = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        }
        return result
    }()

    private struct Ordinal {
        var number: Int
        /// The ordinal with its comma or colon and the spaces after it.
        var range: Range<String.Index>
    }

    /// Where an ordinal counts. German ordinals and the English -ly forms: anywhere. Plain English ordinals (“first”,
    /// “first of all”): at the start of the text, after . ! ? , : or a line break, or after “and” or “then”.
    private static func counts(_ said: String, language: Lang, before: Substring) -> Bool {
        guard language == .en, !said.hasSuffix("ly") else { return true }
        var head = before
        while let last = head.last, last == " " || last == "\t" { head.removeLast() }
        guard let last = head.last else { return true }
        if ".!?,:".contains(last) || last.isNewline { return true }
        let word = head.reversed().prefix { $0.isLetter }
        return englishLeads.contains(String(word.reversed()).lowercased())
    }

    /// `text` as a numbered list, or unchanged if it holds none: at least two ordinals that count, in order from
    /// one. `terms` (glossary terms and spellings) keep a lowercase first letter (“vypo”).
    static func apply(_ text: String, language: Lang, terms: Set<String> = []) -> String {
        guard let forms = forms(language), let regex = patterns[language] else { return text }
        let ordinals: [Ordinal] = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { m in
            guard let range = Range(m.range, in: text), let word = Range(m.range(at: 1), in: text) else { return nil }
            let said = text[word].lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard let index = forms.firstIndex(where: { $0.contains(said) }),
                  counts(said, language: language, before: text[..<range.lowerBound]) else { return nil }
            return Ordinal(number: index + 1, range: range)
        }
        guard let run = firstRun(ordinals) else { return text }

        var items: [String] = []
        for (k, ordinal) in run.enumerated() {
            let isLast = k + 1 == run.count
            let end = isLast ? text.endIndex : run[k + 1].range.lowerBound
            let item = cleanItem(String(text[ordinal.range.upperBound..<end]), beforeNext: !isLast, terms: terms)
            guard !item.isEmpty else { return text }
            items.append("\(k + 1). \(item)")
        }
        var intro = String(text[..<run[0].range.lowerBound])
        // A connector before the first ordinal goes too: “Ich war dort und erstens …” gives “Ich war dort:”.
        dropConnectors(&intro)
        intro = intro.trimmingCharacters(in: .whitespacesAndNewlines)
        if let last = intro.last, !":.!?".contains(last) { intro += ":" }
        let list = items.joined(separator: "\n")
        return intro.isEmpty ? list : intro + "\n" + list
    }

    /// The first ordinals that count one, two, three … without a gap, at least two of them. Ordinals after the run
    /// stay text.
    private static func firstRun(_ ordinals: [Ordinal]) -> [Ordinal]? {
        for (i, start) in ordinals.enumerated() where start.number == 1 {
            var run = [start]
            for next in ordinals[(i + 1)...] {
                guard next.number == run.count + 1 else { break }
                run.append(next)
            }
            if run.count >= 2 { return run }
        }
        return nil
    }

    /// Before the next ordinal: a connector at the end (“und”, “and then”) removed, with a comma before it. Then
    /// trailing , and ; and one trailing period removed; a capital first letter unless a lowercase term starts it.
    private static func cleanItem(_ raw: String, beforeNext: Bool, terms: Set<String>) -> String {
        var item = raw
        trimEnd(&item, removing: ",;")
        if beforeNext { dropConnectors(&item) }
        if item.hasSuffix("."), !item.hasSuffix("..") { item.removeLast() }
        item = item.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstWord = String(item.prefix { !$0.isWhitespace })
        return ContextFormatter.startsWithLowercaseTerm(firstWord, glossaryTerms: terms) ? item : FillerRemover.capitalizedFirst(item)
    }

    /// Connectors at the end (“und”, “and then”) removed, with a comma before them, and trailing , and ;.
    private static func dropConnectors(_ s: inout String) {
        trimEnd(&s, removing: ",;")
        while true {
            let cut = s.lastIndex(where: { $0.isWhitespace || $0 == "," })
            let word = cut.map { s[s.index(after: $0)...] } ?? s[...]
            guard connectors.contains(word.lowercased()) else { return }
            s = cut.map { String(s[..<$0]) } ?? ""
            trimEnd(&s, removing: ",;")
        }
    }

    private static func trimEnd(_ s: inout String, removing marks: String) {
        while let last = s.last, last.isWhitespace || marks.contains(last) { s.removeLast() }
    }

    /// Whether `text` starts with a list made by `apply` (no intro): “1. …” and a line “2. …”. Smart spacing puts it
    /// on a line of its own.
    static func startsWithList(_ text: String) -> Bool {
        text.hasPrefix("1. ") && text.contains("\n2. ")
    }
}
