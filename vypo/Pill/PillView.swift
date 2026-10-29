import SwiftUI

/// Text typed into the pill's glossary field (§6.5).
@MainActor
@Observable
final class PillAddModel {
    var text = ""
    /// Bumped to move focus into the field.
    var focusRequest = 0
}

/// Callbacks from the floating pill to its controller.
struct PillActions {
    var stop: () -> Void = {}
    var tap: () -> Void = {}
    var confirmAdd: () -> Void = {}
    var cancelAdd: () -> Void = {}
    var dragChanged: () -> Void = {}
    var dragEnded: () -> Void = {}
}

/// The pill's colors for one surface (§6.2). Dark is the default HUD, the same in light and dark mode,
/// so it reads on any window.
struct PillInk {
    var surface: Color
    var edge: Color
    var primary: Color
    var secondary: Color
    var track: Color
    var scheme: ColorScheme

    static let dark = PillInk(surface: Color(white: 0.1).opacity(0.94), edge: .white.opacity(0.14), primary: .white.opacity(0.92),
                              secondary: .white.opacity(0.6), track: .white.opacity(0.14), scheme: .dark)
    static let light = PillInk(surface: Color(white: 0.98).opacity(0.96), edge: .black.opacity(0.12), primary: .black.opacity(0.82),
                               secondary: .black.opacity(0.5), track: .black.opacity(0.08), scheme: .light)

    /// Glass has no fill of its own; its ink follows the appearance like the system's glass does.
    static func glass(_ scheme: ColorScheme) -> PillInk {
        var ink = scheme == .dark ? dark : light
        ink.surface = .clear
        ink.edge = (scheme == .dark ? Color.white : .black).opacity(0.1)
        return ink
    }
}

extension PillBackground {
    func ink(in scheme: ColorScheme) -> PillInk {
        switch self {
        case .automatic: scheme == .dark ? .dark : .light
        case .dark: .dark
        case .light: .light
        case .glass: .glass(scheme)
        }
    }

    var name: String {
        switch self {
        case .automatic: String(localized: "Automatic")
        case .dark: String(localized: "Dark")
        case .light: String(localized: "Light")
        case .glass: String(localized: "Glass")
        }
    }
}

extension PillColor {
    func color(on ink: PillInk, custom: Color) -> Color {
        switch self {
        case .white: ink.primary
        case .orange: Color.vyAccent
        case .blue: Color(nsColor: .systemBlue)
        case .purple: Color(nsColor: .systemPurple)
        case .pink: Color(nsColor: .systemPink)
        case .green: Color(nsColor: .systemGreen)
        case .custom: custom
        }
    }

    var name: String {
        switch self {
        case .white: String(localized: "Neutral")
        case .blue: String(localized: "Blue")
        case .purple: String(localized: "Purple")
        case .pink: String(localized: "Pink")
        case .orange: String(localized: "Orange")
        case .green: String(localized: "Green")
        case .custom: String(localized: "Custom color")
        }
    }
}

/// The pill (§6). `size` is the pill's own size; the view is laid out at that size and centered.
struct PillView: View {
    var mode: PillMode
    /// The colour of the voice bars.
    var color: PillColor = .white
    var customColor: Color = .vyAccent
    var surface: PillBackground = .dark
    var level: () -> Float = { 0 }
    var size: CGSize
    var addModel: PillAddModel?
    var actions = PillActions()
    var interactive = true
    var showsShadow = true
    /// The appearance around the pill, for `automatic` and `glass`.
    @Environment(\.colorScheme) private var outerScheme

    private var ink: PillInk { surface.ink(in: outerScheme) }

    var body: some View {
        ZStack {
            background
            content
                .frame(width: size.width, height: size.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Capsule().fill(ink.surface))
        .glassEffect(surface == .glass ? .regular : .identity, in: Capsule())
        .overlay(Capsule().strokeBorder(ink.edge, lineWidth: 0.5))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(showsShadow ? (ink.scheme == .dark ? 0.28 : 0.16) : 0), radius: 6, y: 2)
        .environment(\.colorScheme, ink.scheme)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(mode.accessibilityLabel)
        .accessibilityAddTraits(.updatesFrequently)
    }

