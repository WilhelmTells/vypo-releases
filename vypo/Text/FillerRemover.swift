import Foundation

/// Removes filler words like "um" and "äh" (§23.2).
enum FillerRemover {
    /// The built-in list of a language. Only pure hesitation sounds, never a word that is also a real word there, because
    /// removal ignores case (Spanish “em” is out for “EM”).
    /// Croatian stays empty on purpose: its usual filler, “ovaj”, is a real word.
    static func defaultWords(_ lang: Lang) -> [String] {
        switch lang {
        case .bg: ["ъъъ", "ммм"]
        case .cs: ["ehm", "hmm"]
        case .da: ["øh", "øhm", "hmm"]
        case .de: ["äh", "ähm", "ähh", "öhm", "öh", "hm", "hmm", "mhm"]
        case .el: ["εεε", "μμμ"]
        case .en: ["uh", "um", "uhm", "umm", "erm", "er", "ah", "hmm", "mhm"]
        case .es: ["ehm", "mmm"]
        case .fi: ["öö", "hmm"]
        case .fr: ["euh", "heu", "hum"]
        case .hr: []
        case .hu: ["ööö", "öö", "hmm"]
        case .it: ["ehm", "uhm", "mmm"]
        case .nl: ["uh", "uhm", "eh", "ehm"]
        case .pl: ["yyy", "eee", "hmm"]
        case .pt: ["hum", "ahn", "hmm"]
        case .ro: ["ăăă", "ăă", "hmm"]
        case .ru: ["эээ", "ммм"]
        case .sk: ["ehm", "hmm"]
        case .sv: ["öh", "eh", "hmm"]
        case .uk: ["еее", "ммм"]
        }
    }

    /// Whole-word, case-insensitive; one adjacent comma goes with the filler.
    static func remove(_ text: String, words fillers: [String]) -> String {
        let set = Set(fillers.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        guard !set.isEmpty else { return text }
        let tokens = Tokenized(text)
        var out: [TextWord] = []
        var seps: [String] = []
        var capitalizeNext = false
        // A line break before a removed filler moves to the next word.
        var carriedSeparator: String?

        for (i, word) in tokens.words.enumerated() {
            guard set.contains(word.core.lowercased()), !word.core.isEmpty else {
                var w = word
                if capitalizeNext { w.core = capitalizedFirst(w.core); capitalizeNext = false }
                out.append(w)
                seps.append(carriedSeparator ?? tokens.separators[i])
                carriedSeparator = nil
                continue
            }
            // The filler starts a sentence if it's first or follows . ! ? or a line break.
            let prevEndsSentence = out.last.map { $0.trail.last.map { ".!?".contains($0) } ?? false } ?? true
            let startsSentence = out.isEmpty || prevEndsSentence || tokens.separators[i].contains(where: \.isNewline)
            if tokens.separators[i].contains(where: \.isNewline) { carriedSeparator = tokens.separators[i] }
            var trail = word.trail
            if let comma = trail.firstIndex(of: ",") {
                trail.remove(at: comma)
            } else if var last = out.popLast() {
                if let comma = last.trail.lastIndex(of: ",") { last.trail.remove(at: comma) }
                out.append(last)
            }
            // Other punctuation after the filler stays with the previous word.
            if !trail.isEmpty, var last = out.popLast() {
                last.trail += trail
                out.append(last)
            }
            if startsSentence { capitalizeNext = true }
        }
        guard !out.isEmpty else { return "" }

        var result = ""
        for (i, w) in out.enumerated() {
            let sep = i == 0 ? "" : (seps[i].contains(where: \.isNewline) ? seps[i] : " ")
            result += sep + w.text
        }
        let leading = tokens.separators.first ?? ""
        return (leading + result).replacingOccurrences(of: "  ", with: " ")
    }

    static func capitalizedFirst(_ s: String) -> String {
        guard let f = s.first else { return s }
        return f.uppercased() + s.dropFirst()
    }
}
