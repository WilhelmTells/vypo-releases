import XCTest
@testable import vypo

/// Runs the benchmark sentences through the real pipeline in three configurations. Opt-in: `TEST_RUNNER_VYPO_BENCHMARK=1`.
/// Uses the installed Parakeet Ultra; recordings come from Debug → Keep recordings for benchmark (Debug builds only).
/// Never fails on scores, only on errors.
@MainActor
final class GlossaryBenchmarkTests: XCTestCase {
    private let languages: [Lang] = [.en, .de]
    /// What the benchmark writes (report, `say` cache, results) goes to a scratch folder, never to the owner's data:
    /// `VYPO_BENCHMARK_OUT` (the script sets it to `build.noindex/benchmark`), else the test run's own folder.
    private var root: URL {
        ProcessInfo.processInfo.environment["VYPO_BENCHMARK_OUT"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? RunEnvironment.testDirectory.appendingPathComponent("Benchmark", isDirectory: true)
    }
    /// The owner's recordings are only read, from their real place.
    private var recordingsDirectory: URL {
        RunEnvironment.realDirectory.appendingPathComponent("Benchmark/recordings", isDirectory: true)
    }
    /// The report, also written to `root/last-report.txt`: FluidAudio's logs interleave with stdout.
    private var lines: [String] = []
    /// Per speaker and take: audio seconds and the transcription time.
    private var timings: [String: [(audio: Double, decode: Duration)]] = [:]
    private var speaker = ""

    private func log(_ line: String) {
        print(line)
        lines.append(line)
    }

    func testGlossaryBenchmark() async throws {
        guard ProcessInfo.processInfo.environment["VYPO_BENCHMARK"] != nil else { throw XCTSkip("Benchmark is opt-in") }
        let models = ModelManager(store: .shared)
        guard models.isInstalled(.parakeetUltra) else {
            throw XCTSkip("Install Parakeet Ultra in vypo first; the benchmark uses the installed model")
        }
        let engines = EngineManager(models: models)
        let engine = try XCTUnwrap(engines.engine(for: .parakeetUltra))
        try await engine.load()
        let set = try BenchmarkSet.load()
        let start = Date()
        defer { try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); try? lines.joined(separator: "\n").appending("\n").write(to: root.appendingPathComponent("last-report.txt"), atomically: true, encoding: .utf8) }

        var results: [BenchmarkResult] = []
        var wers: [String: [BenchmarkConfig: [Double]]] = [:]
        speaker = "owner"
        let owner = try await ownerOutputs(set, engine)
        speaker = "say"
        let say = try await sayOutputs(set, engine)
        for (speaker, byCase) in [("owner", owner), ("say", say)] {
            guard !byCase.isEmpty else { log("\n\(speaker): no recordings"); continue }
            for c in set.cases {
                guard let outputs = byCase[c.id] else { continue }
                for config in BenchmarkConfig.allCases {
                    let out = outputs[config]!
                    let passed = switch c.kind {
                    case .hit: BenchmarkScore.termsRight(out, terms: c.terms) == c.terms.count
                    case .trap: BenchmarkScore.trapSpared(out, keep: c.keep, forbid: c.forbid)
                    case .neutral: out == outputs[.none]
                    }
                    results.append(BenchmarkResult(speaker: speaker, caseID: c.id, config: config, output: out, passed: passed))
                    wers["\(speaker)/\(c.lang.rawValue)", default: [:]][config, default: []].append(BenchmarkScore.wer(out, expected: c.text))
                }
            }
            report(speaker, set, results, wers)
        }
        log(String(format: "\nTime: %.0f s", Date().timeIntervalSince(start)))
        try save(results)
        await engines.unload(.parakeetUltra)
    }

    // MARK: Pipeline

