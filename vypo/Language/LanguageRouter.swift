import Foundation
import NaturalLanguage

/// Which language a dictation was in (§10). One model transcribes every language, so the language is
/// read from the transcript afterwards.
@MainActor
enum LanguageRouter {
    /// The language of `text` among `langs`; `fallback` (the previous dictation's language) when only
    /// one is possible or the text is too short or mixed to tell.
    nonisolated static func detect(_ text: String, among langs: [Lang], fallback: Lang) -> Lang {
        guard langs.count > 1 else { return langs.first ?? fallback }
        guard text.split(whereSeparator: \.isWhitespace).count >= minimumWords else { return fallback }
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = langs.map(\.nlLanguage)
        recognizer.processString(text)
        guard let (best, confidence) = recognizer.languageHypotheses(withMaximum: langs.count).max(by: { $0.value < $1.value }),
              confidence >= minimumConfidence, let lang = langs.first(where: { $0.nlLanguage == best }) else { return fallback }
        return lang
    }

    nonisolated static let minimumConfidence = 0.6

    /// The language for a short or unclear dictation: the previous one if it's still chosen, else the
    /// Mac's first language that's chosen, else the first chosen.
    nonisolated static func fallback(last: Lang?, chosen: [Lang], preferred: [String] = Locale.preferredLanguages) -> Lang {
        if let last, chosen.contains(last) { return last }
        return Lang.preselection(preferred: preferred).first(where: chosen.contains) ?? chosen.first ?? .en
    }

    /// True when `text` is clearly in another language than `langs`, e.g. Danish for a short German
    /// sentence: the model drifted, and pasting it would be wrong. Shorter than `minimumWords` is never
    /// foreign: "Vypo" reads as Czech and "Hi" as Catalan.
    nonisolated static func isForeign(_ text: String, among langs: [Lang]) -> Bool {
        guard text.split(whereSeparator: \.isWhitespace).count >= minimumWords else { return false }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (best, confidence) = recognizer.languageHypotheses(withMaximum: 1).first else { return false }
        return confidence >= foreignConfidence && !langs.contains { $0.nlLanguage == best || $0.neighbours.contains(best) }
    }

    /// A language whose script all of `langs` share, for engines that can filter wrong-script tokens;
    /// nil for mixed scripts (English + Russian) and for none.
    nonisolated static func scriptHint(for langs: [Lang]) -> Lang? {
        guard let first = langs.first, langs.allSatisfy({ $0.script == first.script }) else { return nil }
        return first
    }

    /// True when `text` has letters in a script none of `langs` is written in: Cyrillic "Слэш" for English
    /// and German. Whatever the word count, that is the model drifting. Digits, punctuation and emoji don't count.
    /// Letters of other scripts (Arabic, Han, …) count too: no chosen language writes them.
    nonisolated static func isWrongScript(_ text: String, among langs: [Lang]) -> Bool {
        let scripts = Set(langs.map(\.script))
        return text.unicodeScalars.contains { scalar in
            guard scalar.properties.isAlphabetic else { return false }
            guard let script = WritingScript.of(scalar) else { return true }
            return !scripts.contains(script)
        }
    }

    nonisolated static let foreignConfidence = 0.8
    /// "OK", "Danke schön": too little to tell.
    nonisolated static let minimumWords = 3
}
