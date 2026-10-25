import AppKit
import PDFKit

/// Finds glossary candidates in a document (§23.10).
@MainActor
struct TermExtractor {
    struct Found: Equatable, Identifiable {
        var term: String
        var count: Int
        var id: String { term }
    }

    static let maxTerms = 200

    /// True if a word is misspelled in both English and German.
    var isUnknownWord: (String) -> Bool = TermExtractor.spellCheckerUnknown

    func extract(from text: String, existing: Set<String>) -> [Found] {
        let tokens = Self.tokens(text)
        var counts: [String: Int] = [:]
        var kindA: Set<String> = []

        var bRun: [String] = []
        func flushRun() {
            if (2...3).contains(bRun.count) {
                counts[bRun.joined(separator: " "), default: 0] += 1
            } else {
                for w in bRun { counts[w, default: 0] += 1 }
            }
            bRun = []
        }

        var previousEnd = text.startIndex
        for (i, token) in tokens.enumerated() {
            let gap = text[previousEnd..<token.range.lowerBound]
            let sentenceStart = i == 0 || gap.contains(where: { ".!?".contains($0) || $0.isNewline })
            let adjacent = i > 0 && gap.allSatisfy { $0 == " " }
            previousEnd = token.range.upperBound
            let word = token.word

            if Self.isCandidateA(word) {
                flushRun()
                kindA.insert(word)
                counts[word, default: 0] += 1
                continue
            }
            let isB = !sentenceStart && Self.isCapitalized(word) && isUnknownWord(word)
            if isB {
                if !adjacent { flushRun() }
                bRun.append(word)
            } else {
                flushRun()
            }
        }
        flushRun()

        return counts
            .filter { term, count in
                term.filter(\.isLetter).count >= 3 && !existing.contains(term) && count >= (kindA.contains(term) ? 1 : 2)
            }
            .map { Found(term: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending }
            .prefix(Self.maxTerms)
            .map { $0 }
    }

    /// Letters (incl. umlauts and ß), digits, and inner "-", ".", "’".
    static func tokens(_ text: String) -> [(word: String, range: Range<String.Index>)] {
        let re = try! NSRegularExpression(pattern: "[\\p{L}\\p{N}]+(?:[-.’'][\\p{L}\\p{N}]+)*")
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { m in
            Range(m.range, in: text).map { (String(text[$0]), $0) }
        }
    }

    /// An uppercase letter after the first character, or letters mixed with digits (SwiftUI, macOS, S4HANA, GPT-4).
    static func isCandidateA(_ w: String) -> Bool {
        let hasLetter = w.contains(where: \.isLetter)
        let hasDigit = w.contains(where: \.isNumber)
        return w.dropFirst().contains(where: \.isUppercase) || (hasLetter && hasDigit)
    }

    static func isCapitalized(_ w: String) -> Bool { w.first?.isUppercase == true }

    @MainActor
    static let spellCheckerUnknown: (String) -> Bool = { word in
        let checker = NSSpellChecker.shared
        func misspelled(_ lang: String) -> Bool {
            let r = checker.checkSpelling(of: word, startingAt: 0, language: lang, wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
            return r.location != NSNotFound
        }
        return misspelled("en") && misspelled("de")
    }

    /// Reads a document as plain text, locally.
    static func text(from url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "pdf":
            return PDFDocument(url: url)?.string
        case "docx":
            return (try? NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML],
                                            documentAttributes: nil))?.string
        default:
            return (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1))
        }
    }
}
