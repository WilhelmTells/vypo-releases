import AppKit
import SwiftUI

/// Type of the onboarding: SF Pro sizes by token.
enum OBFont {
    static let heroTitle = Font.system(size: 26, weight: .bold)
    static let title = Font.system(size: 22, weight: .bold)
    static let bodyLarge = Font.system(size: 15)
    static let field = Font.system(size: 17)
    static let body = Font.system(size: 13)
    static let bodySemibold = Font.system(size: 13, weight: .semibold)
    static let secondary = Font.system(size: 12)
    static let secondarySemibold = Font.system(size: 12, weight: .semibold)
    static let caption = Font.system(size: 11)
}

/// The five button shapes of the spec. Primary is `app-accent-fill` with white text; the rest are bordered.
struct OBButtonStyle: ButtonStyle {
    enum Kind { case hero, primary, bordered, rowPrimary, rowBordered, small }
    var kind: Kind
    @Environment(\.isEnabled) private var enabled

    private var height: CGFloat {
        switch kind {
        case .hero: 32
        case .primary, .bordered: 28
        case .rowPrimary, .rowBordered: 24
        case .small: 22
        }
    }

    private var radius: CGFloat {
        switch kind {
        case .hero: 7
        case .small: 5
        default: 6
        }
    }

    private var filled: Bool { kind == .hero || kind == .primary || kind == .rowPrimary }

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        configuration.label
            .font(kind == .hero || kind == .primary ? .system(size: 13, weight: .medium)
                  : kind == .bordered ? OBFont.body : OBFont.secondary)
            .foregroundStyle(enabled ? (filled ? Color.white : Color.vyLabel) : Color.vyLabelTertiary)
            .padding(.horizontal, kind == .hero ? 20 : kind == .primary ? 16 : 10)
            .frame(minWidth: kind == .primary ? 104 : nil, minHeight: height, maxHeight: height)
            .background(shape.fill(!enabled ? Color.vyFillTrack : filled ? Color.vyAccentFill : Color.vyBgControl))
            .overlay {
                if enabled && !filled {
                    shape.strokeBorder(Color.vySeparator, lineWidth: 0.5)
                }
            }
            .shadow(color: .black.opacity(enabled && !filled ? 0.08 : 0), radius: 0.5, y: 1)
            .overlay { if configuration.isPressed { shape.fill(Color.black.opacity(0.12)) } }
            .contentShape(shape)
    }
}

extension ButtonStyle where Self == OBButtonStyle {
    static func ob(_ kind: OBButtonStyle.Kind) -> OBButtonStyle { OBButtonStyle(kind: kind) }
}

/// Title and one line of a step (22 / 28 bold, then 13 / 18 secondary).
struct OBTitle: View {
    var title: LocalizedStringKey
    var text: LocalizedStringKey?
    var centered = true

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(OBFont.title)
                .tracking(-0.2)
                .foregroundStyle(Color.vyLabel)
                .accessibilityAddTraits(.isHeader)
            if let text {
                Text(text)
                    .font(OBFont.body)
                    .foregroundStyle(Color.vyLabelSecondary)
                    .multilineTextAlignment(centered ? .center : .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
    }
}

/// A line that fades in with a 4 pt rise (status lines, results), or only fades with Reduce motion.
extension AnyTransition {
    static func statusLine(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 4))
    }
}

// MARK: Model ring

/// The progress ring of the path bar and the waiting area: stroke 3, track `fill-track`, round cap, from 12 o'clock.
struct ModelRing: View {
    var fraction: Double
    var size: CGFloat = 18
    var lineWidth: CGFloat = 3
    /// Pulses while the model is preparing.
    var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ring(opacity: 1)
            .overlay {
                if pulsing && !reduceMotion {
                    TimelineView(.animation) { context in
                        let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2
                        ring(opacity: 0.8 + 0.2 * cos(phase * 2 * .pi)).background(Color.vyBgWindow.opacity(0.0001))
                    }
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private func ring(opacity: Double) -> some View {
        ZStack {
            Circle().stroke(Color.vyFillTrack, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(fraction, 1)))
                .stroke(Color.vyAccent.opacity(opacity), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .linear(duration: 0.3), value: fraction)
        }
        .padding(lineWidth / 2)
    }
}

// MARK: Keycap

/// One key of the shortcut, 120 x 120 (SPEC: Keycaps).
struct Keycap: View {
    enum Content: Equatable {
        /// A modifier: its symbol top right, its name bottom left.
        case modifier(symbol: String, name: String)
        /// A letter or number: the character large in the middle.
        case character(String)
        /// fn: "fn" top right and the globe bottom left.
        case fn
    }

    var content: Content
    var pressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let depth: CGFloat = 4
        // Pressed keys sink by their depth (not with Reduce motion: the ring says it).
        let sink = pressed && !reduceMotion ? depth : 0
        ZStack(alignment: .top) {
            shape.fill(Color.vyFillTrack).frame(width: 120, height: 120).offset(y: depth)
            ZStack {
                shape.fill(Color.vyBgControl)
                shape.strokeBorder(Color.vyBorderControl, lineWidth: 0.5)
                label
                if pressed { shape.strokeBorder(Color.vyAccent, lineWidth: 2) }
            }
            .frame(width: 120, height: 120)
            .offset(y: sink)
        }
        .frame(width: 120, height: 124)
        .animation(reduceMotion ? nil : .easeOut(duration: pressed ? 0.08 : 0.12), value: pressed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityName)
    }

