import SwiftUI
import WidgetKit

/// The widget's face. Positions are those of `SPEC.md`: from the widget's top left corner, in the size the design was
/// drawn at. A smaller real widget scales the whole face down rather than cutting it off.
struct WidgetFace: View {
    let snapshot: WidgetSnapshot
    let family: WidgetFamily
    let look: WidgetLook
    var now = Date()
    /// Renders outside WidgetKit have no rendering mode; they set this one.
    var forcedAccented: Bool?

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var scheme

    private var accented: Bool { forcedAccented ?? (renderingMode == .accented) }

    var body: some View {
        WidgetStage(family: family) {
            if snapshot.showsFace {
                FaceContent(s: snapshot, text: WidgetText(snapshot: snapshot), family: family, look: look, now: now, dark: scheme == .dark,
                            accented: accented, forcedLinksOff: forcedAccented != nil)
            } else {
                MessageContent(snapshot: snapshot, palette: WidgetPalette(look: look, dark: scheme == .dark, accented: accented))
            }
        }
    }
}

/// The design's coordinate space inside the content margins, scaled down to the real widget. The face and the prints
/// in the background both stand on it, so they stay on top of each other.
private struct WidgetStage<Content: View>: View {
    let family: WidgetFamily
    @ViewBuilder var content: Content

    private var design: CGSize {
        switch family {
        case .systemSmall: CGSize(width: 170, height: 170)
        case .systemLarge: CGSize(width: 364, height: 382)
        default: CGSize(width: 364, height: 170)
        }
    }

    var body: some View {
        let size = CGSize(width: design.width - 32, height: design.height - 32)
        GeometryReader { proxy in
            let scale = min(1, proxy.size.width / size.width, proxy.size.height / size.height)
            content
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .scaleEffect(scale, anchor: .topLeading)
        }
    }
}

/// The widget's background: paper in Woodcut, the group colour in Plain, with the coloured boy and stamp printed on it.
/// macOS removes all of it in glass, in tinted and while dimming the desktop. See `WidgetPrints`.
struct WidgetBackground: View {
    let snapshot: WidgetSnapshot
    let family: WidgetFamily
    let look: WidgetLook
    /// Renders outside WidgetKit have no margins; they set these.
    var forcedMargins: EdgeInsets?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetContentMargins) private var margins

    var body: some View {
        ZStack {
            switch look {
            case .woodcut:
                let size = family == .systemSmall ? "small" : family == .systemLarge ? "large" : "medium"
                Image("paper-\(scheme == .dark ? "dark" : "light")-\(size)", bundle: WidgetAssets.bundle)
                    .resizable()
            case .plain:
                scheme == .dark ? Color(red: 0x2C / 255, green: 0x2C / 255, blue: 0x2E / 255) : Color.white
            }
            if snapshot.showsFace {
                WidgetStage(family: family) { WidgetPrints(s: snapshot, family: family, look: look, ink: .colour(dark: scheme == .dark)) }
                    .padding(forcedMargins ?? margins)
            }
        }
    }
}

/// Boy and stamp. While a window is in front, macOS draws the widget with the background removed and the rest
/// desaturated, in `fullColor`, and tells the widget nothing: `showsWidgetContainerBackground` stays true and
/// `.vibrant` never comes. Dark colour art turns to a blotch there.
/// So the colour art sits in the background and goes with the paper, and the face holds a cut-out in a blend mode that
/// changes nothing on paper: white in multiply on a dark desktop, black in screen on a light one. Once the paper is
/// gone there is nothing to blend with, and the cut-out is the print.
private struct WidgetPrints: View {
    enum Ink {
        /// In the background.
        case colour(dark: Bool)
        /// On the face, in full colour.
        case hiddenOnPaper(dark: Bool)
        /// On the face, in clear and tinted.
        case glass
    }

    let s: WidgetSnapshot
    let family: WidgetFamily
    let look: WidgetLook
    let ink: Ink

    private var colour: Bool { if case .colour = ink { true } else { false } }
    private var top: Bool { s.nextRankName == nil }

    /// Goes on last: `shadow` and `opacity` would keep it from reaching the background.
    private var blend: BlendMode {
        if case let .hiddenOnPaper(dark) = ink { dark ? .multiply : .screen } else { .normal }
    }

