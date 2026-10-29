import Foundation

#if DEBUG

/// Debug: keeps every finished recording for the glossary benchmark (`GlossaryBenchmarkTests`).
enum BenchmarkRecordings {
    static var directory: URL {
        Store.shared.directory.appendingPathComponent("Benchmark/recordings", isDirectory: true)
    }

    /// Names sort by time, so the benchmark can tell the newest take of a sentence.
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return f
    }()

    /// Writes the samples as `<yyyyMMdd-HHmmss-SSS>.wav`. Never throws: a failure must not stop the dictation.
    @discardableResult
    static func keep(_ samples: [Float], at date: Date = Date(), in directory: URL = directory) -> URL? {
        let url = directory.appendingPathComponent(formatter.string(from: date) + ".wav")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try WAVFile.write(samples, to: url)
            return url
        } catch {
            Log.audio.error("Keeping the recording for the benchmark failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
#endif
