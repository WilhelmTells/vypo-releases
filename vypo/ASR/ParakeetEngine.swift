@preconcurrency import FluidAudio
import Foundation

/// Parakeet Ultra via FluidAudio, with the optional CTC glossary helper (§9, §11.3).
actor ParakeetEngine: ASREngine {
    static let version: AsrModelVersion = .ultra
    private let directory: URL
    /// Where the `ctc-vocab` helper lives; nil while it is off or not installed (`setHelper`).
    private var helperDirectory: URL?

    private var manager: AsrManager?
    private var loading: Task<AsrManager, Error>?
    private var ctcModels: CtcModels?
    private var ctcLoading: Task<CtcModels?, Never>?
    private var vocabulary: VocabularyBoostingSession?
    private var vocabularyKey: [String] = []
    private(set) var lastTiming: TranscriptionTiming?

    static let maxTerms = 100

    init(directory: URL, helperDirectory: URL? = nil) {
        self.directory = directory
        self.helperDirectory = helperDirectory
    }

    var isLoaded: Bool { manager != nil }
    var isVocabularyLoaded: Bool { ctcModels != nil }
    var isHelperOn: Bool { helperDirectory != nil }

    /// Turns the glossary helper on (loaded right away when the speech model is) or off (unloaded;
    /// the files stay). Off, transcribing skips the CTC pass; the text correction runs as always.
    func setHelper(_ directory: URL?) {
        guard directory != helperDirectory else { return }
        helperDirectory = directory
        ctcLoading?.cancel()
        ctcLoading = nil
        ctcModels = nil
        vocabulary = nil
        vocabularyKey = []
        if directory != nil, manager != nil { Task { _ = await self.loadCtcModels() } }
        Log.asr.notice("Glossary helper \(directory == nil ? "off" : "on", privacy: .public)")
    }

    func load() async throws {
        guard manager == nil else { return }
        // Concurrent callers share one load.
        let task = loading ?? Task { [directory] in
            let models = try await AsrModels.load(from: directory, version: Self.version)
            let m = AsrManager(config: .default)
            try await m.loadModels(models)
            return m
        }
        loading = task
        defer { loading = nil }
        manager = try await task.value
        Log.asr.info("Loaded Parakeet Ultra")
        // The glossary helper took 25.8 s on the first dictation after an install (2026-10-23): load it now.
        if helperDirectory != nil { Task { _ = await self.loadCtcModels() } }
    }

    /// The CTC helper for the glossary, loaded once; concurrent callers share the load.
    private func loadCtcModels() async -> CtcModels? {
        if let ctcModels { return ctcModels }
        guard let dir = helperDirectory else { return nil }
        let task = ctcLoading ?? Task {
            let clock = ContinuousClock()
            let start = clock.now
            do {
                let models = try await CtcModels.load(from: dir)
                Log.asr.notice("Loaded the glossary helper in \((clock.now - start).milliseconds) ms")
                return models
            } catch {
                Log.asr.error("Custom vocabulary unavailable: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        ctcLoading = task
        let models = await task.value
        // Turned off or moved meanwhile: drop it.
        guard helperDirectory == dir else { return nil }
        ctcLoading = nil
        ctcModels = models
        return models
    }

    func unload() async {
        loading?.cancel()
        loading = nil
        ctcLoading?.cancel()
        ctcLoading = nil
        await manager?.cleanup()
        manager = nil
        ctcModels = nil
        vocabulary = nil
        vocabularyKey = []
    }

    /// vypo's language as FluidAudio's, which only uses its script: with a hint the decoder prefers a
    /// token in that script over a likelier one in another (Cyrillic "Слэш" for "Slash").
    static func fluidLanguage(_ lang: Lang) -> Language {
        switch lang {
        case .bg: .bulgarian
        case .cs: .czech
        case .da: .danish
        case .de: .german
        case .el: .greek
        case .en: .english
        case .es: .spanish
        case .fi: .finnish
        case .fr: .french
        case .hr: .croatian
        case .hu: .hungarian
        case .it: .italian
        case .nl: .dutch
        case .pl: .polish
        case .pt: .portuguese
        case .ro: .romanian
        case .ru: .russian
        case .sk: .slovak
        case .sv: .swedish
        case .uk: .ukrainian
        }
    }

    func transcribe(_ samples: [Float], language: Lang?, glossary: [GlossaryEntry]) async throws -> String {
        if manager == nil { try await load() }
        guard let manager else { throw ASREngineError.notLoaded }
        var timing = TranscriptionTiming()
        defer { lastTiming = timing }
        let clock = ContinuousClock()
        var mark = clock.now
        /// The time since the previous call, which starts the next span.
        func lap() -> Duration {
            let now = clock.now
            defer { mark = now }
            return now - mark
        }
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let result = try await manager.transcribe(samples, decoderState: &state, language: language.map(Self.fluidLanguage))
        timing.decode = lap()
        var text = result.text
        guard !glossary.isEmpty, helperDirectory != nil, let timings = result.tokenTimings, !timings.isEmpty else { return text }
        var steps = GlossaryTiming()
        defer { timing.glossary = steps }
        guard let session = await vocabularySession(for: glossary) else { return text }
        steps.session = lap()
        guard let out = await session.rescore(text: text, tokenTimings: timings, audioSamples: samples) else {
            steps.helper = lap()
            return text
        }
        steps.helper = lap()
        let pairs = out.replacements.filter(\.shouldReplace).compactMap { r in r.replacementWord.map { (r.originalWord, $0) } }
        Log.asr.debug("Vocabulary replacements: \(pairs.map { "\($0.0) → \($0.1)" }.joined(separator: "; "), privacy: .public)")
        let aliases = Dictionary(glossary.map { ($0.term, $0.soundsLike) }, uniquingKeysWith: { a, _ in a })
        // Which of the replaced words are ordinary English or German words; the spell checker wants the main thread.
        let candidates = Set(pairs.flatMap { $0.0.split(separator: " ").map { $0.trimmingCharacters(in: .punctuationCharacters) } })
        let words = await MainActor.run { candidates.filter { !TermExtractor.spellCheckerUnknown($0) } }
        steps.spelling = lap()
        text = Self.merge(text, replacements: pairs, aliases: aliases, isWord: words.contains)
        steps.merge = lap()
        return text
    }

    /// Applies the rescorer's term replacements to the original transcript. FluidAudio's rebuilt text
    /// keeps only words with timings and its spans can swallow neighbouring words, so spans that already
    /// contain the term are skipped and a span is narrowed to the part that clearly matches the term or an alias.
    /// `isWord` tells ordinary dictionary words: those are replaced only when they're spelled almost like
    /// the term or an alias, or sound the same; merely similar words (“glaube” → “Claus”) stay.
    static func merge(_ text: String, replacements: [(original: String, term: String)], aliases: [String: [String]] = [:],
                      isWord: (String) -> Bool = { _ in false }) -> String {
        var result = text
        for (original, term) in replacements {
            let words = original.split(separator: " ").map(String.init)
            guard !words.isEmpty else { continue }
            let bare = words.map { $0.trimmingCharacters(in: .punctuationCharacters) }
            if bare.contains(where: { $0.caseInsensitiveCompare(term) == .orderedSame }) { continue }

            // Narrow to a sub-span only on strong evidence (term or alias, similarity ≥ 0.85).
            let targets = ([term] + (aliases[term] ?? [])).map(TextSimilarity.normalize)
            var best = (start: 0, end: words.count, score: 0.85)
            for i in 0..<words.count {
                for j in (i + 1)...words.count where j - i < words.count {
                    let window = TextSimilarity.normalize(bare[i..<j].joined())
                    let score = targets.map { TextSimilarity.similarity(window, $0) }.max() ?? 0
                    if score > best.score + 1e-9 { best = (i, j, score) }
                }
            }
            // Without a strong sub-span, the whole span must resemble the term or an alias; the rescorer
            // proposes short terms for unrelated words (“dass die ein bisschen heller” → “Claus”).
            if best.end - best.start == words.count && !isPlausible(bare.joined(), targets: targets) { continue }
            let span = bare[best.start..<best.end]
            if span.allSatisfy(isWord) && !realWordMayBecome(Array(span), term: term, targets: targets) { continue }
            let lead = String(words[best.start].prefix { $0.isPunctuation })
            let trail = String(words[best.end - 1].reversed().prefix { $0.isPunctuation }.reversed())
            let replaced = (Array(words[..<best.start]) + [lead + term + trail] + Array(words[best.end...])).joined(separator: " ")

            let pattern = "(?i)(?<![\\p{L}\\p{N}])" + words.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "\\s+") + "(?![\\p{L}\\p{N}])"
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            // The rescorer doesn't say where the span is, and it may occur more than once: try the
            // occurrences spelled exactly like it first, then the rest, and take the first one allowed.
            let ranges = re.matches(in: result, range: NSRange(result.startIndex..., in: result)).compactMap { Range($0.range, in: result) }
            let ordered = ranges.filter { result[$0] == original } + ranges.filter { result[$0] != original }
            let guarded = span.allSatisfy(isWord) && !targets.contains(TextSimilarity.normalize(span.joined()))
            let allowed = ordered.first { r in
                // “in the cloud”: after an article an ordinary word is a thing, not a name, unless the user
                // listed it as a spelling of the term.
                guard guarded else { return true }
                let previous = best.start > 0 ? bare[best.start - 1]
                    : result[..<r.lowerBound].split(whereSeparator: \.isWhitespace).last.map { $0.trimmingCharacters(in: .punctuationCharacters) }
                return !(previous.map { GlossaryCorrector.determiners.contains($0.lowercased()) } ?? false)
            }
            guard let r = allowed else { continue }
            result.replaceSubrange(r, with: replaced)
        }
        return result
    }

    /// Spelled at least half like a target, or sounding the same (Double Metaphone).
    static func isPlausible(_ span: String, targets: [String]) -> Bool {
        let norm = TextSimilarity.normalize(span)
        let code = DoubleMetaphone.primary(norm)
        return targets.contains { TextSimilarity.similarity(norm, $0) >= GlossaryCorrector.phoneticMinimum || DoubleMetaphone.primary($0) == code }
    }

    /// The bar for real words: spelled almost the same (≥ 0.85), or the same Double Metaphone code when part
    /// of the term is already there (“Claus Kot” → “Claus Code”). A single word that only sounds the same
    /// stays: “Claudia”, “Jura”, and, the accepted cost, a misheard “Cloud”.
    static func realWordMayBecome(_ span: [String], term: String, targets: [String]) -> Bool {
        let norm = TextSimilarity.normalize(span.joined())
        if targets.contains(where: { TextSimilarity.similarity(norm, $0) >= 0.85 }) { return true }
        let termWords = Set(term.lowercased().split(separator: " ").map(String.init))
        guard span.count > 1, span.contains(where: { termWords.contains($0.lowercased()) }) else { return false }
        let code = DoubleMetaphone.primary(norm)
        return targets.contains { DoubleMetaphone.primary($0) == code }
    }

    /// Builds (and caches) the custom vocabulary: term as canonical text, "sounds like" as aliases,
    /// at most 100 terms, newest first. FluidAudio's default weights and thresholds are kept.
    private func vocabularySession(for glossary: [GlossaryEntry]) async -> VocabularyBoostingSession? {
        let entries = glossary.sorted { $0.createdAt > $1.createdAt }.prefix(Self.maxTerms)
        let key = entries.map { "\($0.term)|\($0.soundsLike.joined(separator: ","))" }
        if key == vocabularyKey, let vocabulary { return vocabulary }
        do {
            guard let ctcModels = await loadCtcModels() else { return nil }
            let terms = entries.map {
                CustomVocabularyTerm(text: $0.term, aliases: $0.soundsLike.isEmpty ? nil : $0.soundsLike)
            }
            let session = try await VocabularyBoostingSession(vocabulary: CustomVocabularyContext(terms: Array(terms)), ctcModels: ctcModels)
            vocabulary = session
            vocabularyKey = key
            return session
        } catch {
            Log.asr.error("Custom vocabulary unavailable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

