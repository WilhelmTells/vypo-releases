import SwiftUI

enum BadgeTone {
    case neutral, success, accent, warning, danger

    var color: Color {
        switch self {
        case .neutral: .vyLabelSecondary
        case .success: .vySuccess
        case .accent: .vyAccent
        case .warning: .vyWarning
        case .danger: .vyDanger
        }
    }
}

/// Outlined capsule with one uppercase word (Badge component).
struct Badge: View {
    var text: LocalizedStringKey
    var tone: BadgeTone = .neutral
    var symbol: String?
    /// Lets the badge shrink slightly in tight rows instead of overflowing.
    var compressible = false

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 8, weight: .bold))
            }
            Text(text).textCase(.uppercase)
                .font(.vyBadge)
                .tracking(0.3)
                .lineLimit(1)
                .minimumScaleFactor(compressible ? 0.75 : 1)
        }
        .foregroundStyle(tone.color)
        .padding(.vertical, 2)
        .padding(.horizontal, compressible ? 5 : 7)
        .overlay(Capsule().strokeBorder(tone.color, lineWidth: 1))
        .fixedSize(horizontal: !compressible, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

/// Key caps such as fn or ⌃ ⌥ L (KeyCap component).
struct KeyCaps: View {
    var keys: [String]
    var small = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                cap(key)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shortcut " + keys.joined(separator: " "))
    }

    private func cap(_ key: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: 5)
        let size: CGFloat = small ? 18 : 22
        return Text(key)
            .font(.system(size: small ? 10 : 11, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.vyLabel)
            .padding(.horizontal, small ? 4 : 6)
            .frame(minWidth: size, minHeight: size)
            .background(shape.fill(Color.vyBgControl))
            .overlay(shape.strokeBorder(Color.vyBorderControl, lineWidth: 1))
            .shadow(color: Color.vyBorderControl, radius: 0, x: 0, y: 1)
    }
}

/// A row label with an optional description below it (FormRow).
struct RowLabel: View {
    var title: LocalizedStringKey
    var description: LocalizedStringKey?
    var strong = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(strong ? .headline : .body)
                .foregroundStyle(Color.vyLabel)
            if let description {
                Text(description)
                    .font(.callout)
                    .foregroundStyle(Color.vyLabelSecondary)
            }
        }
    }
}

/// The credit line under a model's name: who made it, what it is based on, and its license (CC BY 4.0
/// asks for exactly that). The full chain is in THIRD_PARTY_NOTICES.md.
struct ModelAttribution: View {
    static let license = URL(string: "https://creativecommons.org/licenses/by/4.0/")!

    var body: some View {
        (Text("By moondream, based on NVIDIA Parakeet TDT 0.6B v3, ") + Text(link))
            .font(.caption)
            .foregroundStyle(Color.vyLabelSecondary)
            .tint(Color.vyLabelSecondary)
    }

    private var link: AttributedString {
        var s = AttributedString("CC BY 4.0")
        s.link = Self.license
        s.underlineStyle = .single
        return s
    }
}

/// A 22 px rounded icon tile.
struct IconTile: View {
    var symbol: String
    var tint: Color = .vyLabel

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12))
            .foregroundStyle(tint)
            .frame(width: 22, height: 22)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.vyFillTrack))
            .accessibilityHidden(true)
    }
}

/// Settings pane title and lead sentence (§15).
struct PaneHeader: View {
    var pane: SettingsPane

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(pane.title)
                .font(.title.bold())
                .foregroundStyle(Color.vyLabel)
            Text(pane.lead)
                .font(.callout)
                .foregroundStyle(Color.vyLabelSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textCase(nil)
        .padding(.bottom, Space.s2)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The first section header of a pane: title, lead, optional extra content, then the group title.
struct PaneSectionHeader<Extra: View>: View {
    var pane: SettingsPane
    var title: LocalizedStringKey?
    @ViewBuilder var extra: Extra

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            PaneHeader(pane: pane)
            extra
            if let title {
                Text(title).padding(.top, Space.s1)
            }
        }
        .padding(.bottom, Space.s1)
    }
}

extension PaneSectionHeader where Extra == EmptyView {
    init(pane: SettingsPane, title: LocalizedStringKey? = nil) {
        self.init(pane: pane, title: title) { EmptyView() }
    }
}

/// “Add {term} to your glossary?” after a fix in History (GlossarySuggestion component).
struct SuggestionBanner: View {
    enum Content: Equatable {
        case offer(GlossarySuggestion)
        case added(String)
    }

