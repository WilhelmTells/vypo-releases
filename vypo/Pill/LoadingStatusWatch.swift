import Foundation

/// Decides when a dictation in processing shows “Loading speech model…” instead of the plain dots (§6.3):
/// right away if the speech model is not ready (still loading, preparing or warming up), and in any case once
/// the recognition has run longer than `after`, so a slow dictation is never silent. Nothing shows at launch.
@MainActor
final class LoadingStatusWatch {
    static let after: Duration = .seconds(5)

    private let isReady: () -> Bool
    private let show: () -> Void
    private let delay: Duration
    private var timer: Task<Void, Never>?
    private(set) var isShowing = false

    init(delay: Duration = LoadingStatusWatch.after, isReady: @escaping () -> Bool, show: @escaping () -> Void) {
        self.delay = delay
        self.isReady = isReady
        self.show = show
    }

    func start() {
        if !isReady() { display() }
        timer = Task { [delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            display()
        }
    }

    /// The transcription is over: no later switch.
    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func display() {
        guard !isShowing else { return }
        isShowing = true
        show()
    }
}
