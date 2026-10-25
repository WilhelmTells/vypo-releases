import Foundation

/// A well-known text for “About as long as …” on the Stats pane.
struct Work: Sendable {
    var id: String
    var words: Int
    var title: @Sendable () -> String
    /// Only the three biggest may be shown at 0.3…0.5 as “0.4 Bibles so far”.
    var soFar: (@Sendable (String) -> String)?

    init(id: String, words: Int, title: @escaping @Sendable () -> String, soFar: (@Sendable (String) -> String)? = nil) {
        self.id = id
        self.words = words
        self.title = title
        self.soFar = soFar
    }

    /// The works, smallest first. Words are about: the English edition, rounded.
    static let all: [Work] = [
        Work(id: "littlePrince", words: 17_000, title: { String(localized: "The Little Prince") }),
        Work(id: "alice", words: 26_500, title: { String(localized: "Alice’s Adventures in Wonderland") }),
        Work(id: "christmasCarol", words: 29_000, title: { String(localized: "A Christmas Carol") }),
        Work(id: "hamlet", words: 30_000, title: { String(localized: "Hamlet") }),
        Work(id: "animalFarm", words: 30_000, title: { String(localized: "Animal Farm") }),
        Work(id: "gatsby", words: 47_000, title: { String(localized: "The Great Gatsby") }),
        Work(id: "frankenstein", words: 75_000, title: { String(localized: "Frankenstein") }),
        Work(id: "harryPotter1", words: 77_000, title: { String(localized: "Harry Potter and the Philosopher’s Stone") }),
        Work(id: "hobbit", words: 95_000, title: { String(localized: "The Hobbit") }),
        Work(id: "prideAndPrejudice", words: 122_000, title: { String(localized: "Pride and Prejudice") }),
        Work(id: "mobyDick", words: 206_000, title: { String(localized: "Moby-Dick") }),
        Work(id: "lordOfTheRings", words: 480_000, title: { String(localized: "The Lord of the Rings") }),
        Work(id: "warAndPeace", words: 587_000, title: { String(localized: "War and Peace") }),
        Work(id: "bible", words: 783_000, title: { String(localized: "the Bible") },
             soFar: { String(localized: "\($0) Bibles so far.") }),
        Work(id: "shakespeare", words: 880_000, title: { String(localized: "Shakespeare’s complete works") },
             soFar: { String(localized: "\($0) of Shakespeare’s complete works so far.") }),
        Work(id: "harryPotterAll", words: 1_080_000, title: { String(localized: "all seven Harry Potter books") },
             soFar: { String(localized: "\($0) of all seven Harry Potter books so far.") }),
    ]
}

/// What the words so far are compared with.
struct WorkComparison: Equatable {
    enum Kind: Equatable {
        /// f ≥ 2: “3 times over”.
        case timesOver(Int)
        /// 1 ≤ f < 2.
        case longerThan
        /// 0.5 ≤ f < 1.
        case moreThanHalf
        /// 0.3 ≤ f < 0.5, only for the big works: the factor, rounded to one decimal.
        case soFar(Double)
    }

    var workID: String
    var kind: Kind
    /// Without a work: book pages (250 words each).
    var pages: Int?
}

extension StatsMath {
    static let comparisonRange = 0.3...20.0

    /// The works that fit `words`, with the sentence form for each.
    static func comparisonCandidates(words: Int, works: [Work] = Work.all) -> [WorkComparison] {
        works.compactMap { work in
            let f = Double(words) / Double(work.words)
            guard comparisonRange.contains(f) else { return nil }
            if f >= 2 { return WorkComparison(workID: work.id, kind: .timesOver(Int(f))) }
            if f >= 1 { return WorkComparison(workID: work.id, kind: .longerThan) }
            if f >= 0.5 { return WorkComparison(workID: work.id, kind: .moreThanHalf) }
            guard work.soFar != nil else { return nil }
            return WorkComparison(workID: work.id, kind: .soFar((f * 10).rounded() / 10))
        }
    }

    /// One comparison for the Stats pane, drawn when it opens. `previous` is the work shown last time; it is left
    /// out when there is another choice. `pick` returns an index below its argument (random in the app).
    /// Below 500 words nothing; where no work fits yet, book pages.
    static func comparison(words: Int, previous: String? = nil, works: [Work] = Work.all,
                           pick: (Int) -> Int = { Int.random(in: 0..<$0) }) -> WorkComparison? {
        guard words >= 500 else { return nil }
        var candidates = comparisonCandidates(words: words, works: works)
        if candidates.isEmpty { return WorkComparison(workID: "", kind: .longerThan, pages: max(1, words / 250)) }
        if candidates.count > 1 { candidates.removeAll { $0.workID == previous } }
        return candidates[min(max(0, pick(candidates.count)), candidates.count - 1)]
    }

    /// “About as long as 12 book pages.”, “That’s *The Hobbit*, 3 times over.”: the title in italics.
    static func comparisonText(_ c: WorkComparison, works: [Work] = Work.all) -> AttributedString {
        if let pages = c.pages { return AttributedString(String(localized: "About as long as \(pages) book pages.")) }
        guard let work = works.first(where: { $0.id == c.workID }) else { return AttributedString() }
        let title = work.title()
        let line: String
        switch c.kind {
        case .timesOver(let n): line = String(localized: "That’s *\(title)*, \(n) times over.")
        case .longerThan: line = String(localized: "Longer than *\(title)*.")
        case .moreThanHalf: line = String(localized: "More than half of *\(title)*.")
        case .soFar(let f):
            let number = f.formatted(.number.precision(.fractionLength(1)).locale(Formatting.uiLocale))
            line = work.soFar?(number) ?? ""
        }
        return (try? AttributedString(markdown: line, options: .init(interpretedSyntax: .inlineOnly))) ?? AttributedString(line)
    }
}

/// The work shown the last time the Stats pane opened, so the next opening shows another one. Not saved.
@MainActor
enum LastComparison {
    static var workID: String?
}