    var content: Content
    var onAdd: () -> Void = {}
    var onDismiss: () -> Void = {}

    var body: some View {
        HStack(spacing: Space.s3) {
            switch content {
            case .offer(let s):
                IconTile(symbol: "sparkles", tint: .vyAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add \(Text(s.term).fontWeight(.semibold)) to your glossary?")
                        .foregroundStyle(Color.vyLabel)
                    HStack(spacing: 4) {
                        Text(s.heard).strikethrough()
                        Image(systemName: "arrow.right").font(.system(size: 9)).accessibilityLabel("becomes")
                        Text(s.term + (s.count > 1 ? ", fixed \(s.count)×" : ""))
                    }
                    .font(.callout)
                    .foregroundStyle(Color.vyLabelSecondary)
                }
                Spacer(minLength: 0)
                Button("Not now", action: onDismiss).buttonStyle(.plain).foregroundStyle(Color.vyAccent)
                Button("Add", action: onAdd).buttonStyle(.borderedProminent)
            case .added(let term):
                Image(systemName: "checkmark").foregroundStyle(Color.vySuccess).accessibilityHidden(true)
                Text("\(Text(term).fontWeight(.semibold)) added to your glossary.")
                    .foregroundStyle(Color.vyLabel)
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, Space.s3)
        .background(RoundedRectangle(cornerRadius: Radius.md).fill(Color.vyBgGroup))
        .overlay {
            if case .offer = content {
                RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Color.vyAccent, lineWidth: 1)
            } else {
                RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Color.vySeparator, lineWidth: 0.5)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Glossary suggestion")
    }
}

enum Formatting {
    /// "2 min ago" within a day, "Yesterday", else a date (§13), in the language vypo is shown in.
    static func relative(_ date: Date, now: Date = Date()) -> String {
        if now.timeIntervalSince(date) < 86_400 {
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .short
            f.locale = uiLocale
            return f.localizedString(for: date, relativeTo: now).replacingOccurrences(of: ".", with: "")
        }
        if Calendar.current.isDateInYesterday(date) { return String(localized: "Yesterday") }
        return date.formatted(.dateTime.month(.abbreviated).day().locale(uiLocale))
    }

    /// The locale of vypo's own language (System / English / Deutsch), not the region's.
    static var uiLocale: Locale { Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en") }

    /// Short weekday names, Sunday first, in vypo's language.
    static var weekdaySymbols: [String] {
        var calendar = Calendar.current
        calendar.locale = uiLocale
        return calendar.shortWeekdaySymbols
    }

    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}

/// A soft card: its fill comes from the background (white in light mode, a few percent of white in
/// dark), a faint shadow instead of an outline in light mode and a hint of top light in dark, with
/// continuous corners. Hover lifts it a little: lighter in dark mode, a light grey tint in light mode.
struct SoftCard: ViewModifier {
    var hovered = false
    @Environment(\.colorScheme) private var scheme

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.md + 2, style: .continuous) }

    /// White in light mode; hovered, the grey of a 4 % black veil over it (a fill behind the content, so clicks on
    /// the icons are never swallowed).
    static let lightHoverFill = Color(white: 0.955)

    func body(content: Content) -> some View {
        let dark = scheme == .dark
        content
            .background(
                shape.fill(dark ? Color.white.opacity(hovered ? 0.085 : 0.055) : (hovered ? Self.lightHoverFill : Color.white))
                    .shadow(color: .black.opacity(dark ? 0 : (hovered ? 0.09 : 0.05)), radius: hovered ? 6 : 4, y: 1)
            )
            .overlay {
                if dark {
                    shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.07), .clear], startPoint: .top, endPoint: .center),
                                       lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(shape)
    }
}

extension View {
    func softCard(hovered: Bool = false) -> some View { modifier(SoftCard(hovered: hovered)) }
}

/// Bordered button with a red label for destructive actions (Button component, `destructive`).
struct DestructiveButton: View {
    var title: LocalizedStringKey
    var action: () -> Void

    init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(role: .destructive, action: action) {
            Text(title).foregroundStyle(Color.vyDanger)
        }
        .buttonStyle(.bordered)
    }
}

/// 4 px accent bar on fill-track.
struct ProgressBar: View {
    var value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.vyFillTrack)
                Capsule().fill(Color.vyAccent).frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityValue("\(Int(value * 100)) percent")
    }
}
