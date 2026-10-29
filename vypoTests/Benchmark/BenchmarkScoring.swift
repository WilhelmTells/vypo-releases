import Foundation
@testable import vypo

/// A: no glossary at all. B: the text correction, as the app runs today.
enum BenchmarkConfig: String, Codable, CaseIterable {
    case none = "A", textOnly = "B"
}

enum BenchmarkScore {
    /// The term as whole word(s), spelled exactly (case-sensitive); any whitespace between its words.
    static func contains(_ output: String, term: String) -> Bool {
        let words = term.split(whereSeparator: \.isWhitespace).map { NSRegularExpression.escapedPattern(for: String($0)) }
        let pattern = "(?<![\\p{L}\\p{N}])" + words.joined(separator: "\\s+") + "(?![\\p{L}\\p{N}])"
        return output.range(of: pattern, options: .regularExpression) != nil
    }

    static func termsRight(_ output: String, terms: [String]) -> Int {
        terms.filter { contains(output, term: $0) }.count
    }

    static func trapSpared(_ output: String, keep: [String], forbid: [String]) -> Bool {
        keep.allSatisfy { contains(output, term: $0) } && !forbid.contains { contains(output, term: $0) }
    }

    /// Word error rate: word-level edit distance over the expected word count, ignoring case and punctuation.
    static func wer(_ output: String, expected: String) -> Double {
        let got = words(output), want = words(expected)
        guard !want.isEmpty else { return got.isEmpty ? 0 : 1 }
        var prev = Array(0...got.count)
        var cur = [Int](repeating: 0, count: got.count + 1)
        for i in 1...want.count {
            cur[0] = i
            for j in 0..<got.count {
                cur[j + 1] = min(prev[j + 1] + 1, cur[j] + 1, prev[j] + (want[i - 1] == got[j] ? 0 : 1))
            }
            swap(&prev, &cur)
        }
        return Double(prev[got.count]) / Double(want.count)
    }

    /// Lowercased words; punctuation at the edges stripped, inner hyphens and apostrophes kept.
    private static func words(_ s: String) -> [String] {
        s.lowercased().split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: .punctuationCharacters.union(.symbols)) }
            .filter { !$0.isEmpty }
    }
}

enum BenchmarkAssign {
    static let minimumSimilarity = 0.5

    /// A take may hold several sentences: split after . ? ! followed by whitespace.
    static func sentences(_ text: String) -> [String] {
        text.replacingOccurrences(of: "([.?!])\\s+", with: "$1\n", options: .regularExpression)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Matches each recording's transcript to the most similar sentence. `recordings` are sorted by name,
    /// which is by time, so a later take of a sentence replaces an earlier one. Returns case id → recording name.
    static func assign(_ recordings: [(name: String, transcript: String)], to cases: [BenchmarkCase]) -> [String: String] {
        let targets = cases.map { ($0.id, TextSimilarity.normalize($0.text)) }
        var result: [String: String] = [:]
        for r in recordings {
            let heard = TextSimilarity.normalize(r.transcript)
            guard !heard.isEmpty,
                  let best = targets.map({ ($0.0, TextSimilarity.similarity(heard, $0.1)) }).max(by: { $0.1 < $1.1 }),
                  best.1 >= minimumSimilarity else { continue }
            result[best.0] = r.name
        }
        return result
    }
}

struct BenchmarkResult: Codable, Equatable {
    var speaker: String
    var caseID: String
    var config: BenchmarkConfig
    var output: String
    var passed: Bool
}

enum BenchmarkDiff {
    /// Cases in config C that passed in one run and not in the other, as "speaker/caseID", sorted.
    static func flips(previous: [BenchmarkResult], current: [BenchmarkResult]) -> (fixed: [String], broken: [String]) {
        func full(_ results: [BenchmarkResult]) -> [String: Bool] {
            Dictionary(results.filter { $0.config == .textOnly }.map { ("\($0.speaker)/\($0.caseID)", $0.passed) },
                       uniquingKeysWith: { _, b in b })
        }
        let before = full(previous), after = full(current)
        let both = after.keys.filter { before[$0] != nil }
        return (both.filter { after[$0]! && !before[$0]! }.sorted(),
                both.filter { !after[$0]! && before[$0]! }.sorted())
    }
}
