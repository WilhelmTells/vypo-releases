import Foundation
import os

/// JSON files in `~/Library/Application Support/vypo/`, written atomically.
struct Store: Sendable {
    let directory: URL
    /// Where the models are, when not in `directory/Models`: the shared store of a test run reads the real ones.
    private let modelsRoot: URL?

    init(directory: URL, modelsDirectory: URL? = nil) {
        self.directory = directory
        modelsRoot = modelsDirectory
    }

    /// The app's data. Under XCTest a scratch folder (see `RunEnvironment`), with the real models.
    static let shared: Store = {
        guard RunEnvironment.isTesting else { return Store(directory: Store.defaultDirectory) }
        let store = Store(directory: RunEnvironment.testDirectory,
                          modelsDirectory: RunEnvironment.realDirectory.appendingPathComponent("Models", isDirectory: true))
        // The list of installed models is read (copied), so the tests find the real models without changing anything.
        try? FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try? FileManager.default.copyItem(at: RunEnvironment.realDirectory.appendingPathComponent("models.json"), to: store.url("models.json"))
        return store
    }()

    static var defaultDirectory: URL { RunEnvironment.realDirectory }

    var modelsDirectory: URL { modelsRoot ?? directory.appendingPathComponent("Models", isDirectory: true) }

    func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

    func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        let url = url(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            Log.store.error("Could not decode \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func save<T: Encodable>(_ value: T, to name: String) {
        do {
            try write(value, to: name)
        } catch {
            Log.store.error("Could not write \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// `save` for a caller that must know it worked (the move to Spoken characters).
    func write<T: Encodable>(_ value: T, to name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(value)
        try data.write(to: url(name), options: .atomic)
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

enum Log {
    static let subsystem = "com.wilhelmtells.vypo"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let store = Logger(subsystem: subsystem, category: "store")
    static let input = Logger(subsystem: subsystem, category: "input")
    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let asr = Logger(subsystem: subsystem, category: "asr")
    static let models = Logger(subsystem: subsystem, category: "models")
    static let output = Logger(subsystem: subsystem, category: "output")
    static let pill = Logger(subsystem: subsystem, category: "pill")
}

extension Duration {
    /// Whole milliseconds, for timing logs.
    var milliseconds: Int { Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000) }
}
