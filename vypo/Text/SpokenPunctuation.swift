import Foundation

/// Turns spoken punctuation into marks, for apps set to Writing (§23.6).
enum SpokenPunctuation {
    enum Mark: Equatable {
        case punct(String)
        case lineBreak(String)
        case openQuote
        case closeQuote
    }

    static func phrases(_ lang: Lang) -> [(words: [String], mark: Mark)] {
        let table: [(String, Mark)]
        switch lang {
        case .en:
            table = [
                ("comma", .punct(",")), ("period", .punct(".")), ("full stop", .punct(".")),
                ("question mark", .punct("?")), ("exclamation mark", .punct("!")), ("exclamation point", .punct("!")),
                ("colon", .punct(":")), ("semicolon", .punct(";")), ("semi colon", .punct(";")), ("semi-colon", .punct(";")),
                ("open quote", .openQuote), ("close quote", .closeQuote),
                ("new line", .lineBreak("\n")), ("new paragraph", .lineBreak("\n\n")),
            ]
        case .de:
            table = [
                ("komma", .punct(",")), ("punkt", .punct(".")), ("fragezeichen", .punct("?")),
                ("ausrufezeichen", .punct("!")), ("doppelpunkt", .punct(":")), ("semikolon", .punct(";")), ("semi-kolon", .punct(";")),
                ("semi kolon", .punct(";")), ("semikolen", .punct(";")),
                ("anführungszeichen auf", .openQuote), ("anführungszeichen zu", .closeQuote),
                ("neue zeile", .lineBreak("\n")), ("neuer absatz", .lineBreak("\n\n")),
            ]
        default:
            table = []
        }
        return table.map { ($0.0.split(separator: " ").map(String.init), $0.1) }
            .sorted { $0.words.count > $1.words.count }
    }

    static func quotes(_ lang: Lang, typographic: Bool) -> (open: String, close: String) {
        lang.quotes(typographic: typographic)
    }

    private enum Item {
        case word(TextWord)
        case mark(Mark)
    }

    /// `terms` are glossary terms and spellings: one written with a lowercase first letter (“macOS”) keeps it at the
    /// start of a sentence.
    static func apply(_ text: String, language: Lang, typographic: Bool = true, terms: Set<String> = []) -> String {
        apply(text, table: phrases(language), language: language, typographic: typographic, terms: terms)
    }

    /// The same with another table (lowercase words, longest first): the Writing entries of Spoken characters.
    static func apply(_ text: String, table: [(words: [String], mark: Mark)], language: Lang, typographic: Bool = true,
                      terms: Set<String> = []) -> String {
        let tokens = Tokenized(text)
        let words = tokens.words
        var items: [Item] = []
        var i = 0
        while i < words.count {
            var matched = false
            for (phrase, mark) in table where i + phrase.count <= words.count {
                let window = words[i..<(i + phrase.count)]
                guard zip(window, phrase).allSatisfy({ $0.core.lowercased() == $1 }) else { continue }
                // “ein wichtiger Punkt”, “the period”: a noun, not a mark.
                if isNoun(words, at: i, language: language) { continue }
                // Leading punctuation of the spoken words stays; trailing punctuation the model added is dropped.
                if let lead = window.first?.lead, !lead.isEmpty {
                    var w = TextWord(Substring(lead)); w.lead = lead; w.core = ""; w.trail = ""
                    items.append(.word(w))
                }
                items.append(.mark(mark))
                i += phrase.count
                matched = true
                break
            }
            if !matched {
                items.append(.word(words[i]))
                i += 1
            }
        }

        let (open, close) = quotes(language, typographic: typographic)
        var out = ""
        var capitalize = false
        var glue = true // no space before the next word
        for item in items {
            switch item {
            case .word(var w):
                if capitalize, !w.core.isEmpty {
                    if !ContextFormatter.startsWithLowercaseTerm(w.core, glossaryTerms: terms) {
                        w.core = FillerRemover.capitalizedFirst(w.core)
                    }
                    capitalize = false
                }
                if !glue && !out.isEmpty { out += " " }
                out += w.text
                glue = false
                if let last = w.trail.last, ".?!".contains(last) { capitalize = true }
            case .mark(.punct(let p)):
                trimTrailingSpaces(&out)
                // Drop a mark the model already put there.
                if let last = out.last, ".,;:!?".contains(last) { out.removeLast() }
                out += p
                glue = false
                if ".?!".contains(p) { capitalize = true }
            case .mark(.lineBreak(let nl)):
                trimTrailingSpaces(&out)
                out += nl
                glue = true
                capitalize = true
            case .mark(.openQuote):
                if !glue && !out.isEmpty { out += " " }
                out += open
                glue = true
            case .mark(.closeQuote):
                trimTrailingSpaces(&out)
                out += close
                glue = false
            }
        }
        return out
    }

