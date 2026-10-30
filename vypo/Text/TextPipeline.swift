import Foundation

/// Everything the text cleanup needs to know about a dictation.
struct PipelineContext: Sendable {
    var language: Lang
    var glossary: [GlossaryEntry] = []
    var strength: CorrectionStrength = .normal
    var replacements: [Replacement] = []
    /// The spellings to apply (`Spellings`); empty when the switch is off.
    var spellings: [String] = []
    /// Filler words to remove; empty when "Remove filler words" is off.
    var fillers: [String] = []
    var mode: AppMode = .standard
    /// nil: the Words page before 0.4.0 (`WordsLayout.legacy`), with “Spoken punctuation” in Writing apps. Otherwise
    /// the entries of Spoken characters; empty when its switch is off.
    var spokenCharacters: [SpokenCharacter]?
    /// Writing apps, `legacy` layout only.
    var spokenPunctuation = true
    var typographicQuotes = true
}

/// Cleans up raw transcriptions before pasting (§8, §23.0). Smart spacing happens later, at paste time.
enum TextPipeline {
    /// `isWord` tells ordinary dictionary words, for the glossary pass.
    static func process(_ raw: String, _ ctx: PipelineContext, isWord: (String) -> Bool = { _ in false }) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        if !ctx.fillers.isEmpty {
            text = FillerRemover.remove(text, words: ctx.fillers)
            guard !text.isEmpty else { return "" }
        }
        text = GlossaryCorrector.correct(text, entries: ctx.glossary, language: ctx.language, strength: ctx.strength, isWord: isWord)
        // After the glossary (the user's own terms win over a built-in spelling), before the replacements.
        text = Spellings.apply(text, list: ctx.spellings, glossary: ctx.glossary, language: ctx.language)
        text = Replacements.apply(ctx.replacements, to: text, mode: ctx.mode, language: ctx.language)
        // A term's own spelling wins over a capital at the start of a sentence or line.
        let terms = Set(ctx.glossary.map(\.term)).union(ctx.spellings)
        if let characters = ctx.spokenCharacters, !characters.isEmpty {
            // After the user's own replacements, so theirs win; a word they have an entry for is theirs alone.
            text = SpokenCharacters.apply(SpokenCharacters.without(ctx.replacements, characters), to: text, mode: ctx.mode, language: ctx.language,
                                          typographic: ctx.typographicQuotes, terms: terms)
        }
        guard !text.isEmpty else { return "" }
        if ctx.mode == .writing {
            if ctx.spokenCharacters == nil && ctx.spokenPunctuation {
                // Line breaks (a spoken "new line" became one) stay: each line on its own.
                text = text.components(separatedBy: "\n").map {
                    SpokenPunctuation.apply($0, language: ctx.language, typographic: ctx.typographicQuotes, terms: terms)
                }.joined(separator: "\n")
            }
            if ctx.typographicQuotes {
                text = TypographicQuotes.apply(text, language: ctx.language)
            }
            // A line break from a replacement (“new line”) is not seen by `SpokenPunctuation`: capital after it too.
            text = SpokenPunctuation.capitalizeAfterLineBreaks(text, terms: terms)
        }
        text = ProfileTweaks.apply(text, mode: ctx.mode)
        return text
    }
}

/// Mode-specific changes (§23.5).
enum ProfileTweaks {
    /// Prompt apps: one trailing "." is removed (never "?" or "!").
    static func apply(_ text: String, mode: AppMode) -> String {
        // A lone "." (the word "Punkt" said by itself) stays.
        guard mode == .prompt, text.hasSuffix("."), !text.hasSuffix(".."), !Replacements.isLoneSymbol(text) else { return text }
        return String(text.dropLast())
    }

    /// Whether Return follows the paste: a Prompt app with “Send automatically”, text in a text field, and
    /// never after a lone symbol: “Slash” by itself must not send “/”.
    static func sendsReturn(mode: AppMode, autoEnter: Bool, inTextField: Bool, text: String) -> Bool {
        inTextField && mode == .prompt && autoEnter && !Replacements.isLoneSymbol(text)
    }
}
