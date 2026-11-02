import Foundation
import Observation
import WidgetKit

/// Runs its action once, `delay` after the last call.
@MainActor
final class Debouncer {
    private let delay: Duration
    private let action: () -> Void
    private var task: Task<Void, Never>?

    init(delay: Duration, action: @escaping () -> Void) {
        self.delay = delay
        self.action = action
    }

    func call() {
        task?.cancel()
        task = Task { [delay, action] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            action()
        }
    }
}

extension WidgetSnapshot {
    /// The widget's data, from the same stores and calculations as the Stats pane. While “Collect stats” is off the
    /// Stats pane shows neither level nor achievements, so this holds nothing but the language.
    @MainActor
    static func current(app: AppState, now: Date = Date(), calendar: Calendar = .current) -> WidgetSnapshot {
        var s = WidgetSnapshot()
        s.writtenAt = now
        s.uiLanguage = Formatting.uiLocale.identifier
        s.numberLocale = Locale.current.identifier
        s.collecting = app.prefs.collectStats
        guard s.collecting else { return s }

        let rank = app.level.rank
        s.level = rank.level
        s.rankName = rank.name
        s.nextRankName = rank.next?.name
        s.words = app.level.xpWords
        s.rankStart = rank.threshold
        s.nextStart = rank.next?.threshold
        s.progress = rank.progress(words: app.level.xpWords)

        s.today = calendar.startOfDay(for: now)
        s.wordsToday = app.stats.words(since: s.today)
        s.minutesSaved = StatsMath.minutesSaved(words: app.stats.allTime, seconds: app.stats.allSeconds)
        s.savedText = StatsMath.savedText(minutes: s.minutesSaved)
        s.activity = app.stats.weeks(activityWeeks, now: now).map { $0.map { $0?.words } }

        let all = app.achievements.all
        s.ready = AchievementCardContent(all).slots.first(where: \.isReady).map {
            Achievement(id: $0.id.rawValue, name: AchievementText.name($0.id, tier: max($0.status.level, 1)))
        }
        // The stamp days are “yyyy-MM-dd”, so they sort as text; within a day the later one in the card's order wins.
        s.latest = AchievementCardContent(all).slots.filter { $0.status.isStamped }.max {
            ($0.status.stampedOn ?? "") < ($1.status.stampedOn ?? "")
        }.map {
            Achievement(id: $0.id.rawValue, name: AchievementText.name($0.id, tier: $0.status.stampedLevel), day: $0.status.stampedOn)
        }
        s.firstAchievementName = AchievementText.name(.firstWords)
        s.suggestion = app.glossary.visibleSuggestions.max { $0.lastSeen < $1.lastSeen }.map { Suggestion(id: $0.id, term: $0.term) }
        return s
    }

    static let activityWeeks = 27
}

/// Keeps the widget up to date: watches everything the snapshot is made from (dictations, the level, stamps, glossary
/// suggestions, “Collect stats”), and at launch, at midnight and when the language or region changes writes the snapshot
/// again. Writes and reloads are debounced, and only happen when the content changed, so a burst of dictations costs one
/// reload. Not under XCTest: `AppCoordinator.start` doesn't run there, so no test reaches the App Group.
@MainActor
final class WidgetSync {
    static let delay: Duration = .seconds(1)

    private let app: AppState
    private let url: URL?
    private let reload: () -> Void
    private var last: WidgetSnapshot?
    private var observers: [NSObjectProtocol] = []
    private lazy var debouncer = Debouncer(delay: Self.delay) { [weak self] in self?.flush() }

    init(app: AppState, url: URL? = WidgetStore.url, reload: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() }) {
        self.app = app
        self.url = url
        self.reload = reload
    }

    func start() {
        guard let url else {
            Log.store.info("Widget: no App Group in this build, nothing is written")
            return
        }
        last = WidgetStore.read(from: url)
        flush()
        watch()
        for name in [Notification.Name.NSCalendarDayChanged, NSLocale.currentLocaleDidChangeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.debouncer.call() }
            })
        }
    }

    /// Reads what the snapshot reads, so that any change of it calls back once, then watches again.
    private func watch() {
        withObservationTracking {
            _ = WidgetSnapshot.current(app: app)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.debouncer.call()
                self?.watch()
            }
        }
    }

    func flush() {
        guard let url else { return }
        let snapshot = WidgetSnapshot.current(app: app)
        if let last, last.sameContent(as: snapshot) { return }
        do {
            try WidgetStore.write(snapshot, to: url)
            last = snapshot
            reload()
        } catch {
            Log.store.error("Widget: the snapshot could not be written: \(error.localizedDescription, privacy: .public)")
        }
    }
}
