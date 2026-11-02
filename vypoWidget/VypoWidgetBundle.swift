import AppIntents
import SwiftUI
import WidgetKit

/// “Edit Widget”.
struct WidgetStyleIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Widget style"
    static let description = IntentDescription("Your rank, today's words and what's next.")

    @Parameter(title: "Woodcut look", default: true)
    var woodcut: Bool
}

struct LevelEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let look: WidgetLook
}

struct LevelProvider: AppIntentTimelineProvider {
    private func look(_ intent: WidgetStyleIntent) -> WidgetLook { WidgetLook(woodcut: intent.woodcut) }

    /// What the app last wrote. Without it the widget asks to open the app; the gallery shows the sample.
    private func snapshot(preview: Bool) -> WidgetSnapshot {
        if let stored = WidgetStore.url.flatMap(WidgetStore.read(from:)) { return stored }
        return preview ? .sample : WidgetSnapshot()
    }

    func placeholder(in context: Context) -> LevelEntry {
        LevelEntry(date: Date(), snapshot: .sample, look: .woodcut)
    }

    func snapshot(for configuration: WidgetStyleIntent, in context: Context) async -> LevelEntry {
        LevelEntry(date: Date(), snapshot: snapshot(preview: context.isPreview), look: look(configuration))
    }

    /// One entry. The app asks for a reload whenever something changes; the only change of its own is midnight, when
    /// “words today” starts again.
    func timeline(for configuration: WidgetStyleIntent, in context: Context) async -> Timeline<LevelEntry> {
        let now = Date()
        let entry = LevelEntry(date: now, snapshot: snapshot(preview: false), look: look(configuration))
        let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0), matchingPolicy: .nextTime) ?? now.addingTimeInterval(86_400)
        return Timeline(entries: [entry], policy: .after(midnight))
    }
}

struct LevelWidget: Widget {
    private static var kind: String { Bundle.main.object(forInfoDictionaryKey: "VYPOWidgetKind") as? String ?? "vypo.level" }

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: WidgetStyleIntent.self, provider: LevelProvider()) { entry in
            LevelEntryView(entry: entry)
        }
        .configurationDisplayName("vypo Level")
        .description("Your rank, today's words and what's next.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct LevelEntryView: View {
    let entry: LevelEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        WidgetFace(snapshot: entry.snapshot, family: family, look: entry.look, now: entry.date)
            .containerBackground(for: .widget) { WidgetBackground(snapshot: entry.snapshot, family: family, look: entry.look) }
            .widgetURL(WidgetLink.stats.url())
    }
}

@main
struct VypoWidgets: WidgetBundle {
    var body: some Widget { LevelWidget() }
}
