import Foundation
@testable import vypo

/// The benchmark's inputs: the owner's recordings and the pipeline settings.
enum BenchmarkFiles {
    /// The `.wav` files in `directory`, sorted by name (= by time). Files that can't be read, or are empty,
    /// are listed instead of stopping the run: a write may have failed half-way.
    static func recordings(in directory: URL) -> (read: [(name: String, samples: [Float])], unreadable: [String]) {
        let files = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "wav" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var read: [(name: String, samples: [Float])] = []
        var unreadable: [String] = []
        for file in files {
            if let samples = try? WAVFile.read(file), !samples.isEmpty {
                read.append((file.lastPathComponent, samples))
            } else {
                unreadable.append(file.lastPathComponent)
            }
        }
        return (read, unreadable)
    }

    /// The app's default settings for a dictation in standard mode, filler words removed;
    /// no replacements, so only the glossary changes between configurations.
    static func context(language: Lang, glossary: [GlossaryEntry]) -> PipelineContext {
        PipelineContext(language: language, glossary: glossary, strength: .normal, fillers: FillerRemover.defaultWords(language))
    }
}
