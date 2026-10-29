import Foundation

/// A whitespace-separated word with its leading/trailing punctuation split off.
struct TextWord: Equatable {
    var lead: String
    var core: String
    var trail: String

    var text: String { lead + core + trail }

    init(lead: String, core: String, trail: String) {
        self.lead = lead
        self.core = core
        self.trail = trail
    }

    init(_ raw: Substring) {
        let chars = Array(raw)
        var start = 0, end = chars.count
        while start < end, Self.isEdgePunctuation(chars[start]) { start += 1 }
        while end > start, Self.isEdgePunctuation(chars[end - 1]) { end -= 1 }
        lead = String(chars[0..<start])
        core = String(chars[start..<end])
        trail = String(chars[end...])
    }

    static func isEdgePunctuation(_ c: Character) -> Bool {
        c.isPunctuation || c.isSymbol
    }
}

/// Splits text into words and the whitespace between them, so it can be put back together exactly.
struct Tokenized {
    var words: [TextWord]
    /// `separators[i]` precedes `words[i]`; the last one trails the text.
    var separators: [String]
    /// Indices `i` where `words[i - 1]` and `words[i]` are the two sides of a hyphen in one compound
    /// (`separators[i]` is "-"): a glossary term never spans such a boundary.
    var hyphenBreaks: Set<Int> = []

    init(_ text: String) {
        words = []
        separators = []
        var sep = ""
        var word = ""
        for ch in text {
            if ch.isWhitespace {
                if !word.isEmpty { words.append(TextWord(Substring(word))); word = "" }
                sep.append(ch)
            } else {
                if word.isEmpty { separators.append(sep); sep = "" }
                word.append(ch)
            }
        }
        if !word.isEmpty { words.append(TextWord(Substring(word))) }
        separators.append(sep)
    }

    /// The parts of every hyphen compound as words of their own, joined by "-" separators, so a glossary term can
    /// match one part (“Vipo-App”) or several words before the hyphen (“Final Cat-Session”). Punctuation stays at
    /// the ends of the compound; `skip` says which words stay whole (a term that itself holds a hyphen).
    func splittingHyphens(skip: (TextWord) -> Bool) -> Tokenized {
        var out = self
        out.words = []
        out.separators = []
        out.hyphenBreaks = []
        for (i, w) in words.enumerated() {
            let parts = w.core.split(separator: "-", omittingEmptySubsequences: false)
            guard parts.count > 1, !parts.contains(where: \.isEmpty), !skip(w) else {
                out.separators.append(separators[i])
                out.words.append(w)
                continue
            }
            for (k, part) in parts.enumerated() {
                out.separators.append(k == 0 ? separators[i] : "-")
                if k > 0 { out.hyphenBreaks.insert(out.words.count) }
                out.words.append(TextWord(lead: k == 0 ? w.lead : "", core: String(part), trail: k == parts.count - 1 ? w.trail : ""))
            }
        }
        out.separators.append(separators.last ?? "")
        return out
    }

    var text: String {
        var out = ""
        for (i, w) in words.enumerated() { out += separators[i] + w.text }
        return out + (separators.last ?? "")
    }
}

/// Replaces words that sound like glossary terms (§11.4).
enum GlossaryCorrector {
    static let phoneticMinimum = 0.50

    /// How a word is matched against the entries.
    enum Matching {
        /// The glossary: similar spelling and, for words that aren't real words, similar sound.
        case similar
        /// Spellings (abbreviations, file formats): the same letters ignoring case and spaces, nothing fuzzy
        /// (“Mac OS” is “macOS”, “pdf” is “PDF”). See `ExactRules` for the guards.
        case exact(ExactRules)
    }

