import FoundationModels
import XCTest
@testable import vypo

/// Trial for writing modes (Apple's on-device model rewriting a dictation): runs real dictations from
/// History through two modes and writes a side-by-side report with timings. Changes nothing in the app.
/// Opt-in: set `VYPO_FM_HISTORY` (via `TEST_RUNNER_VYPO_FM_HISTORY`) to a `history.json` (read only)
/// and `VYPO_FM_REPORT` to the Markdown file to write.
@MainActor
final class WritingModeTrialTests: XCTestCase {
    private struct Mode {
        let name: String
        let instructions: String
    }

    private let modes = [
        Mode(name: "Clean up", instructions: """
            You clean up dictated text. Remove filler words, stutters and false starts. When the speaker \
            corrects themselves, keep only the corrected version. Fix punctuation and grammar. Keep the \
            language, the wording, the meaning and the tone; don't add, summarize or answer anything. \
            Reply with the cleaned text only.
            """),
        Mode(name: "Email", instructions: """
            You turn dictated text into a short, friendly email body. Keep every fact, date and name, and \
            write in the same language as the text. Don't add a subject line, placeholders or a signature. \
            Reply with the email body only.
            """),
    ]

    /// Typical spoken messiness that History may not contain.
    private let examples: [(String, Lang)] = [
        ("Um so can we move the call to uh Tuesday, no wait, Wednesday at like three, and uh bring the the slides please", .en),
        ("Hey Lena I just wanted to say that the report is is basically done, I mean almost done, I'll send it tomorrow morning", .en),
        ("Also ähm wir treffen uns dann am Montag, nein Dienstag, um zehn im Büro und äh bring bitte den Laptop mit", .de),
        ("Kannst du mir vielleicht ähm die Rechnung von letzter Woche schicken, also die vom Kunden aus Hamburg", .de),
    ]

    func testWritingModesOnRealDictations() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let historyPath = env["VYPO_FM_HISTORY"], let reportPath = env["VYPO_FM_REPORT"] else {
            throw XCTSkip("Writing mode trial is opt-in")
        }
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            throw XCTSkip("Apple's on-device model is unavailable: \(model.availability)")
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: historyPath))
        let history = try Store.decoder.decode([HistoryItem].self, from: data)
            .filter { !$0.undone && $0.text.split(separator: " ").count >= 6 }
            .sorted { $0.date > $1.date }
        let picked = Array(history.filter { $0.language == .en }.prefix(8)) + Array(history.filter { $0.language == .de }.prefix(8))
        let inputs = examples + picked.map { ($0.text, $0.language) }

        let clock = ContinuousClock()
        var lines = ["# Writing modes trial", "", "Apple on-device model, one fresh session per text.", ""]
        var times: [String: [Int]] = [:]
        for (text, lang) in inputs {
            lines += ["## \(lang.code): \(text)", ""]
            for mode in modes {
                let session = LanguageModelSession(instructions: mode.instructions)
                let start = clock.now
                let result: String
                do {
                    result = try await session.respond(to: text, options: GenerationOptions(temperature: 0.2)).content
                } catch {
                    result = "⚠️ \(error)"
                }
                let ms = (clock.now - start).milliseconds
                times[mode.name, default: []].append(ms)
                lines += ["- **\(mode.name)** (\(ms) ms): \(result.trimmingCharacters(in: .whitespacesAndNewlines))"]
            }
            lines.append("")
        }

        var summary = ["## Timing", ""]
        for mode in modes {
            let t = (times[mode.name] ?? []).sorted()
            guard !t.isEmpty else { continue }
            summary.append("- \(mode.name): median \(t[t.count / 2]) ms, fastest \(t.first!) ms, slowest \(t.last!) ms (\(t.count) texts)")
        }
        let report = (lines.prefix(4) + summary + [""] + lines.dropFirst(4)).joined(separator: "\n")
        try report.write(toFile: reportPath, atomically: true, encoding: .utf8)
        print("TRIAL\n" + summary.joined(separator: "\n"))
    }
}
