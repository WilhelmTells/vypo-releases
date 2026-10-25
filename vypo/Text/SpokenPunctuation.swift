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

    static func apply(_ text: String, language: Lang, typographic: Bool = true) -> String {
        let tokens = Tokenized(text)
        let words = tokens.words
        let table = phrases(language)
        var items: [Item] = []
        var i = 0
        while i < words.count {
            var matched = false
            for (phrase, mark) in table where i + phrase.count <= words.count {
                let window = words[i..<(i + phrase.count)]
                guard zip(window, phrase).allSatisfy({ $0.core.lowercased() == $1 }) else { continue }
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
                    w.core = FillerRemover.capitalizedFirst(w.core)
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
