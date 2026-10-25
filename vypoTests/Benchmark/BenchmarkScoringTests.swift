import XCTest
@testable import vypo

final class BenchmarkScoringTests: XCTestCase {
    func testTermMatchingIsWholeWordAndCaseSensitive() {
        XCTAssertTrue(BenchmarkScore.contains("Ich hab das mit Claus Code gebaut.", term: "Claus Code"))
        XCTAssertTrue(BenchmarkScore.contains("Das Stand-up ist um zehn.", term: "Stand-up"))
        XCTAssertFalse(BenchmarkScore.contains("Claudia kommt später.", term: "Claus"))
        XCTAssertFalse(BenchmarkScore.contains("move the cursor", term: "Cursor"))
        XCTAssertTrue(BenchmarkScore.contains("Claus  Code", term: "Claus Code"))
    }

    func testTermsRightCountsEachTerm() {
        XCTAssertEqual(BenchmarkScore.termsRight("Das Backlog in Dschira vor der Retro.", terms: ["Backlog", "Jira", "Retro"]), 2)
    }

    func testTrapSpared() {
        XCTAssertTrue(BenchmarkScore.trapSpared("Ich glaube, das klappt.", keep: ["glaube"], forbid: ["Claus"]))
        XCTAssertFalse(BenchmarkScore.trapSpared("Ich Claus, das klappt.", keep: ["glaube"], forbid: ["Claus"]))
        XCTAssertFalse(BenchmarkScore.trapSpared("Move the Cursor to the end.", keep: ["cursor"], forbid: ["Cursor"]))
    }

    func testWERIgnoresCaseAndPunctuation() {
        XCTAssertEqual(BenchmarkScore.wer("ich gehe heute einkaufen", expected: "Ich gehe heute einkaufen."), 0)
        XCTAssertEqual(BenchmarkScore.wer("ich gehe einkaufen", expected: "Ich gehe heute einkaufen."), 0.25, accuracy: 1e-9)
        XCTAssertEqual(BenchmarkScore.wer("Das Stand-up ist um zehn", expected: "Das Stand-up ist um zehn."), 0)
    }

    func testNewestRecordingWins() {
        let cases = [BenchmarkCase(id: "a", kind: .neutral, lang: .de, text: "Ich gehe heute Abend noch einkaufen.")]
        let r = BenchmarkAssign.assign([("20261023-100000-000", "ich gehe heute abend noch einkaufen"),
                                        ("20261023-100500-000", "ich gehe heute abend einkaufen")], to: cases)
        XCTAssertEqual(r["a"], "20261023-100500-000")
    }

    func testEmptyAndUnrelatedTranscriptsAreIgnored() {
        let cases = [BenchmarkCase(id: "a", kind: .neutral, lang: .en, text: "I'll call you back after lunch.")]
        XCTAssertTrue(BenchmarkAssign.assign([("x", ""), ("y", "the weather in Berlin is lovely today")], to: cases).isEmpty)
    }

    func testSimilarSentencesGoToTheRightCase() {
        let cases = [BenchmarkCase(id: "de", kind: .hit, lang: .de, text: "Öffne das Projekt in Xcode und bau es neu.", terms: ["Xcode"]),
                     BenchmarkCase(id: "en", kind: .hit, lang: .en, text: "Open the project in Xcode and run the tests.", terms: ["Xcode"])]
        let r = BenchmarkAssign.assign([("1", "open the project in x code and run the tests")], to: cases)
        XCTAssertEqual(r, ["en": "1"])
    }

    func testDiffListsFixedAndBroken() {
        let prev = [BenchmarkResult(speaker: "owner", caseID: "a", config: .full, output: "", passed: false),
                    BenchmarkResult(speaker: "owner", caseID: "b", config: .full, output: "", passed: true)]
        let cur = [BenchmarkResult(speaker: "owner", caseID: "a", config: .full, output: "", passed: true),
                   BenchmarkResult(speaker: "owner", caseID: "b", config: .full, output: "", passed: false),
                   BenchmarkResult(speaker: "owner", caseID: "b", config: .none, output: "", passed: true)]
        let d = BenchmarkDiff.flips(previous: prev, current: cur)
        XCTAssertEqual(d.fixed, ["owner/a"])
        XCTAssertEqual(d.broken, ["owner/b"])
    }

    func testDiffWithoutPreviousIsEmpty() {
        let d = BenchmarkDiff.flips(previous: [], current: [BenchmarkResult(speaker: "owner", caseID: "a", config: .full, output: "", passed: true)])
        XCTAssertTrue(d.fixed.isEmpty && d.broken.isEmpty)
    }
}

final class BenchmarkInputTests: XCTestCase {
    func testUnreadableRecordingIsSkippedNotFatal() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try XCTUnwrap(BenchmarkRecordings.keep([0.1, 0.2], at: Date(timeIntervalSince1970: 0), in: dir))
        try Data("not audio".utf8).write(to: dir.appendingPathComponent("zz-broken.wav"))
        let r = BenchmarkFiles.recordings(in: dir)
        XCTAssertEqual(r.read.count, 1)
        XCTAssertEqual(r.unreadable, ["zz-broken.wav"])
    }

    func testMissingFolderHasNoRecordings() {
        let r = BenchmarkFiles.recordings(in: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)"))
        XCTAssertTrue(r.read.isEmpty && r.unreadable.isEmpty)
    }

    func testPipelineRemovesFillersLikeTheAppDefault() {
        let ctx = BenchmarkFiles.context(language: .de, glossary: [])
        XCTAssertEqual(ctx.fillers, FillerRemover.defaultWords(.de))
        XCTAssertFalse(TextPipeline.process("Äh, ich gehe heute einkaufen.", ctx).lowercased().contains("äh"))
    }
}

final class BenchmarkSentenceTests: XCTestCase {
    func testSplitsATakeIntoSentences() {
        XCTAssertEqual(BenchmarkAssign.sentences("Das Stand-up ist heute um 10. Wir schätzen das in Storypoints, nicht in Stunden. Can you update the README before the demo?"),
                       ["Das Stand-up ist heute um 10.", "Wir schätzen das in Storypoints, nicht in Stunden.", "Can you update the README before the demo?"])
        XCTAssertEqual(BenchmarkAssign.sentences("  Ich gehe einkaufen  "), ["Ich gehe einkaufen"])
        XCTAssertEqual(BenchmarkAssign.sentences(""), [])
    }

    func testSentencesOfOneTakeGoToTheirCases() {
        let cases = [BenchmarkCase(id: "jura", kind: .trap, lang: .de, text: "Sie studiert Jura in Hamburg.", keep: ["Jura"], forbid: ["Jira"]),
                     BenchmarkCase(id: "lunch", kind: .neutral, lang: .en, text: "I'll call you back after lunch.")]
        let take = "Sie studiert Jura in Hamburg. I'll call you back after lunch."
        let parts = BenchmarkAssign.sentences(take).enumerated().map { ("take#\($0.offset)", $0.element) }
        XCTAssertEqual(BenchmarkAssign.assign(parts, to: cases), ["jura": "take#0", "lunch": "take#1"])
    }
}
