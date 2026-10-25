import Foundation

/// Word-level LCS diff between an original and an edited text (§13).
enum WordDiff {
    struct Substitution: Equatable {
        var old: [String]
        var new: [String]

        var heard: String { old.joined(separator: " ") }
        var term: String { new.joined(separator: " ") }
    }

    /// Words with surrounding punctuation removed (case kept).
    static func words(_ text: String) -> [String] {
        Tokenized(text).words.map(\.core).filter { !$0.isEmpty }
    }

    /// Blocks where old words were replaced by new words (pure insertions/deletions are ignored).
    static func substitutions(from old: String, to new: String) -> [Substitution] {
        let a = words(old), b = words(new)
        let n = a.count, m = b.count
        var lcs = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        if n > 0 && m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
                }
            }
        }
        var result: [Substitution] = []
        var removed: [String] = [], added: [String] = []
        func flush() {
            if !removed.isEmpty && !added.isEmpty { result.append(Substitution(old: removed, new: added)) }
            removed = []; added = []
        }
        var i = 0, j = 0
        while i < n || j < m {
            if i < n, j < m, a[i] == b[j] {
                flush()
                i += 1; j += 1
            } else if j < m, i == n || lcs[i][j + 1] >= lcs[i + 1][j] {
                added.append(b[j]); j += 1
            } else {
                removed.append(a[i]); i += 1
            }
        }
        flush()
        return result
    }

    /// Substitutions of 1–3 words by 1–3 words, the ones that become glossary suggestions.
    static func suggestionCandidates(from old: String, to new: String) -> [Substitution] {
        substitutions(from: old, to: new).filter { (1...3).contains($0.old.count) && (1...3).contains($0.new.count) }
    }
}
