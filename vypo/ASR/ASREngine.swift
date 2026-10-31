import Foundation

/// A speech-to-text engine (§4). Engines are actors, so `unload` and `isLoaded` are async.
protocol ASREngine: Actor {
    var isLoaded: Bool { get }
    func load() async throws
    func unload() async
    /// Whether the model has run once since it was loaded, so Core ML has prepared it (E5 cache, ANE).
    var isWarm: Bool { get }
    /// Runs one second of silence through the loaded model, once per load. Takes its turn like a dictation;
    /// skips itself if a transcription already warmed the model. Never throws: a failure only goes to the log.
    func warmUp() async
    /// `samples` are 16 kHz mono Float32. `language` is a hint for engines that need one; nil lets the engine work it out.
    func transcribe(_ samples: [Float], language: Lang?) async throws -> String
    /// How the last `transcribe` spent its time, for the log.
    var lastTiming: TranscriptionTiming? { get }
}

enum ASREngineError: Error {
    case notLoaded
    case modelFilesMissing
}
