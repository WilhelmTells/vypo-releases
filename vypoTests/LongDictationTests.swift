@preconcurrency import FluidAudio
import AppKit
import Foundation
import XCTest
@testable import vypo

/// Long dictations through a freshly loaded engine, with the wall time of each. Opt-in, needs the downloaded model:
/// `VYPO_INTEGRATION_DIR` (via `TEST_RUNNER_VYPO_INTEGRATION_DIR`) is a folder holding `Models/parakeet-ultra/parakeet-ultra`,
/// such as `~/Library/Application Support/vypo`; it is only read. Run each configuration in a fresh process.
/// `VYPO_LONG_STEPS`: what to transcribe in order, as `<seconds>` or `<seconds><de|en>` or `pause<seconds>` (default `60de,60en,180de,180en`).
/// `VYPO_LONG_CONCURRENCY`: FluidAudio's parallel chunks (default: what vypo uses).
final class LongDictationTests: XCTestCase {
    private static let english = [
        "The meeting on Monday was moved because half of the team was still travelling back from the conference.",
        "We looked at the numbers again and decided to keep the old pricing for another quarter.",
        "If the new build passes the tests tonight, we can send it to the first users tomorrow morning.",
        "My grandmother used to bake bread every Saturday, and the whole house smelled of it until the evening.",
        "The train to the coast leaves at seven, so we should pack the bags before we go to bed.",
        "Nobody expected the old bridge to hold, but the engineers had done their work remarkably well.",
        "Please remember to water the plants on the balcony while I am away next week.",
        "The library closes early on Fridays, which is a pity, because that is when I have the most time.",
        "After the rain stopped, the children ran outside and jumped in every puddle along the street.",
        "I think the second chapter is too long and the ending comes rather suddenly for most readers.",
        "The doctor said the knee will take six weeks to heal if I stop running for a while.",
        "We found a small restaurant near the harbour that serves the best fish soup I have ever tasted.",
        "The committee will publish its report in the spring, after everyone has had a chance to comment.",
        "When the power went out, we lit a few candles and played cards until it came back.",
        "The new neighbours moved in last month and they have already invited the whole street for dinner.",
        "Learning a language takes years, but the first real conversation makes all the effort worth it.",
        "The mountain road is closed in winter, so the village can only be reached by the valley train.",
        "She translated the whole novel in eight months and still found time to teach two courses.",
        "The cat sat on the windowsill all afternoon and watched the birds in the old apple tree.",
        "Our flight was delayed by three hours, so we walked through the airport and bought far too many magazines.",
    ]
    private static let german = [
        "Die Besprechung am Montag wurde verschoben, weil die Hälfte des Teams noch von der Konferenz zurückreiste.",
        "Wir haben uns die Zahlen noch einmal angesehen und beschlossen, die alten Preise ein weiteres Quartal zu behalten.",
        "Wenn der neue Stand heute Nacht alle Prüfungen besteht, können wir ihn morgen früh an die ersten Nutzer schicken.",
        "Meine Großmutter hat jeden Samstag Brot gebacken, und das ganze Haus duftete bis zum Abend danach.",
        "Der Zug an die Küste fährt um sieben, also sollten wir die Taschen packen, bevor wir ins Bett gehen.",
        "Niemand hatte erwartet, dass die alte Brücke hält, aber die Ingenieure hatten ihre Arbeit erstaunlich gut gemacht.",
        "Bitte denk daran, die Pflanzen auf dem Balkon zu gießen, während ich nächste Woche weg bin.",
        "Die Bibliothek schließt freitags früher, was schade ist, denn genau dann habe ich die meiste Zeit.",
        "Als der Regen aufhörte, rannten die Kinder hinaus und sprangen in jede Pfütze entlang der Straße.",
        "Ich finde das zweite Kapitel zu lang, und das Ende kommt für die meisten Leser ziemlich plötzlich.",
        "Die Ärztin sagte, das Knie brauche sechs Wochen, wenn ich eine Weile mit dem Laufen aufhöre.",
        "Wir haben ein kleines Restaurant am Hafen gefunden, das die beste Fischsuppe serviert, die ich je gegessen habe.",
        "Der Ausschuss veröffentlicht seine Ergebnisse im Frühjahr, nachdem alle Gelegenheit zur Stellungnahme hatten.",
        "Als der Strom ausfiel, zündeten wir ein paar Kerzen an und spielten Karten, bis er wiederkam.",
        "Die neuen Nachbarn sind letzten Monat eingezogen und haben schon die ganze Straße zum Essen eingeladen.",
        "Eine Sprache zu lernen dauert Jahre, aber das erste echte Gespräch macht die ganze Mühe wett.",
        "Die Bergstraße ist im Winter gesperrt, sodass man das Dorf nur mit der Talbahn erreicht.",
        "Sie hat den ganzen Roman in acht Monaten übersetzt und trotzdem noch zwei Kurse unterrichtet.",
        "Die Katze saß den ganzen Nachmittag auf der Fensterbank und beobachtete die Vögel im alten Apfelbaum.",
        "Unser Flug hatte drei Stunden Verspätung, also liefen wir durch den Flughafen und kauften viel zu viele Zeitschriften.",
    ]

    /// Sentences of generated speech with a short pause between them, cut to `seconds`.
    private func speech(seconds: Double, german: Bool) throws -> (samples: [Float], words: Set<String>) {
        let sentences = german ? Self.german : Self.english
        let voice = german ? "Anna" : "Samantha"
        let target = Int(seconds * AudioRecorder.sampleRate)
        let pause = [Float](repeating: 0, count: Int(0.4 * AudioRecorder.sampleRate))
        var samples: [Float] = []
        var words = Set<String>()
        var index = 0
        while samples.count < target {
            let sentence = sentences[index % sentences.count]
            samples += try TestSpeech.say(sentence, voice: voice) + pause
            words.formUnion(Self.words(sentence))
            index += 1
        }
        return (Array(samples.prefix(target)), words)
    }

