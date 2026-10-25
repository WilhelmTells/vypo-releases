import AppKit

/// The sound pair played when a recording starts and stops (Settings → Recording). vypo's own short
/// synthesized blips (`scripts/make-sounds.py`), bundled in `Resources/Sounds`.
enum RecordingSound: String, CaseIterable, Sendable {
    case off
    case glideShort = "glide-short"
    case glide
    case glideLow = "glide-low"
    case soft, duo, deep, bell

    static let standard: RecordingSound = .glideShort

    var name: String {
        switch self {
        case .off: String(localized: "Off")
        case .glideShort: String(localized: "Glide short")
        case .glide: String(localized: "Glide")
        case .glideLow: String(localized: "Glide low")
        case .soft: String(localized: "Soft")
        case .duo: String(localized: "Duo")
        case .deep: String(localized: "Deep")
        case .bell: String(localized: "Bell")
        }
    }

    /// The start sound; nil when off. Loaded once and kept, so playing it doesn't touch the disk.
    @MainActor var start: NSSound? { Self.load("\(rawValue)-start") }
    @MainActor var stop: NSSound? { Self.load("\(rawValue)-stop") }

    /// Start, then stop, as in a short dictation (Settings preview).
    @MainActor func preview() {
        start?.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { stop?.play() }
    }

    @MainActor private static var cache: [String: NSSound] = [:]

    @MainActor private static func load(_ file: String) -> NSSound? {
        guard !file.hasPrefix("off") else { return nil }
        if let sound = cache[file] { return sound }
        guard let url = Bundle.main.url(forResource: file, withExtension: "wav", subdirectory: "Sounds")
                ?? Bundle.main.url(forResource: file, withExtension: "wav"),
              let sound = NSSound(contentsOf: url, byReference: true) else {
            Log.audio.error("Missing sound \(file, privacy: .public)")
            return nil
        }
        cache[file] = sound
        return sound
    }
}
