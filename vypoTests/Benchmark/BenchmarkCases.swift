import Foundation
@testable import vypo

/// One sentence of the glossary benchmark and what counts as right for it.
struct BenchmarkCase: Codable, Equatable {
    enum Kind: String, Codable { case hit, trap, neutral }

    var id: String
    var kind: Kind
    var lang: Lang
    var text: String
    /// hit: glossary terms that must appear exactly.
    var terms: [String] = []
    /// trap: ordinary words that must stay, and terms that must not appear.
    var keep: [String] = []
    var forbid: [String] = []
}

extension BenchmarkCase {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(Kind.self, forKey: .kind)
        lang = try c.decode(Lang.self, forKey: .lang)
        text = try c.decode(String.self, forKey: .text)
        terms = try c.decodeIfPresent([String].self, forKey: .terms) ?? []
        keep = try c.decodeIfPresent([String].self, forKey: .keep) ?? []
        forbid = try c.decodeIfPresent([String].self, forKey: .forbid) ?? []
    }
}

/// The benchmark glossary and sentences from `glossary-cases.json`.
struct BenchmarkSet: Codable {
    struct Term: Codable {
        var term: String
        var soundsLike: [String] = []

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            term = try c.decode(String.self, forKey: .term)
            soundsLike = try c.decodeIfPresent([String].self, forKey: .soundsLike) ?? []
        }
    }

    var glossary: [Term]
    var cases: [BenchmarkCase]

    private final class BundleToken {}

    static func load() throws -> BenchmarkSet {
        guard let url = Bundle(for: BundleToken.self).url(forResource: "glossary-cases", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(BenchmarkSet.self, from: Data(contentsOf: url))
    }

    /// Fixed, distinct creation dates in file order, so the terms come in the same order every run.
    var entries: [GlossaryEntry] {
        glossary.enumerated().map { i, t in
            GlossaryEntry(term: t.term, soundsLike: t.soundsLike, createdAt: Date(timeIntervalSince1970: Double(1_000 - i)))
        }
    }
}