    /// VYPO_BENCHMARK_HINT=1 passes the script hint the app gives for English and German (`LanguageRouter.scriptHint`),
    /// to compare transcripts and decode time with and without it.
    private var hint: Lang? {
        ProcessInfo.processInfo.environment["VYPO_BENCHMARK_HINT"] != nil ? LanguageRouter.scriptHint(for: languages) : nil
    }

    /// Mirrors `AppCoordinator.transcribeAndInsert`: padding, language detection, `TextPipeline`
    /// with the default filler words. Not mirrored: the foreign-language guard, the previous dictation's language
    /// as fallback (the sentence's own is used), replacements and smart spacing. A and B share one transcript.
    private func outputs(_ samples: [Float], lang: Lang, entries: [GlossaryEntry],
                         engine: any ASREngine) async throws -> [BenchmarkConfig: String] {
        let padded = AudioPadding.padded(samples)
        let plain = try await engine.transcribe(padded, language: hint)
        if let timing = await engine.lastTiming {
            timings[speaker, default: []].append((Double(padded.count) / AudioRecorder.sampleRate, timing.decode))
        }
        return [.none: process(plain, fallback: lang, glossary: []),
                .textOnly: process(plain, fallback: lang, glossary: entries)]
    }

    private func process(_ raw: String, fallback: Lang, glossary: [GlossaryEntry]) -> String {
        let language = LanguageRouter.detect(raw, among: languages, fallback: fallback)
        // Configuration A has no glossary and no spellings; B has both, as the app runs.
        let ctx = BenchmarkFiles.context(language: language, glossary: glossary, spellings: glossary.isEmpty ? [] : Spellings.defaultList)
        return TextPipeline.process(raw, ctx) { word in MainActor.assumeIsolated { !TermExtractor.spellCheckerUnknown(word) } }
    }

    // MARK: Speakers

    /// The owner's takes. A take may hold several sentences: it runs through the pipeline as a whole,
    /// as the app would, and each configuration's output is split into sentences, which are matched
    /// to the cases by config A's text. Returns case id → output per configuration.
    private func ownerOutputs(_ set: BenchmarkSet, _ engine: any ASREngine) async throws -> [String: [BenchmarkConfig: String]] {
        let files = BenchmarkFiles.recordings(in: recordingsDirectory)
        for name in files.unreadable { log("  unreadable \(name)") }
        guard !files.read.isEmpty else { return [:] }
        var parts: [String: [BenchmarkConfig: String]] = [:]
        var heard: [(name: String, transcript: String)] = []
        for (name, samples) in files.read {
            let outputs = try await outputs(samples, lang: .de, entries: set.entries, engine: engine)
            let split = outputs.mapValues(BenchmarkAssign.sentences)
            let counts = Set(split.values.map(\.count))
            guard counts.count == 1, let n = counts.first else {
                log("  \(name): sentence count differs between configurations, skipped")
                continue
            }
            for i in 0..<n {
                let key = "\(name)#\(i + 1)"
                parts[key] = split.mapValues { $0[i] }
                heard.append((key, split[.none]![i]))
            }
        }
        let assigned = BenchmarkAssign.assign(heard, to: set.cases)
        log("\nowner: \(files.read.count) recordings, \(heard.count) sentences")
        for c in set.cases {
            if let key = assigned[c.id] { log("  \(c.id) ← \(key)") } else { log("  \(c.id) — missing") }
        }
        let used = Set(assigned.values)
        for h in heard where !used.contains(h.name) { log("  unassigned \(h.name): \(h.transcript)") }
        return assigned.compactMapValues { parts[$0] }
    }

