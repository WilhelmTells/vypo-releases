import Foundation

/// String comparison helpers for glossary matching (§11.4).
enum TextSimilarity {
    /// Lowercase, letters and digits only, spaces removed.
    static func normalize(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }

    /// 1 − levenshtein / max length, on already normalized strings.
    static func similarity(_ a: String, _ b: String) -> Double {
        let m = max(a.count, b.count)
        guard m > 0 else { return 1 }
        return 1 - Double(levenshtein(a, b)) / Double(m)
    }
}
