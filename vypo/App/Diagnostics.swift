import Foundation

/// “Copy Diagnostics…” in Settings → About: what helps to look into a problem, for pasting into a
/// message. Never anything dictated, no glossary terms, no app names from the history.
struct DiagnosticsSnapshot: Equatable {
    var version: String
    var build: String
    var macOS: String
    var macModel: String
    var chip: String
    var memoryBytes: UInt64
    var languages: [String]
    var speechModel: String
    var glossaryHelper: String
    var microphone: Bool
    var accessibility: Bool
    var glossaryTerms: Int
    var activeGlossaryTerms: Int
}

/// What the log of the last 24 hours gives: the newest dictation timings and the errors.
struct DiagnosticsLog: Equatable {
    static let maxTimings = 20
    static let maxErrors = 50

    var timings: [String] = []
    var errors: [String] = []
    /// Why the log couldn't be read; nil when it could.
    var unavailable: String?

    /// `log show --style ndjson` output: keeps vypo's own entries from the app at `appPath` (not test hosts
    /// or other copies), the last `maxTimings` timing lines and the last `maxErrors` errors and faults.
    static func parse(ndjson: String, appPath: String) -> DiagnosticsLog {
        var timings: [String] = [], errors: [String] = []
        for line in ndjson.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let entry = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  entry["subsystem"] as? String == Log.subsystem,
                  (entry["processImagePath"] as? String)?.hasPrefix(appPath + "/") == true,
                  let message = entry["eventMessage"] as? String else { continue }
            let time = (entry["timestamp"] as? String).map { String($0.prefix(19)) } ?? "?"
            switch entry["messageType"] as? String {
            case "Error", "Fault":
                errors.append("\(time) [\(entry["category"] as? String ?? "?")] \(message)")
            default:
                if message.hasPrefix("Dictation timing:") { timings.append("\(time) \(message)") }
            }
        }
        return DiagnosticsLog(timings: Array(timings.suffix(maxTimings)), errors: Array(errors.suffix(maxErrors)))
    }

    /// Reads vypo's entries of the last 24 hours (takes a few seconds).
    static func read(appPath: String) async -> DiagnosticsLog {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
            process.arguments = ["show", "--last", "24h", "--style", "ndjson", "--predicate",
                                 "subsystem == \"\(Log.subsystem)\" AND (messageType == error OR messageType == fault "
                                 + "OR eventMessage BEGINSWITH \"Dictation timing\")"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                return parse(ndjson: String(decoding: data, as: UTF8.self), appPath: appPath)
            } catch {
                return DiagnosticsLog(unavailable: error.localizedDescription)
            }
        }.value
    }
}

/// Runs one diagnostics collection at a time: clicks while one runs are ignored.
@MainActor
final class DiagnosticsRun {
    private(set) var isRunning = false

    /// Starts `work` unless one is running; returns whether it started.
    @discardableResult
    func start(_ work: @escaping @MainActor () async -> Void) -> Bool {
        guard !isRunning else { return false }
        isRunning = true
        Task {
            await work()
            isRunning = false
        }
        return true
    }
}

enum Diagnostics {
    /// Replaces each of `words` (glossary terms and their spellings, app names and bundle IDs from the
    /// history) with a placeholder, and the home folder with `~`. Log lines carry no dictated text, but
    /// error messages can hold file names.
    static func redact(_ line: String, words: [String], home: String = NSHomeDirectory()) -> String {
        var line = line.replacingOccurrences(of: home, with: "~")
        // vypo's own name isn't private, even when it's a glossary term (“vypo 112 MB” in the timings).
        let words = Set(words.map { $0.trimmingCharacters(in: .whitespaces) })
            .filter { $0.count >= 2 && $0.lowercased() != "vypo" }
        // Longest first, so “Claus Code” goes before “Claus”.
        for word in words.sorted(by: { $0.count > $1.count }) {
            let pattern = "(?i)(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: word) + "(?![\\p{L}\\p{N}])"
            line = line.replacingOccurrences(of: pattern, with: "[…]", options: .regularExpression)
        }
        return line
    }

    static func report(_ s: DiagnosticsSnapshot, log: DiagnosticsLog, redacting words: [String], now: Date,
                       home: String = NSHomeDirectory()) -> String {
        func yes(_ granted: Bool) -> String { granted ? String(localized: "granted") : String(localized: "not granted") }
        let memory = s.memoryBytes / 1_073_741_824
        var lines = [
            String(localized: "vypo diagnostics, \(now.formatted(.iso8601))"),
            "",
            String(localized: "vypo \(s.version) (build \(s.build))"),
            String(localized: "macOS \(s.macOS)"),
            String(localized: "Mac: \(s.macModel), \(s.chip), \(memory) GB memory"),
            String(localized: "Languages: \(s.languages.joined(separator: ", "))"),
            String(localized: "Speech model: \(s.speechModel); glossary helper: \(s.glossaryHelper)"),
            String(localized: "Microphone: \(yes(s.microphone)); Accessibility: \(yes(s.accessibility))"),
            String(localized: "Glossary: \(s.glossaryTerms) terms, \(s.activeGlossaryTerms) in active sets"),
            "",
        ]
        if let reason = log.unavailable {
            lines.append(String(localized: "Log unavailable: \(reason)"))
        } else {
            // Only the log lines are masked; the lines above are vypo's own.
            lines.append(String(localized: "Last \(log.timings.count) dictation timings:"))
            lines += log.timings.isEmpty ? [String(localized: "(none in the last 24 hours)")]
                : log.timings.map { redact($0, words: words, home: home) }
            lines.append("")
            lines.append(String(localized: "Errors in the last 24 hours: \(log.errors.count)"))
            lines += log.errors.map { redact($0, words: words, home: home) }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func sysctlString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "?" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "?" }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