    /// Guards for exact matching, because the short words of a spelling list are often ordinary words too.
    struct ExactRules {
        /// Spellings (lowercased) that are also ordinary words: “zip”, “ram”, “ui”. They are written by themselves
        /// only before one of `nouns`, or as a part of a hyphen compound (“Zip-Datei”).
        var ambiguous: Set<String>
        var nouns: Set<String>
        /// Words that don't glue to the one before them: “Linked in”, “I phone” stay as they are.
        var noGlueAfter: Set<String>
        /// A window whose first word is one of these is never merged (the pronoun “I” in “I phone you”).
        var noGlueBefore: Set<String>
    }

    private struct Candidate {
        let entry: GlossaryEntry
        let similarity: Double
    }

    /// `isWord` tells ordinary dictionary words. Without the audio to go on, those never take the
    /// sound-alike path: “Vibe” and “vipo” share a code, but “Vibe” is what was said.
    static func correct(_ text: String, entries: [GlossaryEntry], language: Lang, strength: CorrectionStrength,
                        matching: Matching = .similar, isWord: (String) -> Bool = { _ in false }) -> String {
        let entries = entries.filter { $0.scope.applies(to: language) && !$0.term.isEmpty }
        guard !entries.isEmpty, !text.isEmpty else { return text }
        // First the words as they are, then the parts of hyphen compounds: “Vipo-App”, “Final Cat-Session”.
        // A compound that is a term itself (“Stand-up”) stays whole.
        let whole = correct(Tokenized(text), entries: entries, strength: strength, matching: matching, isWord: isWord)
        let terms = Set(entries.map(\.term))
        let compounds = Tokenized(whole).splittingHyphens { terms.contains($0.core) }
        guard !compounds.hyphenBreaks.isEmpty else { return whole }
        return correct(compounds, entries: entries, strength: strength, matching: matching, isWord: isWord)
    }