    private static func words(_ text: String) -> Set<String> {
        Set(text.lowercased().split { !$0.isLetter }.map(String.init))
    }

    func testLongAudio() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["VYPO_INTEGRATION_DIR"] else { throw XCTSkip("Integration tests are opt-in") }
        let models = URL(fileURLWithPath: dir).appendingPathComponent("Models/parakeet-ultra/parakeet-ultra")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: models.path), "no model in \(models.path)")
        let config = env["VYPO_LONG_CONCURRENCY"].flatMap(Int.init).map { ASRConfig(parallelChunkConcurrency: $0) }
        let engine = config.map { ParakeetEngine(directory: models, config: $0) } ?? ParakeetEngine(directory: models)
        let steps = (env["VYPO_LONG_STEPS"] ?? "60de,60en,180de,180en").split(separator: ",").map(String.init)
        print("LONG pid \(getpid()), concurrency \(env["VYPO_LONG_CONCURRENCY"] ?? "vypo's")")

        let clock = ContinuousClock()
        let loadTime = try await clock.measure { try await engine.load() }
        print("LONG load \(loadTime.milliseconds) ms")
        for step in steps {
            if step.hasPrefix("pause") {
                try await Task.sleep(for: .seconds(Int(step.dropFirst(5)) ?? 0))
                continue
            }
            let german = !step.hasSuffix("en")
            let seconds = Double(step.prefix { $0.isNumber }) ?? 60
            let (samples, words) = try speech(seconds: seconds, german: german)
            let started = Date()
            let text = try await clock.measure { try await engine.transcribe(AudioPadding.padded(samples), language: nil) }
            let found = Self.words(text.result)
            let recall = Double(words.intersection(found).count) / Double(words.count)
            print("LONG \(step): \(text.time.milliseconds) ms, words recognised \(Int(recall * 100)) %, \(found.count) distinct, at \(started)")
            if let out = env["VYPO_LONG_OUT"] {
                try text.result.write(toFile: "\(out)-\(step).txt", atomically: true, encoding: .utf8)
            }
            XCTAssertGreaterThan(recall, 0.7, step)
        }
    }

    /// The whole way for a leftover, with the real model: it lands in History and is neither pasted nor counted.
    @MainActor
    func testALeftoverEndsUpInHistoryOnly() async throws {
        guard ProcessInfo.processInfo.environment["VYPO_INTEGRATION_DIR"] != nil else { throw XCTSkip("Integration tests are opt-in") }
        let prefs = Preferences(defaults: UserDefaults(suiteName: "vypo.tests.\(UUID().uuidString)")!)
        let app = AppState(prefs: prefs, store: Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        let coordinator = AppCoordinator(app: app)
        try XCTSkipUnless(coordinator.models.effectiveModel != nil, "the test's model list has no model")
        coordinator.start()
        defer { coordinator.shutdown() }
        let (samples, _) = try speech(seconds: 20, german: true)
        let clipboard = NSPasteboard.general.changeCount
        let words = app.level.xpWords
        let before = app.stats.allTime

        coordinator.dictation.startProcessing(samples, RecordingContext(startedAt: Date()))
        coordinator.dictation.moveProcessingToBackground()
        XCTAssertEqual(coordinator.dictation.phase, .idle)
        let deadline = Date().addingTimeInterval(60)
        while app.history.items.isEmpty, Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }

        XCTAssertEqual(app.history.items.count, 1)
        XCTAssertTrue(app.history.items.first?.text.lowercased().contains("montag") ?? false)
        XCTAssertEqual(NSPasteboard.general.changeCount, clipboard, "the clipboard stays untouched")
        XCTAssertEqual(app.level.xpWords, words)
        XCTAssertEqual(app.stats.allTime, before)
        XCTAssertNil(app.lastDictation)
        XCTAssertNil(coordinator.memory.last)
    }

    /// A long transcription with a short one started while it runs, on one engine (a leftover and the next dictation).
    func testOverlappingTranscriptions() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["VYPO_INTEGRATION_DIR"] else { throw XCTSkip("Integration tests are opt-in") }
        let models = URL(fileURLWithPath: dir).appendingPathComponent("Models/parakeet-ultra/parakeet-ultra")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: models.path), "no model in \(models.path)")
        let config = env["VYPO_LONG_CONCURRENCY"].flatMap(Int.init).map { ASRConfig(parallelChunkConcurrency: $0) }
        let engine = config.map { ParakeetEngine(directory: models, config: $0) } ?? ParakeetEngine(directory: models)
        try await engine.load()
        let long = try speech(seconds: 60, german: true).samples
        let short = try speech(seconds: 5, german: false).samples
        let clock = ContinuousClock()
        for round in 1...3 {
            let start = clock.now
            async let first = engine.transcribe(AudioPadding.padded(long), language: nil)
            try await Task.sleep(for: .milliseconds(200))
            let second = try await engine.transcribe(AudioPadding.padded(short), language: nil)
            let shortTime = clock.now - start
            let longText = try await first
            print("LONG overlap \(round): short ready after \(shortTime.milliseconds) ms, long after \((clock.now - start).milliseconds) ms")
            XCTAssertFalse(second.isEmpty)
            XCTAssertFalse(longText.isEmpty)
        }
    }
}

private extension ContinuousClock {
    /// `measure` with a result.
    func measure<T>(_ work: () async throws -> T) async rethrows -> (result: T, time: Duration) {
        let start = now
        let result = try await work()
        return (result, now - start)
    }
}
