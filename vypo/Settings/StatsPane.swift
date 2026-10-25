import AppKit
import SwiftUI

/// Settings → Stats (§23.12): the level, figure cards, a streak heatmap, apps and languages.
struct StatsPane: View {
    @Environment(AppState.self) private var app
    @State private var confirmReset = false
    /// The comparison drawn when the pane opened (another work than last time).
    @State private var comparison: WorkComparison?

    var body: some View {
        @Bindable var prefs = app.prefs
        Form {
            Section {
                Toggle("Collect stats", isOn: $prefs.collectStats)
                Toggle("Show level", isOn: $prefs.showLevel)
                LabeledContent("Reset stats") {
                    DestructiveButton("Reset stats") { confirmReset = true }
                }
            } header: {
                PaneSectionHeader(pane: .stats) {
                    VStack(spacing: 10) {
                        if prefs.showLevel, prefs.collectStats {
                            LevelCard(level: app.level, preview: app.levelPreview)
                        }
                        row {
                            speedCard
                            savedCard
                            totalCard
                        }
                        StreakCard(stats: app.stats)
                        row {
                            appsCard
                            languagesCard.frame(width: 190)
                        }
                    }
                    .textCase(nil)
                    .padding(.bottom, Space.s3)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            comparison = StatsMath.comparison(words: app.stats.allTime, previous: LastComparison.workID)
            LastComparison.workID = comparison.flatMap { $0.pages == nil ? $0.workID : nil }
        }
        .alert("Reset all stats?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { app.resetStats() }
            // Return and Esc both cancel; the reset needs a click.
            Button("Cancel", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
        } message: {
            Text("Words, streak, apps, languages and your level go back to zero. This can’t be undone.")
        }
    }

    /// Cards side by side, all as tall as the tallest.
    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 10) { content() }
            .fixedSize(horizontal: false, vertical: true)
    }

    private var wpm: Int { StatsMath.wordsPerMinute(words: app.stats.allTime, seconds: app.stats.allSeconds) }

    private var speedCard: some View {
        StatCard {
            Figure(value: wpm.formatted(), label: "Words per minute")
            Spacer(minLength: Space.s2)
            HStack(spacing: Space.s2) {
                SpeedGauge(value: Double(wpm) / 200)
                if wpm > 0 {
                    Text("\((Double(wpm) / StatsMath.typingWPM).formatted(.number.precision(.fractionLength(1)).locale(Formatting.uiLocale)))× as fast as typing")
                        .font(.callout)
                        .foregroundStyle(Color.vyLabelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var savedCard: some View {
        let minutes = StatsMath.minutesSaved(words: app.stats.allTime, seconds: app.stats.allSeconds)
        return StatCard {
            Figure(value: StatsMath.savedText(minutes: minutes), label: "Time saved")
            Spacer(minLength: Space.s2)
            Text("Compared with typing at 40 words per minute.")
                .font(.callout)
                .foregroundStyle(Color.vyLabelSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var totalCard: some View {
        let stats = app.stats
        return StatCard {
            Figure(value: stats.allTime.formatted(), label: "Words dictated")
            Spacer(minLength: Space.s2)
            // The day's words show when the pointer rests on a day in the streak map.
            if let comparison = comparison ?? StatsMath.comparison(words: stats.allTime) {
                Text(StatsMath.comparisonText(comparison))
                    .font(.callout)
                    .foregroundStyle(Color.vyLabelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var appsCard: some View {
        let shares = StatsMath.appShares(app.stats.apps)
        return StatCard {
            CardTitle("Apps")
            if shares.rows.isEmpty {
                Text("Counted from now on. Dictate in a few apps and they show up here.")
                    .font(.callout)
                    .foregroundStyle(Color.vyLabelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: Space.s3) {
                    ForEach(shares.rows, id: \.app) { entry in
                        ShareRow(icon: .app(AppProfileStore.icon(for: entry.app)), name: Self.appName(entry.app), percent: entry.percent)
                    }
                    if let other = shares.other {
                        ShareRow(icon: .symbol("square.grid.2x2"), name: String(localized: "Other (\(other.count) apps)"), percent: other.percent)
                    }
                }
            }
        }
    }

    private var languagesCard: some View {
        let words = app.stats.days.reduce(into: [String: Int]()) { sum, day in
            sum.merge(day.wordsByLanguage, uniquingKeysWith: +)
        }
        let shares = StatsMath.languageShares(words)
        let tints = [1, 0.6, 0.35, 0.2].map { Color.vyAccent.opacity($0) }
        return StatCard {
            CardTitle("Languages")
            GeometryReader { geo in
                HStack(spacing: 2) {
                    let width = geo.size.width - 2 * Double(max(0, shares.count - 1))
                    ForEach(Array(shares.enumerated()), id: \.offset) { i, share in
                        Capsule().fill(tints[i]).frame(width: max(4, width * Double(share.percent) / 100))
                    }
                    if shares.isEmpty { Capsule().fill(Color.vyFillTrack) }
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.s1) {
                ForEach(Array(shares.enumerated()), id: \.offset) { i, share in
                    legend(share.lang?.name ?? String(localized: "Other"), percent: share.percent, tint: tints[i])
                }
            }
        }
    }

    private func legend(_ name: String, percent: Int, tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 8, height: 8).accessibilityHidden(true)
            Text(name).foregroundStyle(Color.vyLabel)
            Spacer(minLength: Space.s2)
            Text("\(percent) %").monospacedDigit().foregroundStyle(Color.vyLabelSecondary)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }

    /// The app's name from its bundle, or the last part of the ID if it isn't installed.
    static func appName(_ bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }
}

/// A rounded card on the group fill.
private struct StatCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) { content }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(Space.s4)
            .softCard()
            .accessibilityElement(children: .combine)
    }
}

/// A large figure with a small uppercase label below it.
private struct Figure: View {
    var value: String
    var label: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 26, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.vyLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            CardLabel(label)
        }
    }
}

struct CardLabel: View {
    var text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .textCase(.uppercase)
            .font(.vyTier)
            .tracking(0.6)
            .foregroundStyle(Color.vyLabelSecondary)
    }
}

private struct CardTitle: View {
    var text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text).font(.headline).foregroundStyle(Color.vyLabel)
    }
}

/// A half-circle gauge, full at 200 words per minute.
private struct SpeedGauge: View {
    var value: Double

    var body: some View {
        ZStack {
            Circle().trim(from: 0, to: 0.5)
                .stroke(Color.vyFillTrack, style: StrokeStyle(lineWidth: 5, lineCap: .round))
            Circle().trim(from: 0, to: 0.5 * min(max(value, 0), 1))
                .stroke(Color.vyAccent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
        }
        .rotationEffect(.degrees(180))
        .frame(width: 40, height: 40)
        .frame(height: 22, alignment: .top)
        .accessibilityHidden(true)
    }
}

/// App icon (or a symbol), name and share, with a bar below.
private struct ShareRow: View {
    enum Icon { case app(NSImage), symbol(String) }
    var icon: Icon
    var name: String
    var percent: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(spacing: 6) {
                switch icon {
                case .app(let image):
                    Image(nsImage: image).resizable().frame(width: 16, height: 16).accessibilityHidden(true)
                case .symbol(let name):
                    Image(systemName: name).frame(width: 16, height: 16).foregroundStyle(Color.vyLabelSecondary).accessibilityHidden(true)
                }
                Text(name).foregroundStyle(Color.vyLabel).lineLimit(1)
                Spacer(minLength: Space.s2)
                Text("\(percent) %").monospacedDigit().foregroundStyle(Color.vyLabelSecondary)
            }
            .font(.callout)
            ProgressBar(value: Double(percent) / 100)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Days with words over the last 26 weeks, one column per week, plus the current and longest streak.
/// Drawn in one Canvas: 182 separate cell views took about a quarter second to lay out.
private struct StreakCard: View {
    let stats: StatsStore
    @State private var hovered: (date: Date, words: Int)?

    var body: some View {
        let weeks = stats.weeks(Heatmap.weeks)
        StatCard {
            HStack(alignment: .firstTextBaseline) {
                Text("\(stats.currentStreak())-day streak")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.vyLabel)
                Spacer()
                CardLabel("Longest: \(stats.longestStreak) days")
            }
            Heatmap(weeks: weeks, hovered: $hovered)
            HStack(spacing: Heatmap.gap) {
                if let hovered {
                    Text("\(hovered.date.formatted(.dateTime.day().month(.abbreviated).locale(Formatting.uiLocale))) · \(hovered.words) words")
                        .monospacedDigit()
                }
                Spacer()
                Text("Less").padding(.trailing, Space.s1)
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2).fill(Heatmap.fill(level: level)).frame(width: 10, height: 10)
                }
                Text("More").padding(.leading, Space.s1)
            }
            .font(.caption)
            .foregroundStyle(Color.vyLabelSecondary)
            .accessibilityHidden(true)
        }
        .accessibilityLabel("Streak")
        .accessibilityValue("\(stats.currentStreak()) days, longest \(stats.longestStreak) days")
    }
}

/// The heatmap itself: weekday labels, month labels and the cells, with the cell under the mouse
/// reported through `hovered`.
private struct Heatmap: View {
    static let weeks = 26
    static let gap: CGFloat = 3
    static let labelWidth: CGFloat = 26
    static let monthHeight: CGFloat = 14

    let weeks: [[(date: Date, words: Int)?]]
    @Binding var hovered: (date: Date, words: Int)?
    @State private var hoverCell: (column: Int, row: Int)?
    @State private var width: CGFloat = 0

    /// Cell edge for a given width.
    static func cell(width: CGFloat) -> CGFloat {
        max(4, (width - labelWidth - gap * CGFloat(weeks)) / CGFloat(weeks))
    }

    static func height(width: CGFloat) -> CGFloat {
        monthHeight + gap + 7 * cell(width: width) + 6 * gap
    }

    var body: some View {
        let peak = max(1, weeks.joined().compactMap { $0?.words }.max() ?? 1)
        let monthLabels = Self.monthLabels(weeks)
        let weekdays = Self.weekdayLabels()
        HeightForWidth(height: Self.height) {
            Canvas { context, size in
                let cell = Self.cell(width: size.width)
                let secondary = Color.vyLabelSecondary
                for (row, label) in weekdays.enumerated() where !label.isEmpty {
                    let y = Self.monthHeight + Self.gap + CGFloat(row) * (cell + Self.gap) + cell / 2
                    context.draw(Text(label).font(.caption2).foregroundStyle(secondary), at: CGPoint(x: 0, y: y), anchor: .leading)
                }
                for (column, label) in monthLabels {
                    let x = Self.labelWidth + Self.gap + CGFloat(column) * (cell + Self.gap)
                    context.draw(Text(label).font(.caption2).foregroundStyle(secondary), at: CGPoint(x: x, y: 0), anchor: .topLeading)
                }
                for (column, week) in weeks.enumerated() {
                    for (row, day) in week.enumerated() {
                        guard let day else { continue }
                        let rect = Self.rect(column: column, row: row, cell: cell)
                        let path = Path(roundedRect: rect, cornerRadius: 2)
                        context.fill(path, with: .color(Self.fill(level: Self.level(day.words, peak: peak))))
                        if let hoverCell, hoverCell.column == column, hoverCell.row == row {
                            context.stroke(Path(roundedRect: rect.insetBy(dx: -1.5, dy: -1.5), cornerRadius: 3),
                                           with: .color(Color.vyLabel), lineWidth: 1.5)
                        }
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .onContinuousHover { phase in
                guard case .active(let point) = phase else { return setHover(nil) }
                setHover(point)
            }
        }
        .accessibilityHidden(true)
    }

    private func setHover(_ point: CGPoint?) {
        guard let point, width > 0 else {
            hoverCell = nil
            hovered = nil
            return
        }
        let cell = Self.cell(width: width)
        let column = Int((point.x - Self.labelWidth - Self.gap) / (cell + Self.gap))
        let row = Int((point.y - Self.monthHeight - Self.gap) / (cell + Self.gap))
        guard point.x >= Self.labelWidth + Self.gap, point.y >= Self.monthHeight + Self.gap,
              weeks.indices.contains(column), (0..<7).contains(row), let day = weeks[column][row] else {
            hoverCell = nil
            hovered = nil
            return
        }
        hoverCell = (column, row)
        hovered = day
    }

    static func rect(column: Int, row: Int, cell: CGFloat) -> CGRect {
        CGRect(x: labelWidth + gap + CGFloat(column) * (cell + gap),
               y: monthHeight + gap + CGFloat(row) * (cell + gap),
               width: cell, height: cell)
    }

    static func level(_ words: Int, peak: Int) -> Int {
        guard words > 0 else { return 0 }
        return min(4, 1 + Int(Double(words) / Double(peak) * 3.999))
    }

    /// Mon, Wed and Fri, for the rows in the calendar's weekday order; empty for the others.
    static func weekdayLabels() -> [String] {
        (0..<7).map { row in
            let weekday = (Calendar.current.firstWeekday - 1 + row) % 7
            return [1, 3, 5].contains(weekday) ? Formatting.weekdaySymbols[weekday] : ""
        }
    }

    /// The month's name over the week its first day falls in, and over the first column.
    static func monthLabels(_ weeks: [[(date: Date, words: Int)?]]) -> [(column: Int, label: String)] {
        let calendar = Calendar.current
        var labels: [(column: Int, label: String)] = weeks.enumerated().compactMap { column, week in
            let dates = week.compactMap { $0?.date }
            guard let start = dates.first else { return nil }
            let first = dates.first { calendar.component(.day, from: $0) == 1 }
            guard first != nil || column == 0 else { return nil }
            return (column, (first ?? start).formatted(.dateTime.month(.abbreviated).locale(Formatting.uiLocale)))
        }
        // The first column's label would run into a month that starts right after it.
        if labels.count > 1, labels[0].column == 0, labels[1].column < 3 { labels.removeFirst() }
        return labels
    }

    static func fill(level: Int) -> Color {
        switch level {
        case 0: .vyFillTrack
        case 1: .vyAccent.opacity(0.3)
        case 2: .vyAccent.opacity(0.55)
        case 3: .vyAccent.opacity(0.8)
        default: .vyAccent
        }
    }
}

/// Takes the offered width and a height computed from it.
private struct HeightForWidth: Layout {
    var height: (CGFloat) -> CGFloat
    init(height: @escaping (CGFloat) -> CGFloat) { self.height = height }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 480
        return CGSize(width: width, height: height(width))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews { subview.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size)) }
    }
}
