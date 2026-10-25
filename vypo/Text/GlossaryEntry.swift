import SwiftUI
import Foundation

/// Which dictations a glossary term applies to. Stored as "all" or a language code, as before the
/// language choice ("all", "en", "de"); an unknown code reads as all.
enum GlossaryScope: Hashable, Codable, Sendable {
    case all
    case only(Lang)

    init(_ lang: Lang) { self = .only(lang) }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Lang(rawValue: raw).map(GlossaryScope.only) ?? .all
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var rawValue: String {
        switch self {
        case .all: "all"
        case .only(let lang): lang.rawValue
        }
    }

    func applies(to lang: Lang) -> Bool { self == .all || self == .only(lang) }

    /// "ALL" / "EN" / "DE"
    var badge: String { rawValue.uppercased() }

    /// The badge in Settings: "All" is translated, language codes aren't.
    var label: LocalizedStringKey {
        switch self {
        case .all: "All"
        case .only(let lang): "\(lang.code)"
        }
    }

    /// The choices in the term sheet: all, each chosen language, and the entry's own scope if its
    /// language isn't chosen any more.
    static func pickerScopes(chosen: [Lang], current: GlossaryScope) -> [GlossaryScope] {
        var scopes = [GlossaryScope.all] + chosen.map(GlossaryScope.only)
        if !scopes.contains(current) { scopes.append(current) }
        return scopes
    }

    /// "All languages" / "French", for the picker.
    var title: String {
        switch self {
        case .all: String(localized: "All languages")
        case .only(let lang): lang.name
        }
    }
}

/// A glossary term (§11.1).
struct GlossaryEntry: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    /// Case-sensitive, written exactly.
    var term: String
    var soundsLike: [String] = []
    var scope: GlossaryScope = .all
    var createdAt = Date()
    /// The set it belongs to (§23.9); nil means General.
    var setID: UUID?
}