    /// `say` speech (Anna for German, Samantha for English), cached in Benchmark/say, one sentence per file.
    private func sayOutputs(_ set: BenchmarkSet, _ engine: any ASREngine) async throws -> [String: [BenchmarkConfig: String]] {
        let dir = root.appendingPathComponent("say", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var result: [String: [BenchmarkConfig: String]] = [:]
        for c in set.cases {
            let url = dir.appendingPathComponent(c.id + ".wav")
            var samples = (try? WAVFile.read(url)) ?? []
            if samples.isEmpty {
                samples = try TestSpeech.say(c.text, voice: c.lang == .de ? "Anna" : "Samantha")
                try WAVFile.write(samples, to: url)
            }
            result[c.id] = try await outputs(samples, lang: c.lang, entries: set.entries, engine: engine)
        }
        return result
    }

    // MARK: Report

    private func report(_ speaker: String, _ set: BenchmarkSet, _ results: [BenchmarkResult],
                        _ wers: [String: [BenchmarkConfig: [Double]]]) {
        let mine = results.filter { $0.speaker == speaker }
        let byID = Dictionary(set.cases.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func cell(_ config: BenchmarkConfig, _ lang: Lang?, _ kind: BenchmarkCase.Kind) -> String {
            let rows = mine.filter { $0.config == config && byID[$0.caseID]?.kind == kind && (lang == nil || byID[$0.caseID]?.lang == lang) }
            if kind == .hit {
                let right = rows.reduce(0) { $0 + BenchmarkScore.termsRight($1.output, terms: byID[$1.caseID]!.terms) }
                let all = rows.reduce(0) { $0 + byID[$1.caseID]!.terms.count }
                return "\(right)/\(all)"
            }
            return "\(rows.filter(\.passed).count)/\(rows.count)"
        }
        func line(_ label: String, _ value: (BenchmarkConfig) -> String) {
            log(label.padding(toLength: 20, withPad: " ", startingAt: 0)
                  + BenchmarkConfig.allCases.map { value($0).padding(toLength: 10, withPad: " ", startingAt: 0) }.joined())
        }
        log("\n" + speaker.padding(toLength: 20, withPad: " ", startingAt: 0) + "A none    B text")
        line("terms right DE") { cell($0, .de, .hit) }
        line("terms right EN") { cell($0, .en, .hit) }
        line("traps spared") { cell($0, nil, .trap) }
        line("neutral unchanged") { cell($0, nil, .neutral) }
        for lang in languages {
            line("WER \(lang.code)") { config in
                let w = wers["\(speaker)/\(lang.rawValue)"]?[config] ?? []
                return w.isEmpty ? "–" : String(format: "%.1f%%", 100 * w.reduce(0, +) / Double(w.count))
            }
        }
        if let t = timings[speaker], !t.isEmpty {
            func ms(_ d: [Duration]) -> String {
                let v = d.map(\.milliseconds).sorted()
                return "mean \(v.reduce(0, +) / v.count) ms, median \(v[v.count / 2]) ms"
            }
            let audio = t.map(\.audio).reduce(0, +) / Double(t.count)
            log(String(format: "time per take (%d takes, audio mean %.1f s):", t.count, audio))
            log("  transcription     " + ms(t.map(\.decode)))
        }
        for r in mine where r.config == .textOnly && !r.passed {
            log("  ✗ \(r.caseID)  expected: \(byID[r.caseID]!.text)  got: \(r.output)")
        }
    }

    private func save(_ results: [BenchmarkResult]) throws {
        let dir = root.appendingPathComponent("results", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let previous = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .max { $0.lastPathComponent < $1.lastPathComponent }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        let url = dir.appendingPathComponent(f.string(from: Date()) + ".json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(results).write(to: url)
        log("\nSaved \(url.path)")
        guard let previous, let old = try? JSONDecoder().decode([BenchmarkResult].self, from: Data(contentsOf: previous)) else {
            log("First run, nothing to compare")
            return
        }
        let d = BenchmarkDiff.flips(previous: old, current: results)
        log("Compared with \(previous.lastPathComponent): fixed \(d.fixed.isEmpty ? "none" : d.fixed.joined(separator: ", ")); "
              + "broken \(d.broken.isEmpty ? "none" : d.broken.joined(separator: ", "))")
    }
}
