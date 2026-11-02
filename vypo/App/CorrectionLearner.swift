import Foundation

/// Turns corrections made in other apps into glossary suggestions. Everything here happens after the paste.
/// Nothing of the field is kept or logged: the log line has numbers and the app, a suggestion only the term and how it was heard.
@MainActor
final class CorrectionLearner {
    private let app: AppState
    private lazy var watcher = CorrectionWatcher { [weak self] result in
        Task { @MainActor in self?.finished(result) }
    }

    init(app: AppState) {
        self.app = app
    }

    /// A paste into a text field is done.
    func pasted(_ text: String, app bundleID: String?, pid: pid_t, language: Lang, context: InsertionContext?) {
        guard app.prefs.learnFromCorrections else { return }
        watcher.start(.init(pasted: text, pid: pid, bundleID: bundleID, language: language,
                            continuesSentence: Self.continuesSentence(context)))
    }

    /// The switch went off.
    func stopAll() {
        watcher.stopAll()
    }

    /// The cursor stood inside a sentence when the text was pasted.
    nonisolated static func continuesSentence(_ context: InsertionContext?) -> Bool {
        guard var before = context?.before else { return false }
        while before.last == " " || before.last == "\t" { before.removeLast() }
        guard let last = before.last else { return false }
        return !last.isNewline && !".!?:".contains(last)
    }

    private func finished(_ result: CorrectionWatcher.Result) {
        let request = result.request
        var candidates = 0, passed = 0
        if app.prefs.learnFromCorrections, let latest = result.latest, latest != TrackedText.trimmed(request.pasted) {
            let pasted = TrackedText.trimmed(request.pasted)
            candidates = WordDiff.suggestionCandidates(from: pasted, to: latest).count
            let filter = CorrectionFilter(languages: app.prefs.languages, isGlossaryTerm: app.glossary.contains(term:))
            let pairs = filter.accepted(from: pasted, to: latest, continuesSentence: request.continuesSentence)
            passed = pairs.count
            app.glossary.learn(from: pairs, scope: GlossaryScope(request.language), source: .app)
        }
        let bundleID = request.bundleID ?? "no app"
        Log.corrections.notice("Watch in \(bundleID, privacy: .public): observed \(result.observed), found at end \(result.foundAtEnd), ended \(result.end.rawValue, privacy: .public), candidates \(candidates), passed \(passed)")
    }
}

private enum TrackedText {
    static func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
}
