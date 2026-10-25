import Foundation
import NaturalLanguage

/// A dictation language: the languages Parakeet Ultra transcribes and `NLLanguageRecognizer` can tell apart.
/// Estonian, Latvian, Lithuanian, Maltese and Slovenian are left out: macOS can't recognize them.
/// The scripts the 20 languages use.
enum WritingScript: Sendable {
    case latin, cyrillic, greek

    /// Whether `scalar` is a letter of this script. Digits, punctuation and emoji belong to none.
    func contains(_ scalar: Unicode.Scalar) -> Bool {
        guard scalar.properties.isAlphabetic else { return false }
        switch scalar.value {
        case 0x0370...0x03FF, 0x1F00...0x1FFF: return self == .greek
        case 0x0400...0x052F, 0x1C80...0x1C8F, 0x2DE0...0x2DFF, 0xA640...0xA69F: return self == .cyrillic
        case 0x0041...0x024F, 0x0250...0x02AF, 0x1E00...0x1EFF, 0x2C60...0x2C7F, 0xA720...0xA7FF, 0xFB00...0xFB06:
            return self == .latin
        default: return false
        }
    }

    /// The script of a letter, or nil for anything else (including scripts vypo has no language for).
    static func of(_ scalar: Unicode.Scalar) -> WritingScript? {
        [WritingScript.latin, .cyrillic, .greek].first { $0.contains(scalar) }
    }
}

enum Lang: String, Codable, CaseIterable, Sendable, Identifiable {
    case bg, cs, da, de, el, en, es, fi, fr, hr, hu, it, nl, pl, pt, ro, ru, sk, sv, uk

    var id: String { rawValue }

    /// "English" / "Englisch", in vypo's own language.
    var name: String {
        let locale = Formatting.uiLocale
        let name = locale.localizedString(forLanguageCode: rawValue) ?? rawValue
        return name.prefix(1).uppercased(with: locale) + name.dropFirst()
    }

    /// "EN" / "DE"
    var code: String { rawValue.uppercased() }

    /// The script the language is written in.
    var script: WritingScript {
        switch self {
        case .bg, .ru, .uk: .cyrillic
        case .el: .greek
        default: .latin
        }
    }

    /// Filler words and spoken punctuation exist only for English and German.
    var hasExtras: Bool { self == .en || self == .de }

    /// Typographic quotes: „…“ in German, “…” in English, the locale's for the others.
    func quotes(typographic: Bool) -> (open: String, close: String) {
        guard typographic else { return ("\"", "\"") }
        switch self {
        case .de: return ("„", "“")
        case .en: return ("“", "”")
        default:
            let locale = Locale(identifier: rawValue)
            return (locale.quotationBeginDelimiter ?? "“", locale.quotationEndDelimiter ?? "”")
        }
    }

    /// The Mac's languages (`Locale.preferredLanguages`) that vypo offers, in order; English if none.
    static func preselection(preferred: [String]) -> [Lang] {
        var result: [Lang] = []
        for id in preferred {
            guard let code = Locale(identifier: id).language.languageCode?.identifier,
                  let lang = Lang(rawValue: code), !result.contains(lang) else { continue }
            result.append(lang)
        }
        return result.isEmpty ? [.en] : result
    }

    /// Close languages the recognizer confuses on short sentences (Russian read as Ukrainian, 2026-10-23).
    /// The guard doesn't block them for each other; detection among the chosen languages is unchanged.
    var neighbours: Set<NLLanguage> {
        switch self {
        case .ru: [.ukrainian, .bulgarian]
        case .uk: [.russian, .bulgarian]
        case .bg: [.russian, .ukrainian]
        case .cs: [.slovak]
        case .sk: [.czech]
        default: []
        }
    }

    var nlLanguage: NLLanguage {
        switch self {
        case .bg: .bulgarian
        case .cs: .czech
        case .da: .danish
        case .de: .german
        case .el: .greek
        case .en: .english
        case .es: .spanish
        case .fi: .finnish
        case .fr: .french
        case .hr: .croatian
        case .hu: .hungarian
        case .it: .italian
        case .nl: .dutch
        case .pl: .polish
        case .pt: .portuguese
        case .ro: .romanian
        case .ru: .russian
        case .sk: .slovak
        case .sv: .swedish
        case .uk: .ukrainian
        }
    }
}