    /// Words that can stand between an article and a noun without being an adjective.
    private static let notAdjectives: Set<String> = ["alles", "etwas", "nichts", "vieles", "jetzt", "immer", "schon", "eben", "dann", "noch"]

    /// Inflected German determiners and contractions that `GlossaryCorrector.determiners` doesn't list: “meinen Punkt”, “beim Punkt”.
    private static let moreDeterminers: Set<String> = [
        "meinen", "meinem", "meiner", "meines", "deinen", "deinem", "deiner", "deines", "seine", "seinen", "seinem", "seiner",
        "ihre", "ihren", "ihrem", "ihrer", "sein", "dieser", "diese", "dieses", "diesen", "diesem", "jede", "jeden", "jedes",
        "kein", "keine", "keinen", "keinem", "keiner", "beim", "zum", "zur", "vom", "im", "am", "unterm", "überm", "vorm",
    ]

    /// Whether the spoken word at `i` is used as a noun: an article or possessive (`GlossaryCorrector.determiners`
    /// and `moreDeterminers`; English also “an”) stands right before it, or two words before it with one adjective between
    /// (“ein wichtiger Punkt”). German adjectives are lowercase and inflected (-e -en -er -es -em), English ones
    /// are any lowercase word. Nothing between the words but a space.
    static func isNoun(_ words: [TextWord], at i: Int, language: Lang) -> Bool {
        func determiner(_ w: TextWord) -> Bool {
            w.lead.isEmpty && w.trail.isEmpty && isDeterminer(w.core, language: language)
        }
        guard i > 0 else { return false }
        if determiner(words[i - 1]) { return true }
        guard i > 1, determiner(words[i - 2]) else { return false }
        let a = words[i - 1]
        guard a.lead.isEmpty, a.trail.isEmpty, a.core.count >= 3, a.core.first?.isLowercase == true,
              !notAdjectives.contains(a.core) else { return false }
        if language == .de { return ["e", "en", "er", "es", "em"].contains { a.core.hasSuffix($0) } }
        return true
    }

    /// An article or possessive (`GlossaryCorrector.determiners`; German also `moreDeterminers`, English also “an”).
    static func isDeterminer(_ word: String, language: Lang?) -> Bool {
        let c = word.lowercased()
        return GlossaryCorrector.determiners.contains(c) || (language == .de && moreDeterminers.contains(c))
            || (language == .en && c == "an")
    }

    /// In a Writing app a line break, whoever made it (a spoken “new line” turned into one by the replacements, or
    /// by `apply`), is followed by a capital letter. A term's own spelling wins (“macOS”).
    static func capitalizeAfterLineBreaks(_ text: String, terms: Set<String> = []) -> String {
        let chars = Array(text)
        var out = ""
        var afterBreak = false
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isNewline {
                afterBreak = true
            } else if afterBreak, c.isLetter {
                var j = i
                while j < chars.count, !chars[j].isWhitespace { j += 1 }
                let word = String(chars[i..<j])
                out += ContextFormatter.startsWithLowercaseTerm(word, glossaryTerms: terms) ? String(c) : c.uppercased()
                afterBreak = false
                i += 1
                continue
            } else if afterBreak, !(c == " " || c == "\t" || "„“\"«(['‚‘".contains(c)) {
                afterBreak = false
            }
            out.append(c)
            i += 1
        }
        return out
    }

    private static func trimTrailingSpaces(_ s: inout String) {
        while let last = s.last, last == " " || last == "\t" { s.removeLast() }
    }
}

/// Straight quotes → „…“ / “…”, apostrophes → ’ (§23.6).
enum TypographicQuotes {
    static func apply(_ text: String, language: Lang) -> String {
        let (open, close) = SpokenPunctuation.quotes(language, typographic: true)
        var out = ""
        var prev: Character?
        for ch in text {
            switch ch {
            case "\"":
                // Opening when preceded by the start or whitespace, otherwise closing.
                out += (prev == nil || prev!.isWhitespace) ? open : close
            case "'":
                out += "’"
            default:
                out.append(ch)
            }
            prev = ch
        }
        return out
    }
}
