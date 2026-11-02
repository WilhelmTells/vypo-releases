import Foundation

/// The text vypo pasted, followed through a field while the user edits it. It keeps the pasted text, its latest version,
/// where that is and how long the field was, and nothing else of the field.
///
/// Edits arrive one at a time, so each new value of the field differs from the last in one place: before the segment,
/// after it, or inside it. That keeps the segment's edges exact. A search for similar words could take the word in front
/// of a corrected first word, and a wrong suggestion is worse than a missed one. All positions are UTF-16 offsets, as in
/// Accessibility.
struct TrackedSegment: Equatable, Sendable {
    let pasted: String
    /// The latest version. Stays when the segment is lost, so a chat's Return, which empties the field, doesn't lose it.
    private(set) var text: String
    private(set) var location: Int
    private var fieldLength: Int

    /// Less than this share of the pasted words left: it was rewritten, not corrected.
    private static let minKept = 0.5
    /// Up to this many pasted words no share says anything: correcting one word of one leaves 0 %. Such a paste is followed
    /// through every edit, and `CorrectionFilter` decides at the end whether the result still sounds like it.
    private static let shortPaste = 1...2

    /// Finds the paste in the field: the occurrence nearest before the cursor, else any, else the same words with other
    /// white space (a terminal wraps lines). nil if it isn't there.
    init?(pasted: String, in value: String, caret: Int?) {
        let wanted = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { return nil }
        let field = value as NSString
        var range = NSRange(location: NSNotFound, length: 0)
        if let caret, caret <= field.length {
            range = field.range(of: wanted, options: .backwards, range: NSRange(location: 0, length: caret))
        }
        if range.location == NSNotFound { range = field.range(of: wanted, options: .backwards) }
        if range.location == NSNotFound {
            let words = wanted.split(whereSeparator: \.isWhitespace).map { NSRegularExpression.escapedPattern(for: String($0)) }
            let pattern = words.joined(separator: "\\s+")
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let match = re.matches(in: value, range: NSRange(location: 0, length: field.length)).last else { return nil }
            range = match.range
        }
        self.pasted = wanted
        text = field.substring(with: range)
        location = range.location
        fieldLength = field.length
    }

    /// Takes the field's new value. False if the segment is gone: deleted, rewritten or sent. `text` then stays as it was.
    mutating func update(_ value: String) -> Bool {
        let new = Array(value.utf16)
        let old = Array(text.utf16)
        let shift = new.count - fieldLength
        let newEnd = location + old.count + shift
        // An empty field is a chat's Return, unless its last letter was just deleted from a short paste.
        guard !new.isEmpty || (isShort && old.count <= 1), newEnd >= 0, newEnd <= new.count else { return false }

        var head = 0
        while head < old.count, location + head < new.count, old[head] == new[location + head] { head += 1 }
        var tail = 0
        while tail < old.count, newEnd - tail > 0, old[old.count - 1 - tail] == new[newEnd - 1 - tail] { tail += 1 }

        var start = location, end = newEnd
        if head == old.count {
            // The edit is behind the segment. Letters right at its end continue its last word: “Z”, “Zw”.
            end = location + old.count
            if end < newEnd { end += new[end..<newEnd].prefix(while: Self.isWordCharacter).count }
        } else if head == 0 && tail == old.count {
            // The edit is in front of it. Letters right at its start continue its first word.
            start = newEnd - old.count
            if location < start { start -= new[location..<start].reversed().prefix(while: Self.isWordCharacter).count }
        }
        guard start <= end, end <= new.count else { return false }
        let candidate = String(decoding: new[start..<end], as: UTF16.self)
        guard keepsEnoughOfThePaste(candidate) else { return false }
        text = candidate
        location = start
        fieldLength = new.count
        return true
    }

    private var isShort: Bool { Self.shortPaste.contains(WordDiff.words(pasted).count) }

    private static func isWordCharacter(_ unit: UInt16) -> Bool {
        Unicode.Scalar(unit).map { $0.properties.isAlphabetic || $0.properties.numericType != nil } ?? false
    }

    private func keepsEnoughOfThePaste(_ candidate: String) -> Bool {
        guard !isShort else { return true }
        var left = Dictionary(WordDiff.words(pasted).map { ($0.lowercased(), 1) }, uniquingKeysWith: +)
        let total = left.values.reduce(0, +)
        guard total > 0 else { return false }
        var kept = 0
        for word in WordDiff.words(candidate) {
            let key = word.lowercased()
            if let n = left[key], n > 0 {
                left[key] = n - 1
                kept += 1
            }
        }
        return Double(kept) / Double(total) >= Self.minKept
    }
}