    private func printed(_ image: Image) -> some View {
        let black = if case .hiddenOnPaper(dark: false) = ink { true } else { false }
        return image
            .renderingMode(black ? .template : .original)
            .resizable()
            .widgetAccentedRenderingMode(.fullColor)
            .foregroundStyle(.black)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if look == .woodcut { boy.blendMode(blend) }
            if family == .systemLarge { stamp.blendMode(blend) }
        }
    }

    private var boy: some View {
        let frame: (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) = switch (family, top) {
        case (.systemSmall, false): (112, 71, 42, 83)
        case (.systemSmall, true): (115, 68, 36, 86)
        case (.systemLarge, false): (289, 16, 59, 116)
        case (.systemLarge, true): (273, 16, 75, 116)
        case (_, false): (283, 26, 65, 128)
        case (_, true): (270, 33, 78, 121)
        }
        let pose = top ? (family == .systemSmall ? "boy-raven-fanfare-tight" : "boy-raven-fanfare") : "boy-standing"
        return printed(Image(colour ? pose : pose + "-glass", bundle: WidgetAssets.bundle))
            .frame(width: frame.w, height: frame.h)
            .shadow(color: colour ? Color(red: 28 / 255, green: 16 / 255, blue: 6 / 255).opacity(0.35) : .clear, radius: 0, x: 1.5, y: 2)
            .at(frame.x, frame.y)
    }

    private var stamp: some View {
        let slot = s.stampSlot
        let variant = if case let .colour(dark) = ink { dark ? "dark" : "light" } else { "glass" }
        return printed(Image("stamp-\(slot.id)-\(variant)", bundle: WidgetAssets.bundle))
            .frame(width: 36, height: 36)
            .opacity(slot.pale ? 0.38 : 1)
            .at(16, WidgetSnapshot.achievementY(glossary: s.suggestion != nil))
    }
}

extension WidgetSnapshot {
    /// Stats off or nothing written yet is a message instead of the face.
    fileprivate var showsFace: Bool { collecting && !rankName.isEmpty }

    /// Which stamp the large widget shows. `pale` is the pre-print.
    fileprivate var stampSlot: (id: String, pale: Bool) {
        if let ready { return (ready.id, true) }
        if let latest { return (latest.id, false) }
        return ("firstWords", true)
    }

    fileprivate static func achievementY(glossary: Bool) -> CGFloat { glossary ? 302 : 316 }
}

/// Stats off, or no snapshot yet: nothing to count, and the whole widget still opens Stats.
private struct MessageContent: View {
    let snapshot: WidgetSnapshot
    let palette: WidgetPalette

    var body: some View {
        let text = WidgetText(snapshot: snapshot)
        let off = !snapshot.collecting
        VStack(alignment: .leading, spacing: 2) {
            Text(off ? text.statsOffTitle : text.openTitle)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(palette.label)
            Text(off ? text.statsOffBody : text.openBody)
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
}

private struct FaceContent: View {
    let s: WidgetSnapshot
    let text: WidgetText
    let family: WidgetFamily
    let look: WidgetLook
    let now: Date
    let dark: Bool
    let accented: Bool
    /// Renders outside WidgetKit can't draw a `Link`.
    var forcedLinksOff = false

    private var palette: WidgetPalette { WidgetPalette(look: look, dark: dark, accented: accented) }
    private var wood: Bool { look == .woodcut }
    private var small: Bool { family == .systemSmall }
    private var medium: Bool { family == .systemMedium }
    private var large: Bool { family == .systemLarge }
    private var top: Bool { s.nextRankName == nil }
    private var hasGlossary: Bool { !small && s.suggestion != nil }
    private var barWidth: CGFloat { small ? (wood ? 84 : 138) : (wood ? 242 : 332) }
    private var barY: CGFloat { small ? 126 : (medium && !hasGlossary ? 124 : 102) }
    private var textWidth: CGFloat { wood ? 88 : 138 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            header
            if small { nextRank } else { wordsToday }
            bar
            barLabels
            if large { largePart }
            if hasGlossary { glossaryLine }
            // Outside any `Link`, which could cut it off from what it blends with.
            WidgetPrints(s: s, family: family, look: look, ink: accented ? .glass : .hiddenOnPaper(dark: dark))
        }
    }

    // MARK: Header

    @ViewBuilder private var header: some View {
        if wood {
            star(14).at(16, 16)
        } else if small {
            Image(systemName: "sparkle")
                .font(.system(size: 16))
                .foregroundStyle(accented ? palette.label : palette.fill)
                .frame(width: 16, height: 16)
                .at(138, 16)
        }
        caption(small ? text.level(s.level) : text.levelOf(s.level)).at(wood ? 34 : 16, 16, width: small ? 120 : nil)
        let titleWidth: CGFloat = small ? 138 : (wood ? 244 : 210)
        // Over 12 characters the small title is drawn at 17 (SPEC.md).
        let size: CGFloat = small ? (s.rankName.count > 12 ? 17 : 20) : 24
        Text(s.rankName)
            .font(.system(size: size, weight: .bold))
            .tracking(-0.2)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(palette.label)
            .frame(width: titleWidth, height: small ? 24 : 28, alignment: .leading)
            .at(16, 34)
    }

    private func caption(_ string: String) -> some View {
        Text(string)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.66)
            .textCase(.uppercase)
            .lineLimit(1)
            .foregroundStyle(palette.secondary)
            .frame(height: 14, alignment: .leading)
    }

