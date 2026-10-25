import XCTest
@testable import vypo

/// “Copy Diagnostics…”: the report's content, the log's evaluation, and that nothing private gets in.
final class DiagnosticsTests: XCTestCase {
    private let app = "/Applications/vypo.app"

    private func entry(_ message: String, type: String = "Default", category: String = "asr", path: String? = nil,
                       subsystem: String = Log.subsystem, time: String = "2026-10-24 20:26:14.298000+0200") -> String {
        let object: [String: Any] = ["messageType": type, "subsystem": subsystem, "category": category, "eventMessage": message,
                                     "timestamp": time, "processImagePath": path ?? app + "/Contents/MacOS/vypo"]
        return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    private let snapshot = DiagnosticsSnapshot(version: "1.0", build: "7", macOS: "Version 27.0 (Build 26A434)", macModel: "Mac15,12",
                                               chip: "Apple M3", memoryBytes: 8 * 1_073_741_824, languages: ["German", "English"],
                                               speechModel: "installed, loaded", glossaryHelper: "installed", microphone: true,
                                               accessibility: false, glossaryTerms: 2, activeGlossaryTerms: 2)

    func testTheLogKeepsOnlyTheAppsOwnTimingsAndErrors() {
        let lines = [
            entry("Dictation timing: audio 28.1 s; ready 1204 ms"),
            entry("Ready to paste 1204 ms after recording ended"),
            entry("Transcription failed: timeout", type: "Error"),
            entry("Capture session error: busy", type: "Fault", category: "audio"),
            entry("Dictation timing: from a test host", path: "/build/x/build.noindex/dd/Build/Products/Debug/vypo.app/Contents/MacOS/vypo"),
            entry("Some other failure", type: "Error", subsystem: "com.fluidinference"),
            "not json",
        ]
        let log = DiagnosticsLog.parse(ndjson: lines.joined(separator: "\n"), appPath: app)
        XCTAssertEqual(log.timings, ["2026-10-24 20:26:14 Dictation timing: audio 28.1 s; ready 1204 ms"])
        XCTAssertEqual(log.errors, ["2026-10-24 20:26:14 [asr] Transcription failed: timeout",
                                    "2026-10-24 20:26:14 [audio] Capture session error: busy"])
        XCTAssertNil(log.unavailable)
    }

    func testOnlyTheLast20Timings() {
        let lines = (1...25).map { entry("Dictation timing: audio \($0).0 s") }
        let log = DiagnosticsLog.parse(ndjson: lines.joined(separator: "\n"), appPath: app)
        XCTAssertEqual(log.timings.count, 20)
        XCTAssertTrue(log.timings.first!.hasSuffix("audio 6.0 s"))
        XCTAssertTrue(log.timings.last!.hasSuffix("audio 25.0 s"))
    }

    func testRedaction() {
        let words = ["Claus", "Claus Code", "Kloot", "dev.warp.Warp-Stable", "Notes"]
        XCTAssertEqual(Diagnostics.redact("Import of /home/anna/Claus Code terms.json failed in Notes", words: words, home: "/home/anna"),
                       "Import of ~/[…] terms.json failed in […]")
        XCTAssertEqual(Diagnostics.redact("kloot and dev.warp.Warp-Stable", words: words, home: "/h"), "[…] and […]")
        // Whole words only.
        XCTAssertEqual(Diagnostics.redact("Footnotes", words: words, home: "/h"), "Footnotes")
        // vypo's own name stays, also as a glossary term.
        XCTAssertEqual(Diagnostics.redact("memory free 48 %, vypo 112 MB", words: ["Vypo", "Waipo"], home: "/h"),
                       "memory free 48 %, vypo 112 MB")
    }

    func testTheReport() {
        let log = DiagnosticsLog(timings: ["t1 Dictation timing: audio 3.0 s"], errors: ["e1 [store] Could not decode glossary for Waipo"])
        let text = Diagnostics.report(snapshot, log: log, redacting: ["Vypo", "Waipo"], now: Date(timeIntervalSince1970: 0), home: "/h")
        for part in ["vypo 1.0 (build 7)", "macOS Version 27.0 (Build 26A434)", "Mac: Mac15,12, Apple M3, 8 GB memory",
                     "Languages: German, English", "Speech model: installed, loaded; glossary helper: installed",
                     "Microphone: granted; Accessibility: not granted", "Glossary: 2 terms, 2 in active sets",
                     "Last 1 dictation timings:", "t1 Dictation timing: audio 3.0 s",
                     "Errors in the last 24 hours: 1", "e1 [store] Could not decode glossary for […]"] {
            XCTAssertTrue(text.contains(part), "missing: \(part)\n\(text)")
        }
        XCTAssertTrue(text.hasPrefix("vypo diagnostics, 1970-01-01"), text)
    }

    func testAnUnreadableLog() {
        let text = Diagnostics.report(snapshot, log: DiagnosticsLog(unavailable: "denied"), redacting: [], now: Date())
        XCTAssertTrue(text.contains("Log unavailable: denied"))
        XCTAssertFalse(text.contains("dictation timings"))
    }

    func testTheMacsModel() {
        XCTAssertNotEqual(Diagnostics.sysctlString("hw.model"), "?")
        XCTAssertTrue(Diagnostics.sysctlString("machdep.cpu.brand_string").hasPrefix("Apple"))
    }

    /// Clicks while a collection runs are ignored; after it, the next one starts.
    @MainActor
    func testOneCollectionAtATime() async throws {
        let run = DiagnosticsRun()
        var started = 0
        var release: CheckedContinuation<Void, Never>?
        XCTAssertTrue(run.start {
            started += 1
            await withCheckedContinuation { release = $0 }
        })
        XCTAssertFalse(run.start { started += 1 })
        XCTAssertTrue(run.isRunning)
        while release == nil { try await Task.sleep(for: .milliseconds(5)) }
        release?.resume()
        while run.isRunning { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(run.start { started += 1 })
        while run.isRunning { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(started, 2)
    }
}
