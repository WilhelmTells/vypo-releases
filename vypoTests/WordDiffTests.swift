import XCTest
@testable import vypo

final class WordDiffTests: XCTestCase {
    func testOneSubstitution() {
        let subs = WordDiff.suggestionCandidates(from: "on cooper netties today", to: "on Kubernetes today")
        XCTAssertEqual(subs.count, 1)
        XCTAssertEqual(subs.first?.heard, "cooper netties")
        XCTAssertEqual(subs.first?.term, "Kubernetes")
    }

    func testIdenticalTextsHaveNone() {
        XCTAssertTrue(WordDiff.suggestionCandidates(from: "same text here", to: "same text here").isEmpty)
    }

    func testFourWordSubstitutionIsNoSuggestion() {
        let old = "we use one two three four now"
        let new = "we use Kubernetes now"
        XCTAssertEqual(WordDiff.substitutions(from: old, to: new).count, 1)
        XCTAssertTrue(WordDiff.suggestionCandidates(from: old, to: new).isEmpty)
    }

    func testPunctuationOnlyChangeIsIgnored() {
        XCTAssertTrue(WordDiff.suggestionCandidates(from: "see you today", to: "see you today.").isEmpty)
    }
}

@MainActor
final class HistoryStoreTests: XCTestCase {
    func testRetentionPrunes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = HistoryStore(store: Store(directory: dir))
        let now = Date()
        store.add(HistoryItem(date: now.addingTimeInterval(-8 * 86_400), text: "old", rawText: "old", language: .en, modelID: "parakeet-ultra"))
        store.add(HistoryItem(date: now, text: "new", rawText: "new", language: .en, modelID: "parakeet-ultra"))
        store.prune(.forever, now: now)
        XCTAssertEqual(store.items.count, 2)
        store.prune(.days7, now: now)
        XCTAssertEqual(store.items.map(\.text), ["new"])
        try? FileManager.default.removeItem(at: dir)
    }

    func testRemoveDeletesOneItem() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = HistoryStore(store: Store(directory: dir))
        let keep = HistoryItem(date: Date(), text: "keep", rawText: "keep", language: .en, modelID: "parakeet-ultra")
        let drop = HistoryItem(date: Date(), text: "drop", rawText: "drop", language: .en, modelID: "parakeet-ultra")
        store.add(keep)
        store.add(drop)
        store.remove(drop.id)
        XCTAssertEqual(store.items.map(\.text), ["keep"])
        XCTAssertEqual(HistoryStore(store: Store(directory: dir)).items.map(\.text), ["keep"])
        try? FileManager.default.removeItem(at: dir)
    }
}
