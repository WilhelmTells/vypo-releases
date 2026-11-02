import AppKit

/// Which corrections are worth a glossary suggestion. The glossary is for terms, not for language: “dem” corrected to
/// “den” is grammar, “cooper netties” corrected to “Kubernetes” is a term. The same in History and in apps.
@MainActor
struct CorrectionFilter {
    /// Not an ordinary word in any of the user's languages.
    var isUnknownWord: (String) -> Bool
    var isDictionaryName: (String) -> Bool = CorrectionFilter.dictionaryName
    var isGlossaryTerm: (String) -> Bool

    init(languages: [Lang], isGlossaryTerm: @escaping (String) -> Bool) {
        isUnknownWord = Self.unknownWord(in: languages)
        self.isGlossaryTerm = isGlossaryTerm
    }

    /// The pairs of a correction that may become suggestions. `continuesSentence`: the old text starts inside a sentence
    /// of the field, so its first word isn't at the start of a sentence. Spell checks run only for pairs that got this far.
    func accepted(from old: String, to new: String, continuesSentence: Bool = false) -> [WordDiff.Substitution] {
        WordDiff.suggestionCandidates(from: old, to: new).filter { pair in
            guard pair.new.contains(where: Self.hasLetter), !isGlossaryTerm(pair.term) else { return false }
            if pair.heard != pair.term && pair.heard.lowercased() == pair.term.lowercased() {
                return !Self.startsSentence(wordAt: pair.oldStart, in: old, continuesSentence: continuesSentence)
            }
            return Self.soundsAlike(pair.heard, pair.term) && hasTerm(pair)
        }
    }

    /// The corrected text holds a word that isn't ordinary language. The dictionaries also list many names (“Kubernetes”,
    /// “Kubernetes”), but in the same way many plain German nouns (“Hund”, “Stadt”). So such a word counts only if what vypo
    /// wrote was no single ordinary word: “cooper netties” or “Kubernetis”, but not “Hunt”.
    private func hasTerm(_ pair: WordDiff.Substitution) -> Bool {
        let words = pair.new.filter(Self.hasLetter)
        if words.contains(where: { TermExtractor.isCandidateA($0) || isUnknownWord($0) }) { return true }
        return (pair.old.count > 1 || pair.old.contains(where: isUnknownWord)) && words.contains(where: isDictionaryName)
    }

    private static func hasLetter(_ word: String) -> Bool { word.contains(where: \.isLetter) }

    /// True if the word of `WordDiff.words` at `index` starts the text, or follows a sentence end or a line break.
    static func startsSentence(wordAt index: Int, in text: String, continuesSentence: Bool) -> Bool {
        let tokens = Tokenized(text)
        let kept = tokens.words.indices.filter { !tokens.words[$0].core.isEmpty }
        guard index < kept.count else { return true }
        guard index > 0 else { return !continuesSentence }
        let previous = tokens.words[kept[index - 1]]
        let between = (kept[index - 1]...kept[index]).dropFirst().map { tokens.separators[$0] }.joined()
        return between.contains(where: \.isNewline) || previous.text.last.map { ".!?".contains($0) } == true
    }

    /// Old and new text sound alike or are spelled alike, so the correction fixes a word instead of changing the content.
    nonisolated static func soundsAlike(_ a: String, _ b: String) -> Bool {
        let x = TextSimilarity.normalize(a), y = TextSimilarity.normalize(b)
        if TextSimilarity.similarity(x, y) >= minSimilarity { return true }
        let codeX = DoubleMetaphone.primary(x), codeY = DoubleMetaphone.primary(y)
        return !codeX.isEmpty && !codeY.isEmpty && TextSimilarity.similarity(codeX, codeY) >= minSimilarity
    }

    private nonisolated static let minSimilarity = 0.6

    // MARK: Dictionaries

    /// A word counts as unknown if every dictionary that can tell says so. Several macOS dictionaries accept anything
    /// (Finnish, Czech, Greek and more, measured for the filler words of 0.5.0), so a language counts only after it
    /// rejected nonsense. With none left, English decides.
    static func unknownWord(in languages: [Lang]) -> (String) -> Bool {
        let usable = languages.map(\.rawValue).filter(rejectsNonsense)
        let codes = usable.isEmpty ? ["en"] : usable
        return { word in codes.allSatisfy { misspelled(word, $0) } }
    }

    /// Capitalized, listed in both the English and the German dictionary, and no word in either in lowercase.
    static let dictionaryName: (String) -> Bool = { word in
        let lower = word.lowercased()
        return word != lower && !misspelled(word, "en") && !misspelled(word, "de") && misspelled(lower, "en") && misspelled(lower, "de")
    }

    private static var usable: Set<String> = []

    private static func rejectsNonsense(_ code: String) -> Bool {
        rejectsNonsense(code, usable: &usable, misspelled: misspelled)
    }

    /// Only a yes is kept. macOS ends the idle spell service and starts it again on demand, and a no can be a wrong
    /// answer from that start, which must not cost a language until the app quits. So a no is asked again next time.
    static func rejectsNonsense(_ code: String, usable: inout Set<String>, misspelled: (String, String) -> Bool) -> Bool {
        if usable.contains(code) { return true }
        let result = misspelled("qzxvbnkt", code)
        if result { usable.insert(code) }
        return result
    }

    private static func misspelled(_ word: String, _ code: String) -> Bool {
        NSSpellChecker.shared.checkSpelling(of: word, startingAt: 0, language: code, wrap: false,
                                            inSpellDocumentWithTag: 0, wordCount: nil).location != NSNotFound
    }
}