    @ViewBuilder private var label: some View {
        switch content {
        case .modifier(let symbol, let name):
            ZStack {
                Text(symbol).font(.system(size: 18)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(12)
                Text(name).font(.system(size: 12)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(12)
            }
            .foregroundStyle(Color.vyLabel)
        case .character(let c):
            Text(c).font(.system(size: 40, weight: .regular)).foregroundStyle(Color.vyLabel)
        case .fn:
            ZStack {
                Text("fn").font(.system(size: 18)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(12)
                Image(systemName: "globe").font(.system(size: 18)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(12)
            }
            .foregroundStyle(Color.vyLabel)
        }
    }

    private var accessibilityName: String {
        switch content {
        case .modifier(_, let name): name
        case .character(let c): c
        case .fn: "fn"
        }
    }
}

extension DictationKey {
    /// The keycaps of the key: fn, Right Option as one "⌥ option", or the recorded shortcut (⌥G = two).
    @MainActor var onboardingKeycaps: [Keycap.Content] {
        switch self {
        case .fn: return [.fn]
        case .rightOption: return [.modifier(symbol: "⌥", name: "option")]
        case .rightCommand: return [.modifier(symbol: "⌘", name: "command")]
        case .rightControl: return [.modifier(symbol: "⌃", name: "control")]
        case .custom:
            let names = ["⌃": "control", "⌥": "option", "⇧": "shift", "⌘": "command"]
            return keyCaps.map { glyph in
                names[glyph].map { Keycap.Content.modifier(symbol: glyph, name: $0) } ?? .character(glyph)
            }
        }
    }
}

// MARK: Stage and glass pill

/// A bar of the stage pill: `level` 0 to 1 lifts it between `minHeight` and `maxHeight`.
struct StageBars: View {
    var barWidth: CGFloat
    var gap: CGFloat
    var minHeight: CGFloat
    var maxHeight: CGFloat
    var level: () -> Float
    /// Flat at 55 % opacity (silent or ready).
    var flat: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            Canvas { ctx, size in
                let t = context.date.timeIntervalSinceReferenceDate
                let voice = flat ? 0 : min(1, Double(level()) * 1.5)
                for i in 0..<VoiceBars.count {
                    let shape = 0.45 + 0.55 * sin(Double(i + 1) / Double(VoiceBars.count + 1) * .pi)
                    let wobble = 0.5 + 0.5 * sin(t * 6.5 + Double(i) * 1.3)
                    let lift = flat ? 0 : min(1, voice * (0.55 + 0.45 * wobble))
                    let h = minHeight + (maxHeight - minHeight) * shape * lift
                    let x = CGFloat(i) * (barWidth + gap)
                    let rect = CGRect(x: x, y: (size.height - h) / 2, width: barWidth, height: h)
                    // Silent bars stay flat at 55 %.
                    ctx.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2),
                             with: .color(.white.opacity(flat || voice < 0.03 ? 0.55 : 1)))
                }
            }
        }
        .frame(width: CGFloat(VoiceBars.count) * barWidth + CGFloat(VoiceBars.count - 1) * gap, height: maxHeight)
    }
}

/// Three dots that travel while the text is made.
struct StageDots: View {
    var dot: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            HStack(spacing: dot) {
                ForEach(0..<3, id: \.self) { i in
                    let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9
                    let lift = reduceMotion ? 0.5 : max(0, sin((phase - Double(i) * 0.15) * 2 * .pi))
                    Circle().fill(.white).frame(width: dot, height: dot)
                        .opacity(0.45 + 0.55 * lift)
                        .offset(y: -dot * 0.6 * lift)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// The product pill with the background "Glass": the same `glassEffect` as `PillView`, drawn dark so its
/// white wave reads on the night stage in both appearances.
struct GlassStagePill: View {
    enum Content: Equatable { case bars(flat: Bool), dots }

    var size: CGSize
    var content: Content
    var level: () -> Float
    var barWidth: CGFloat
    var gap: CGFloat
    var minHeight: CGFloat
    var maxHeight: CGFloat

    var body: some View {
        ZStack {
            switch content {
            case .bars(let flat):
                StageBars(barWidth: barWidth, gap: gap, minHeight: minHeight, maxHeight: maxHeight, level: level, flat: flat)
            case .dots:
                StageDots(dot: barWidth)
            }
        }
        .frame(width: size.width, height: size.height)
        .glassEffect(.regular, in: Capsule())
        .overlay(Capsule().inset(by: 0.25).stroke(.white.opacity(0.35), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 8)
        .environment(\.colorScheme, .dark)
    }
}

/// The woodcut stage (460 x 130) the pill sits on: night in step 3, early dawn in step 6.
struct WoodcutStage: View {
    var dawn = false
    var cropHeight: CGFloat = 130

    /// Loads and decodes the night stage once, so the Microphone step doesn't do it during its transition (the first
    /// load took 10–33 ms, 2026-10-29). Called while the Permissions step rests.
    static func preload() {
        _ = NSImage(named: "Onboarding/woodcut-stage")?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    var body: some View {
        Image(dawn ? "Onboarding/woodcut-stage-dawn" : "Onboarding/woodcut-stage")
            .resizable()
            .interpolation(.high)
            .frame(width: 460, height: 130)
            // Dawn: anchored 80 % down so the castle stays whole in the 104 high crop.
            .offset(y: cropHeight < 130 ? -(130 - cropHeight) * 0.8 : 0)
            .frame(width: 460, height: cropHeight, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.vySeparator, lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

/// The paper shadow of the woodcut figures: hard, no blur.
extension View {
    func paperShadow(x: CGFloat = 1.5, y: CGFloat = 2, opacity: Double = 0.42) -> some View {
        shadow(color: Color(red: 28 / 255, green: 16 / 255, blue: 6 / 255).opacity(opacity), radius: 0, x: x, y: y)
    }
}

/// An outlined badge ("Early version").
struct OBBadge: View {
    var text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.vyLabelSecondary)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).inset(by: 0.5).stroke(Color.vySeparator, lineWidth: 1))
    }
}