    @ViewBuilder private var background: some View {
        let shape = Capsule()
        if interactive {
            shape.fill(Color.clear)
                .contentShape(shape)
                .gesture(
                    DragGesture(minimumDistance: 2, coordinateSpace: .global)
                        .onChanged { _ in actions.dragChanged() }
                        .onEnded { _ in actions.dragEnded() }
                )
                .onTapGesture { actions.tap() }
        } else {
            shape.fill(Color.clear)
        }
    }

    @ViewBuilder private var content: some View {
        switch mode {
        case .collapsed, .ready:
            EmptyView()
        case .listening, .processing:
            row(leading: PillMetrics.padding, trailing: PillMetrics.padding) {
                VoiceBars(processing: mode == .processing, color: color.color(on: ink, custom: customColor), level: level)
            }
        case .handsfree:
            row(leading: PillMetrics.padding, trailing: 5) {
                VoiceBars(processing: false, color: color.color(on: ink, custom: customColor), level: level)
                Button(action: actions.stop) {
                    ZStack {
                        Circle().fill(ink.track)
                        RoundedRectangle(cornerRadius: 2).fill(ink.primary).frame(width: 8, height: 8)
                    }
                    .frame(width: PillMetrics.stopSize, height: PillMetrics.stopSize)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop recording")
            }
        case .error(let error):
            row(leading: PillMetrics.padding, trailing: PillMetrics.padding) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(nsColor: .systemYellow))
                    .frame(width: 14)
                    .accessibilityHidden(true)
                Text(error.message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ink.primary)
                    .fixedSize()
            }
            .allowsHitTesting(false)
        case .add:
            row(leading: 10, trailing: 5, spacing: 6) {
                Image(systemName: "book")
                    .font(.system(size: 13))
                    .foregroundStyle(ink.secondary)
                    .frame(width: 13)
                    .accessibilityHidden(true)
                if let addModel {
                    PillAddField(model: addModel, ink: ink, confirm: actions.confirmAdd, cancel: actions.cancelAdd)
                } else {
                    Capsule().fill(ink.track).frame(width: 150, height: 24)
                }
                Button(action: actions.confirmAdd) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.vyOnAccent)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.vyAccent))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add to glossary")
            }
        case .added(let notice):
            row(leading: PillMetrics.padding, trailing: PillMetrics.padding, spacing: 6) {
                // Still at work: waving dots, not a check.
                if notice == .collectingDiagnostics {
                    WorkingDots(color: ink.secondary)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .systemGreen))
                        .frame(width: 13)
                        .accessibilityHidden(true)
                }
                noticeText(notice)
                    .font(.system(size: 12))
                    .foregroundStyle(ink.primary)
                    .fixedSize()
            }
            .allowsHitTesting(false)
        }
    }

    private func noticeText(_ notice: PillNotice) -> Text {
        switch notice {
        case .termAdded(let term): Text("\(Text(term).fontWeight(.semibold)) added")
        case .copied: Text("Copied")
        case .onClipboard: Text("On clipboard")
        case .undone: Text("Undone")
        case .savedToHistory: Text("Saved to History")
        case .collectingDiagnostics: Text("Collecting diagnostics…")
        }
    }

    private func row<C: View>(leading: CGFloat, trailing: CGFloat, spacing: CGFloat = PillMetrics.gap, @ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: spacing) { c() }
            .padding(.leading, leading)
            .padding(.trailing, trailing)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// The text field in the `add` state.
private struct PillAddField: View {
    @Bindable var model: PillAddModel
    var ink: PillInk
    var confirm: () -> Void
    var cancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Add to glossary", text: $model.text)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(ink.primary)
            .padding(.horizontal, 10)
            .frame(width: 150, height: 24)
            .background(Capsule().fill(ink.track))
            .focused($focused)
            .onSubmit(confirm)
            .onExitCommand(perform: cancel)
            .accessibilityLabel("Glossary term")
            .onChange(of: model.focusRequest, initial: true) {
                focused = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                }
            }
    }
}

