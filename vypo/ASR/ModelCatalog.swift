import Foundation

/// The models vypo downloads (§9.1): Parakeet Ultra for every language, and the CTC glossary helper,
/// which is off by default and only downloaded when turned on (Debug menu).
enum ModelID: String, Codable, CaseIterable, Sendable, Identifiable {
    case parakeetUltra = "parakeet-ultra"
    case ctcVocab = "ctc-vocab"

    var id: String { rawValue }
    var info: ModelInfo { ModelCatalog.info(self) }
}

struct ModelInfo: Sendable, Identifiable {
    let id: ModelID
    let name: String
    let note: String
    /// Approximate download size before the model is installed.
    let approxBytes: Int64

    var approxSizeText: String { ModelCatalog.gigabytes(approxBytes) }
}

enum ModelCatalog {
    /// The one speech model. Measured on an M1 MacBook Pro: 130–250 ms per sentence, against 5–6 s for
    /// Whisper large-v3-turbo, which vypo used before.
    static let speech: ModelID = .parakeetUltra

    static let all: [ModelInfo] = [
        ModelInfo(id: .parakeetUltra, name: "Parakeet Ultra", note: String(localized: "Fast and accurate, 20 languages. Runs on this Mac."),
                  approxBytes: 650_000_000),
        ModelInfo(id: .ctcVocab, name: "Parakeet CTC 110M", note: "Glossary helper (off by default).", approxBytes: 100_000_000),
    ]

    static func info(_ id: ModelID) -> ModelInfo { all.first { $0.id == id }! }

    static func gigabytes(_ bytes: Int64) -> String {
        (Double(bytes) / 1_000_000_000).formatted(.number.precision(.fractionLength(1)).locale(Formatting.uiLocale)) + " GB"
    }
}
