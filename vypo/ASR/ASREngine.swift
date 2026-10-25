import Foundation

/// A speech-to-text engine (§4). Engines are actors, so `unload` and `isLoaded` are async.
protocol ASREngine: Actor {
    var isLoaded: Bool { get }
    func load() async throws
    func unload() async
    /// `samples` are 16 kHz mono Float32. `glossary` holds the in-scope entries to bias towards (§11.3).
    /// `language` is a hint for engines that need one; nil lets the engine work it out.
    func transcribe(_ samples: [Float], language: Lang?, glossary: [GlossaryEntry]) async throws -> String
    /// How the last `transcribe` spent its time, for the log.
    var lastTiming: TranscriptionTiming? { get }
}

enum ASREngineError: Error {
    case notLoaded
    case modelFilesMissing
}