/// Nine bars (§6.3). While recording they rise with the voice and keep a slight motion of their own;
/// while processing they settle into dots with a light sweeping across them.
struct VoiceBars: View {
    var processing = false
    var color: Color = PillInk.dark.primary
    var level: () -> Float

    static let count = 9
    static let barWidth: CGFloat = 3
    static let spacing: CGFloat = 3
    static let minHeight: CGFloat = 3
    static let maxHeight: CGFloat = 18
    static var width: CGFloat { CGFloat(count) * barWidth + CGFloat(count - 1) * spacing }

    /// When `processing` last flipped; the bars morph over 0.3 s from there.
    @State private var changedAt = Date.distantPast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            Canvas { ctx, size in
                let t = context.date.timeIntervalSinceReferenceDate
                let k = min(max(context.date.timeIntervalSince(changedAt) / 0.3, 0), 1)
                let eased = k * k * (3 - 2 * k)
                let settle = processing ? eased : 1 - eased
                let voice = reduceMotion ? 0.4 : min(1, Double(level()) * 1.5)
                for i in 0..<Self.count {
                    let height = Self.height(bar: i, t: t, voice: voice, settle: settle, still: reduceMotion)
                    let rect = CGRect(x: CGFloat(i) * (Self.barWidth + Self.spacing), y: (size.height - height) / 2,
                                      width: Self.barWidth, height: height)
                    let sweep = reduceMotion ? 1 : 0.5 + 0.5 * sin(t * 5 - Double(i) * 0.7)
                    let opacity = 1 - settle * 0.7 * (1 - sweep)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: Self.barWidth / 2), with: .color(color.opacity(opacity)))
                }
            }
        }
        .frame(width: Self.width, height: Self.maxHeight)
        .onChange(of: processing) { changedAt = Date() }
        .accessibilityHidden(true)
    }

    /// Taller in the middle; `voice` 0–1 lifts the bars, `settle` 0–1 pulls them down to dots.
    static func height(bar i: Int, t: Double, voice: Double, settle: Double, still: Bool) -> CGFloat {
        let shape = 0.45 + 0.55 * sin(Double(i + 1) / Double(count + 1) * .pi)
        let wobble = still ? 0.5 : 0.5 + 0.5 * sin(t * 6.5 + Double(i) * 1.3)
        let lift = min(1, 0.12 * wobble + voice * (0.55 + 0.45 * wobble))
        let recording = minHeight + (maxHeight - minHeight) * shape * lift
        return recording + (minHeight - recording) * settle
    }
}


/// Three dots that rise and brighten one after the other, like a typing indicator (1.1 s a round). Same size and
/// width as the ellipsis symbol it replaces, so the pill doesn't jump. With Reduce Motion the dots only pulse slowly.
struct WorkingDots: View {
    var color: Color
    /// Fixes the time (seconds) instead of following the clock, for snapshots.
    var time: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let period = 1.1
    static let pulsePeriod = 2.4

    /// Rise and brightness of one dot, 0…1.
    static func lift(dot: Int, at time: Double) -> Double {
        let phase = (time / period - Double(dot) * 0.18).truncatingRemainder(dividingBy: 1)
        let x = phase < 0 ? phase + 1 : phase
        return x < 0.5 ? 0.5 - 0.5 * cos(x * 4 * .pi) : 0
    }

    var body: some View {
        if let time {
            dots(at: time)
        } else {
            TimelineView(.animation) { context in
                dots(at: context.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func dots(at time: Double) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                let lift = reduceMotion ? 0 : Self.lift(dot: i, at: time)
                let pulse = reduceMotion ? 0.55 + 0.45 * (0.5 - 0.5 * cos(time * 2 * .pi / Self.pulsePeriod)) : 1
                Circle()
                    .fill(color)
                    .frame(width: 3, height: 3)
                    .opacity(reduceMotion ? pulse : 0.35 + 0.65 * lift)
                    .offset(y: -2 * lift)
            }
        }
        .frame(width: 13, height: 12)
        .accessibilityHidden(true)
    }
}