    /// One pass over `tokens`; `entries` are already filtered for the language.
    private static func correct(_ tokens: Tokenized, entries: [GlossaryEntry], strength: CorrectionStrength,
                                matching: Matching, isWord: (String) -> Bool) -> String {
        var tokens = tokens
        let text = tokens.text

        let prepared = entries.map { e in
            (entry: e,
             term: TextSimilarity.normalize(e.term),
             sounds: e.soundsLike.map(TextSimilarity.normalize).filter { !$0.isEmpty },
             code: DoubleMetaphone.primary(TextSimilarity.normalize(e.term)))
        }

        let words = tokens.words
        let breaks = tokens.hyphenBreaks
        /// A window may not take in both sides of a hyphen.
        func crossesHyphen(_ range: Range<Int>) -> Bool { range.dropFirst().contains { breaks.contains($0) } }

        func isExact(_ range: Range<Int>) -> Bool {
            let exact = words[range].map(\.core).joined(separator: " ")
            return prepared.contains { $0.entry.term == exact }
        }

        /// The best entry for a window, by similarity, then the longer term.
        func bestMatch(_ range: Range<Int>) -> Candidate? {
            let norm = TextSimilarity.normalize(words[range].map(\.core).joined())
            if case .exact(let rules) = matching {
                guard norm.filter(\.isLetter).count >= 2, exactAllowed(range, rules: rules, norm: norm) else { return nil }
                guard let p = prepared.first(where: { $0.term == norm }) else { return nil }
                return Candidate(entry: p.entry, similarity: 1)
            }
            guard norm.filter(\.isLetter).count >= 3 else { return nil }
            let code = strength == .careful ? "" : DoubleMetaphone.primary(norm)
            var best: Candidate?
            for p in prepared {
                var score: Double?
                if p.sounds.contains(norm) {
                    score = 1
                } else {
                    let sim = ([p.term] + p.sounds).map { TextSimilarity.similarity(norm, $0) }.max() ?? 0
                    if sim >= strength.threshold {
                        score = sim
                    } else if strength != .careful, sim >= phoneticMinimum, code == p.code,
                              !words[range].allSatisfy({ isWord($0.core) }) {
                        score = sim
                    }
                }
                guard let score else { continue }
                if let b = best, score < b.similarity || (score == b.similarity && p.entry.term.count <= b.entry.term.count) { continue }
                best = Candidate(entry: p.entry, similarity: score)
            }
            return best
        }

        /// The guards of exact matching: a spelling that is an ordinary word needs a noun after it or a hyphen next to it;
        /// words don't glue across “I” or before a preposition or article.
        func exactAllowed(_ range: Range<Int>, rules: ExactRules, norm: String) -> Bool {
            if range.count > 1 {
                // Never across a full stop or comma: “Mac. Os” is two sentences.
                if range.dropLast().contains(where: { !words[$0].trail.isEmpty }) { return false }
                if rules.noGlueBefore.contains(words[range.lowerBound].core.lowercased()) { return false }
                return !range.dropFirst().contains { rules.noGlueAfter.contains(words[$0].core.lowercased()) }
            }
            guard rules.ambiguous.contains(norm) else { return true }
            let nextToHyphen = breaks.contains(range.upperBound) || breaks.contains(range.lowerBound)
            let next = range.upperBound < words.count ? words[range.upperBound].core.lowercased() : ""
            return nextToHyphen || rules.nouns.contains(next)
        }

        /// “Move the cursor”: a lowercase ordinary word after an article that differs from a term only in case
        /// is a thing, not the name (as in `ParakeetEngine.merge`). “in die Readme” is still corrected.
        func isThingAfterArticle(_ range: Range<Int>, term: String) -> Bool {
            let spoken = words[range].map(\.core).joined(separator: " ")
            guard range.lowerBound > 0, spoken == spoken.lowercased(), spoken != term, spoken == term.lowercased(),
                  words[range].allSatisfy({ isWord($0.core) }) else { return false }
            return determiners.contains(words[range.lowerBound - 1].core.lowercased())
        }

        var consumed = [Bool](repeating: false, count: words.count)
        // Replacements by first word index: (length, new word).
        var replacements: [Int: (Int, TextWord)] = [:]

        for n in [3, 2, 1] where n <= words.count {
            for i in 0...(words.count - n) {
                let range = i..<(i + n)
                if range.contains(where: { consumed[$0] }) || crossesHyphen(range) { continue }
                // Already written exactly like a term: leave it.
                if isExact(range) {
                    for j in range { consumed[j] = true }
                    continue
                }
                guard let best = bestMatch(range) else { continue }
                if case .similar = matching, isThingAfterArticle(range, term: best.entry.term) { continue }
                // A longer window only wins if no window inside it is a term or matches better.
                var beaten = false
                if n > 1 {
                    outer: for m in 1..<n {
                        for k in i...(i + n - m) {
                            let sub = k..<(k + m)
                            if crossesHyphen(sub) { continue }
                            if isExact(sub) || (bestMatch(sub)?.similarity ?? 0) > best.similarity { beaten = true; break outer }
                        }
                    }
                }
                if beaten { continue }
                var word = TextWord(Substring(best.entry.term))
                word.lead = words[i].lead
                word.core = best.entry.term
                word.trail = words[i + n - 1].trail
                replacements[i] = (n, word)
                for j in range { consumed[j] = true }
            }
        }
        guard !replacements.isEmpty else { return text }

        var out: [TextWord] = []
        var seps: [String] = []
        var i = 0
        while i < words.count {
            seps.append(tokens.separators[i])
            if let (n, w) = replacements[i] {
                out.append(w)
                i += n
            } else {
                out.append(words[i])
                i += 1
            }
        }
        seps.append(tokens.separators.last ?? "")
        tokens.words = out
        tokens.separators = seps
        return tokens.text
    }

    /// Articles and possessives, English and German; "an" is left out as it's a German preposition too.
    static let determiners: Set<String> = ["the", "a", "this", "that", "these", "those", "my", "your", "his", "her", "its",
                                            "our", "their", "der", "die", "das", "dem", "den", "des", "ein", "eine", "einen",
                                            "einem", "einer", "eines", "mein", "meine", "dein", "deine", "unser", "unsere"]
}
