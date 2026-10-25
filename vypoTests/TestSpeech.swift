import Foundation
@testable import vypo

/// Speech from `say`, as 16 kHz mono Float32.
enum TestSpeech {
    static func say(_ text: String, voice: String) throws -> [Float] {
        let aiff = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".aiff")
        defer { try? FileManager.default.removeItem(at: aiff) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        p.arguments = ["-v", voice, "-o", aiff.path, text]
        try p.run()
        p.waitUntilExit()
        return try WAVFile.read(aiff)
    }
}

extension TestSpeech {
    /// The first installed `say` voice for `lang`, preferring the main variety (en_US, pt_PT, …).
    static func voice(for lang: Lang) -> String? {
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        p.arguments = ["-v", "?"]
        p.standardOutput = pipe
        guard (try? p.run()) != nil else { return nil }
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        // "Anna (German (Germany)) de_DE    # Hallo! …" or "Tünde               hu_HU    # …".
        let pattern = /^(.+?)\s+([a-z]{2}_[A-Z]{2})\s+#/
        let voices: [(name: String, locale: String)] = out.split(separator: "\n").compactMap { line in
            guard let m = String(line).firstMatch(of: pattern) else { return nil }
            return (String(m.1), String(m.2))
        }
        let preferred = ["en": "en_US", "de": "de_DE", "fr": "fr_FR", "es": "es_ES", "pt": "pt_PT", "nl": "nl_NL"]
        // The Eloquence voices (Eddy, Flo, Grandma, …) sound synthetic; skip them when there's another.
        let novelty: Set<String> = ["Eddy", "Flo", "Grandma", "Grandpa", "Reed", "Rocko", "Sandy", "Shelley"]
        let matching = voices.filter { $0.locale.hasPrefix(lang.rawValue + "_") }
        let natural = matching.filter { !novelty.contains(String($0.name.split(separator: " ").first ?? "")) }
        let pool = natural.isEmpty ? matching : natural
        return (pool.first { $0.locale == preferred[lang.rawValue] } ?? pool.first)?.name
    }
}