    @ViewBuilder private func star(_ size: CGFloat) -> some View {
        Image(accented ? "star-glass" : "star-gold", bundle: WidgetAssets.bundle)
            .resizable()
            .widgetAccentedRenderingMode(.fullColor)
            .frame(width: size, height: size)
    }

    // MARK: Small

    @ViewBuilder private var nextRank: some View {
        if let next = s.nextRankName {
            caption(text.next).frame(width: textWidth, alignment: .leading).at(16, 90)
            line(next, size: 12, height: 16, weight: .semibold, width: textWidth).at(16, 104)
        } else {
            line(text.madeIt, size: 12, height: 16, weight: .semibold, width: textWidth).at(16, 104)
        }
    }

    private func line(_ string: String, size: CGFloat, height: CGFloat, weight: Font.Weight = .regular, width: CGFloat) -> some View {
        Text(string)
            .font(.system(size: size, weight: weight))
            .lineLimit(1)
            .foregroundStyle(palette.label)
            .frame(width: width, height: height, alignment: .leading)
    }

    // MARK: Words today

    @ViewBuilder private var wordsToday: some View {
        let n = s.wordsToday(on: now)
        if wood {
            run(text.number(n), number: .system(size: 22, weight: .bold).monospacedDigit(), label: text.todayLabel(n))
                .lineLimit(1)
                .frame(width: 244, height: 26, alignment: .leading)
                .at(16, medium && !hasGlossary ? 74 : 68)
        } else {
            VStack(alignment: .trailing, spacing: 0) {
                Text(text.number(n))
                    .font(.system(size: 28, weight: .bold).monospacedDigit())
                    .foregroundStyle(palette.label)
                    .frame(height: 34)
                caption(n == 1 ? text.todayLabel(1) : text.todayCaption)
            }
            .frame(width: 332, alignment: .trailing)
            .at(16, 16)
        }
    }

    /// A bold number and a quieter label, one text run on one baseline, with a normal space.
    private func run(_ number: String, number font: Font, label: String) -> Text {
        var a = AttributedString(number)
        a.font = font
        a.foregroundColor = palette.label
        var b = AttributedString(" " + label)
        b.font = .system(size: 13)
        b.foregroundColor = palette.secondary
        return Text(a + b)
    }

    // MARK: Bar

    @ViewBuilder private var bar: some View {
        let progress = top ? 1 : min(1, max(0, s.progress))
        if wood && !accented {
            let name = small ? "84" : "242"
            ZStack(alignment: .leading) {
                Image("bar-empty-\(name)", bundle: WidgetAssets.bundle).resizable()
                Image("bar-fill-\(name)", bundle: WidgetAssets.bundle).resizable()
                    .mask(alignment: .leading) { Rectangle().frame(width: barWidth * progress) }
            }
            .frame(width: barWidth, height: 10)
            .at(16, barY)
        } else {
            ZStack(alignment: .leading) {
                Capsule().fill(palette.track)
                Capsule().fill(palette.fill)
                    .frame(width: progress == 0 ? 0 : max(barWidth * progress, 6))
                    .widgetAccentable()
            }
            .frame(width: barWidth, height: 6)
            .at(16, barY + 2)
        }
        if top && wood {
            star(14).at(16 + barWidth - 9, barY - 2)
        }
    }

