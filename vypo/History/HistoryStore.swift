import Foundation
import Observation

/// One dictation, text and metadata only (§13).
struct HistoryItem: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var date: Date
    var text: String
    var rawText: String
    var appBundleID: String?
    var appName: String?
    var language: Lang
    /// The model's id, e.g. "parakeet-ultra"; older entries name models vypo no longer has.
    var modelID: String
    /// Set by “Undo last dictation” (§23.4); the item is kept.
    var undone = false
}

/// `history.json`, newest first, pruned by retention.
@MainActor
@Observable
final class HistoryStore {
    private(set) var items: [HistoryItem]
    @ObservationIgnored private let store: Store
    @ObservationIgnored private var timer: Timer?
    private static let file = "history.json"

    init(store: Store = .shared) {
        self.store = store
        items = (store.load([HistoryItem].self, from: Self.file) ?? []).sorted { $0.date > $1.date }
    }

    /// Prunes now and every hour.
    func startPruning(retention: @escaping @MainActor () -> HistoryRetention) {
        prune(retention())
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.prune(retention()) }
        }
    }

    func prune(_ retention: HistoryRetention, now: Date = Date()) {
        guard let days = retention.days else { return }
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        let kept = items.filter { $0.date >= cutoff }
        if kept.count != items.count {
            items = kept
            save()
        }
    }

    func add(_ item: HistoryItem) {
        items.insert(item, at: 0)
        save()
    }

    func update(_ id: UUID, _ change: (inout HistoryItem) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[i])
        save()
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func clear() {
        items = []
        save()
    }

    private func save() { store.save(items, to: Self.file) }
}
