@preconcurrency import FluidAudio
import Foundation
import XCTest
@testable import vypo

/// What Parakeet writes for spoken ordinals (“erstens”, “first”), for `NumberedLists`. Opt-in, needs the downloaded
/// model: `VYPO_INTEGRATION_DIR` (via `TEST_RUNNER_VYPO_INTEGRATION_DIR`) is a folder holding
/// `Models/parakeet-ultra/parakeet-ultra`, such as `~/Library/Application Support/vypo`; it is only read.
/// Prints `ORDINAL <voice> | <said> | <raw> | <Writing app result>` per sentence. `say` voices only.
final class OrdinalASRProbeTests: XCTestCase {
    private static let german = [
        "Für den Einkauf brauche ich erstens Milch, zweitens Eier und drittens Brot.",
        "Erstens, wir müssen pünktlich sein. Zweitens, wir bringen Kuchen mit.",
        "Erstens Milch. Zweitens Eier. Drittens Brot. Viertens Butter.",
        "Fünftens Käse, sechstens Äpfel, siebtens Nudeln, achtens Reis, neuntens Tee, zehntens Kaffee.",
        "Siebentens Honig.",
        "Ich war zum zweiten Mal dort und erstens war es zu laut.",
        // Follow-up 12.11.: natural sentences.
        "Ich brauche erstens Milch, zweitens Eier und drittens Brot.",
        "Für den Ausflug brauchen wir erstens Wasser, zweitens Brote und drittens eine Karte.",
        "Heute muss ich erstens einkaufen, zweitens die Wohnung putzen und drittens meine Mutter anrufen.",
        "Das war erstens zu teuer und zweitens zu laut.",
        "Das war erstens zu teuer.",
        "Erstens Milch, dann zweitens Eier und dann drittens Brot.",
    ]
    private static let english = [
        "For the trip I need first sunscreen, second a hat, and third some water.",
        "Firstly, we start early. Secondly, we bring lunch. Thirdly, we leave by six.",
        "First milk. Second eggs. Third bread. Fourth butter.",
        "Fifth cheese, sixth apples, seventh pasta, eighth rice, ninth tea, tenth coffee.",
        "Fourthly, fifthly, sixthly, seventhly, eighthly, ninthly, tenthly.",
        "The second time I went there, first of all it was too loud.",
        // Follow-up 12.11.: natural sentences.
        "I need firstly milk, secondly eggs and thirdly bread.",
        "First milk, then second eggs and third bread.",
        "Firstly, the price is too high, and secondly, the room is too small.",
        "For the trip we need first water and second a map.",
        "Today I have to first go shopping, then second clean the flat and third call my mother.",
        "The first time and the second time I went there, it was too loud.",
    ]

    func testOrdinalTranscripts() async throws {
        guard let dir = ProcessInfo.processInfo.environment["VYPO_INTEGRATION_DIR"] else {
            throw XCTSkip("set TEST_RUNNER_VYPO_INTEGRATION_DIR")
        }
        let models = URL(fileURLWithPath: dir).appendingPathComponent("Models/parakeet-ultra/parakeet-ultra")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: models.path), "no model in \(models.path)")
        let engine = ParakeetEngine(directory: models)
        try await engine.load()
        let runs: [(Lang, [String], [String])] = [(.de, Self.german, ["Anna", "Eddy (German (Germany))", "Flo (German (Germany))", "Shelley (German (Germany))"]),
                                                  (.en, Self.english, ["Samantha", "Daniel", "Karen", "Fred"])]
        for (lang, sentences, voices) in runs {
            for voice in voices {
                for sentence in sentences {
                    guard let samples = try? TestSpeech.say(sentence, voice: voice), samples.count > 1000 else { continue }
                    let raw = try await engine.transcribe(AudioPadding.padded(samples), language: nil)
                    let out = TextPipeline.process(raw, PipelineContext(language: lang, mode: .writing,
                                                                        spokenCharacters: SpokenCharacters.defaults))
                    print("ORDINAL \(voice) | \(sentence) | \(raw) | \(out.replacingOccurrences(of: "\n", with: "⏎"))")
                }
            }
        }
    }
}