    @ViewBuilder private var barLabels: some View {
        let toNext = (s.nextStart ?? s.words) - s.words
        if small {
            Text(top ? text.words(s.words) : text.toGo(toNext))
                .font(.system(size: 11).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .foregroundStyle(palette.secondary)
                .frame(width: textWidth, height: 14, alignment: .leading)
                .at(16, 140)
        } else {
            HStack(spacing: 8) {
                Text(top ? text.words(s.words) : text.ofWords(s.words, s.nextStart ?? s.words))
                Spacer(minLength: 0)
                Text(top ? text.madeIt : text.toRank(toNext, s.nextRankName ?? ""))
            }
            .font(.system(size: 11).monospacedDigit())
            .lineLimit(1)
            .foregroundStyle(palette.secondary)
            .frame(width: barWidth, height: 14)
            .at(16, barY + 16)
        }
    }

    // MARK: Large

    private var layout: (time: CGFloat, comparison: CGFloat, caption: CGFloat, grid: CGFloat) {
        hasGlossary ? (146, 168, 190, 208) : (150, 172, 198, 216)
    }

    @ViewBuilder private var largePart: some View {
        run(s.savedText, number: .system(size: 17, weight: .bold), label: text.saved)
            .lineLimit(1)
            .frame(width: 332, height: 22, alignment: .leading)
            .at(16, layout.time)
        Text(text.comparison)
            .font(.system(size: 11))
            .lineLimit(1)
            .foregroundStyle(palette.secondary)
            .frame(width: 332, height: 14, alignment: .leading)
            .at(16, layout.comparison)
        activityCaption.at(16, layout.caption)
        ActivityGrid(weeks: s.activity, colors: palette.activity).at(16, layout.grid)
        achievementRow.at(16, WidgetSnapshot.achievementY(glossary: hasGlossary))
    }

    private var isEmptyActivity: Bool { !s.activity.joined().contains { ($0 ?? 0) > 0 } }

    private var activityCaption: some View {
        HStack(spacing: 3) {
            caption(text.lastMonths)
            Spacer(minLength: 0)
            if isEmptyActivity {
                caption(text.fillsIn)
            } else {
                caption(text.less).padding(.trailing, 3)
                ForEach(0..<5, id: \.self) { step in
                    RoundedRectangle(cornerRadius: 2).fill(palette.activity[step]).frame(width: 8, height: 8)
                }
                caption(text.more).padding(.leading, 3)
            }
        }
        .frame(width: 332, height: 14)
    }

    @ViewBuilder private var achievementRow: some View {
        if let ready = s.ready {
            WidgetTapArea(link: .stamp(ready.id), live: forcedLinksOff == false) {
                row(name: ready.name) {
                    HStack(spacing: 4) {
                        if wood || accented {
                            star(11)
                        } else {
                            Image(systemName: "sparkle").font(.system(size: 11)).foregroundStyle(palette.fill).frame(width: 11, height: 11)
                        }
                        Text(text.readyToStamp)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.label)
                    }
                    .frame(height: 16)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .padding(.vertical, -4)
        } else if let latest = s.latest {
            row(name: latest.name) { secondLine(text.unlocked(day: latest.day, now: now)) }
        } else {
            row(name: s.firstAchievementName) { secondLine(text.firstStamp) }
        }
    }

    private func secondLine(_ string: String) -> some View {
        Text(string)
            .font(.system(size: 12))
            .lineLimit(1)
            .foregroundStyle(palette.secondary)
            .frame(height: 16)
    }

    /// The stamp itself is in `WidgetPrints`; this keeps its place.
    private func row(name: String, @ViewBuilder second: () -> some View) -> some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(palette.label)
                    .frame(height: 18)
                second()
            }
        }
        .frame(width: 332, height: 36, alignment: .leading)
    }

    // MARK: Glossary line

    @ViewBuilder private var glossaryLine: some View {
        if let suggestion = s.suggestion {
            let width: CGFloat = medium && wood ? 244 : 332
            WidgetTapArea(link: .suggestion(suggestion.id), live: forcedLinksOff == false) {
                HStack(spacing: 5) {
                    Image(systemName: "character.book.closed").font(.system(size: 12))
                    glossaryText(suggestion.term)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right").font(.system(size: 9))
                }
                .foregroundStyle(palette.secondary)
                .frame(width: width, height: 16)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(text.suggestionPrefix + " " + suggestion.term)
            .padding(.vertical, -6)
            .at(16, medium ? 138 : 350)
        }
    }

    private func glossaryText(_ term: String) -> Text {
        var prefix = AttributedString(text.suggestionPrefix + " ")
        prefix.font = .system(size: 12)
        prefix.foregroundColor = palette.secondary
        var word = AttributedString(term)
        word.font = .system(size: 12, weight: .semibold)
        word.foregroundColor = palette.label
        return Text(prefix + word)
    }
}

/// A part of the widget with its own link.
private struct WidgetTapArea<Content: View>: View {
    let link: WidgetLink
    let live: Bool
    @ViewBuilder var content: Content

    var body: some View {
        if live { Link(destination: link.url()) { content } } else { content }
    }
}

/// 27 columns of 7 squares, oldest week left, the busiest day full. A day still to come is empty.
private struct ActivityGrid: View {
    let weeks: [[Int?]]
    let colors: [Color]

    var body: some View {
        let peak = max(1, weeks.joined().compactMap { $0 }.max() ?? 1)
        Canvas { context, _ in
            for column in 0..<27 {
                for row in 0..<7 {
                    let words = weeks.indices.contains(column) && weeks[column].indices.contains(row) ? weeks[column][row] ?? 0 : 0
                    let rect = CGRect(x: CGFloat(column) * 12, y: CGFloat(row) * 12, width: 10, height: 10)
                    context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(colors[WidgetSnapshot.activityLevel(words, peak: peak)]))
                }
            }
        }
        .frame(width: 322, height: 82)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Places a view by the spec's coordinates: from the widget's corner, so 16 less inside the margins.
    fileprivate func at(_ x: CGFloat, _ y: CGFloat, width: CGFloat? = nil) -> some View {
        frame(width: width, alignment: .leading).offset(x: x - 16, y: y - 16)
    }
}
