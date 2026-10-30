import SwiftUI

/// The achievements card on the Stats pane, under the level card (`design/achievements/final/vypo-achievements/`).
/// It reads the data layer and calls its `stamp`; nothing stamps by itself. One press per click, then rest.
/// Its header row folds it to that row and back; the setting remembers which.
struct AchievementsCard: View {
    let store: AchievementStore
    @Binding var expanded: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var windowVisible = false
    @State private var presses: [AchievementID: StampPress] = [:]

    /// The pane is on screen in a visible window (the Settings window is kept when closed).
    private var visible: Bool { appeared && windowVisible }

    var body: some View {
        AchievementsCardLayout(content: AchievementCardContent(store.all), presses: presses, animating: visible,
                               expanded: expanded, onToggle: toggle) { slot in
            stamp(slot)
        }
        .background(WindowVisibilityReader { windowVisible = $0 })
        .onAppear { appeared = true }
        .onDisappear {
            appeared = false
            presses = [:]
        }
    }

    /// A short standard animation; none with Reduce Motion.
    private func toggle() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { expanded.toggle() }
        if !expanded { presses = [:] }
    }

    /// Stamps every ready tier of the slot and plays the press over the old print (vermilion for a first stamp,
    /// bronze for a tier-up). The slot takes no click while its press plays.
    private func stamp(_ slot: AchievementSlot) {
        guard let face = slot.face, presses[slot.id] == nil else { return }
        let press = StampPress(from: slot.art, to: slot.stampedArt, face: face, start: Date(), reduced: reduceMotion)
        presses[slot.id] = press
        store.stamp(slot.id)
        Task {
            try? await Task.sleep(for: .seconds(press.reduced ? StampMotion.reducedDuration : StampMotion.duration))
            if presses[slot.id] == press { presses[slot.id] = nil }
        }
    }
}

/// A press being played on one slot.
struct StampPress: Equatable {
    var from: AchievementArt
    var to: AchievementArt
    var face: StampFace
    var start: Date
    var reduced: Bool
}

/// Colours of the card (CARD.md): woodcut paper, unlike the pane's other cards.
enum AchievementPaper {
    static func background(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: "#1D1711")! : Color(hex: "#F3E9CF")! }
    static func label(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: "#F3E9CF")! : Color(hex: "#1D1711")! }
    static func secondary(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: "#B8AD95")! : Color(hex: "#5A4F42")! }
}

/// The card's face: header, grid, secrets line and the hover popover. Shared by the card and the snapshots.
struct AchievementsCardLayout: View {
    static let columns = 8
    static let stampSize: CGFloat = 60
    static let minGap: CGFloat = 10
    /// Room above the first row for a ready tool (16 section gap + 22).
    static let gridTop: CGFloat = 38
    static let rowGap: CGFloat = 32
    static let maxWidth: CGFloat = LevelSceneGeometry.artWidth
    /// Above and below the header row while folded.
    static let foldedPadding: CGFloat = 9

    var content: AchievementCardContent
    var presses: [AchievementID: StampPress] = [:]
    var animating = true
    /// Snapshots: the popover of this one, without hovering.
    var popover: AchievementID?
    /// Folded: only the header row.
    var expanded = true
    /// Clicking the header row; nil (snapshots) makes it plain text.
    var onToggle: (() -> Void)?
    /// Whether the last row's popover has room below the card (other cards follow); otherwise it opens above.
    var roomBelow = true
    #if DEBUG
    /// Snapshots of the whole Stats pane: a popover shown as if hovered.
    static var snapshotPopover: AchievementID?
    #endif
    var onStamp: (AchievementSlot) -> Void = { _ in }

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered: AchievementID?
    @State private var shownPopover: AchievementID?

    /// The stamp size and column gap for the grid's width: 60 pt with at least 20 between them from 620 pt on;
    /// narrower, the gap shrinks to 10 and then the stamps.
    static func metrics(width: CGFloat) -> (size: CGFloat, gap: CGFloat) {
        let n = CGFloat(columns)
        let size = min(stampSize, max(24, (width - (n - 1) * minGap) / n))
        return (size, max(minGap, (width - n * size) / (n - 1)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if expanded {
                grid.transition(.opacity)
            }
        }
        // Folded, a quieter bar of about 36 pt.
        .padding(.top, expanded ? 16 : Self.foldedPadding)
        .padding(.horizontal, 20)
        .padding(.bottom, expanded ? 18 : Self.foldedPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AchievementPaper.background(scheme))
        // Stars may leave their slot, not the card.
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(scheme == .dark ? Color.white.opacity(contrast == .increased ? 0.35 : 0.1)
                              : Color.black.opacity(contrast == .increased ? 0.35 : 0.1), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.1), radius: 1, y: 1)
        .overlayPreferenceValue(SlotBoundsKey.self) { anchors in
            GeometryReader { proxy in
                if expanded, let id = popover ?? Self.debugPopover ?? shownPopover, let anchor = anchors[id],
                   let status = content.slots.first(where: { $0.id == id })?.status {
                    let r = proxy[anchor]
                    let x = min(max(r.midX - AchievementPopover.width / 2, 20), proxy.size.width - 20 - AchievementPopover.width)
                    let popover = AchievementPopover(text: AchievementText.popover(status, locale: Formatting.uiLocale))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    // Without room below (the card last on a pane, over AppKit rows that draw over anything reaching
                    // into them) the last row's popover opens above the stamp.
                    if Self.opensAbove(r, lastRowTop: anchors.values.map { proxy[$0].minY }.max() ?? r.minY, roomBelow: roomBelow) {
                        popover
                            .frame(width: AchievementPopover.width, height: max(0, r.minY - 12), alignment: .bottom)
                            .offset(x: x)
                    } else {
                        popover.offset(x: x, y: r.maxY + 12)
                    }
                }
            }
        }
        .frame(maxWidth: Self.maxWidth)
        .frame(maxWidth: .infinity)
        .task(id: hovered) {
            guard let id = hovered else { return shownPopover = nil }
            // The popover comes after a short rest on the stamp, at once with Reduce Motion; no fade.
            if !reduceMotion { try? await Task.sleep(for: .seconds(HoverTilt.popoverDelay)) }
            guard !Task.isCancelled else { return }
            shownPopover = id
        }
    }

    /// Title, counter and (with `onToggle`) the chevron; the whole row folds and unfolds the card. Folded, the
    /// “… ready to stamp” part is in the accent colour.
    @ViewBuilder private var header: some View {
        // Open: title and counter on one baseline (CARD.md); folded: everything centred in the bar.
        let row = HStack(alignment: expanded ? .firstTextBaseline : .center, spacing: Space.s2) {
            Text("Achievements")
                .font(expanded ? .system(size: 17, weight: .bold) : .system(size: 15, weight: .semibold))
                .foregroundStyle(AchievementPaper.label(scheme))
                .capCentered(size: 15, weight: .semibold)
            Spacer(minLength: Space.s2)
            counter
                .textCase(.uppercase)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.66)
                .monospacedDigit()
                .capCentered(size: 11, weight: .semibold)
            if onToggle != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(secondary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 14)
                    .accessibilityHidden(true)
            }
        }
        if let onToggle {
            Button(action: onToggle) { row.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityLabel("Achievements")
                .accessibilityValue(Text(verbatim: "\(content.counter), \(expanded ? String(localized: "expanded") : String(localized: "collapsed"))"))
                .accessibilityHint(expanded ? "Collapses the achievements." : "Expands the achievements.")
        } else {
            row.accessibilityElement(children: .combine)
        }
    }

    private var counter: Text {
        let reached = Text(content.reachedPart).foregroundStyle(secondary)
        guard let ready = content.readyPart else { return reached }
        let tail = Text(ready).foregroundStyle(expanded ? secondary : Color.vyAccent)
        return reached + Text(verbatim: ", ").foregroundStyle(secondary) + tail
    }

    private var grid: some View {
        VStack(alignment: .leading, spacing: 0) {
            AchievementGrid {
                ForEach(content.slots) { slot in
                    GeometryReader { geo in
                        AchievementSlotView(slot: slot, size: geo.size.width, press: presses[slot.id], animating: animating,
                                            onHover: { hover(slot.id, $0) }, onStamp: { onStamp(slot) })
                    }
                    .anchorPreference(key: SlotBoundsKey.self, value: .bounds) { [slot.id: $0] }
                }
            }
            .padding(.top, content.slots.isEmpty ? 0 : Self.gridTop)
            if let secrets = content.secrets {
                HStack(spacing: Space.s2) {
                    Circle()
                        .stroke(secondary, style: StrokeStyle(lineWidth: 1.2, dash: [2.2, 1.8]))
                        .frame(width: 15, height: 15)
                        .frame(width: 16, height: 16)
                        .accessibilityHidden(true)
                    Text(secrets)
                        .font(.system(size: 12))
                        .foregroundStyle(secondary)
                }
                .padding(.top, Space.s4)
            }
        }
    }

    /// Whether the popover of the stamp at `slot` opens above it: in the grid's last row, when nothing is below the card.
    static func opensAbove(_ slot: CGRect, lastRowTop: CGFloat, roomBelow: Bool) -> Bool {
        !roomBelow && slot.minY >= lastRowTop - 1
    }

    private static var debugPopover: AchievementID? {
        #if DEBUG
        snapshotPopover
        #else
        nil
        #endif
    }

    private var secondary: Color {
        contrast == .increased ? AchievementPaper.label(scheme) : AchievementPaper.secondary(scheme)
    }

    private func hover(_ id: AchievementID, _ inside: Bool) {
        if inside { hovered = id } else if hovered == id { hovered = nil }
    }
}

/// Eight columns of square slots across the offered width (`AchievementsCardLayout.metrics`), 32 pt between rows.
struct AchievementGrid: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 620
        let size = AchievementsCardLayout.metrics(width: width).size
        let rows = (subviews.count + AchievementsCardLayout.columns - 1) / AchievementsCardLayout.columns
        return CGSize(width: width, height: rows == 0 ? 0 : CGFloat(rows) * size + CGFloat(rows - 1) * AchievementsCardLayout.rowGap)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (size, gap) = AchievementsCardLayout.metrics(width: bounds.width)
        for (i, subview) in subviews.enumerated() {
            let column = i % AchievementsCardLayout.columns, row = i / AchievementsCardLayout.columns
            subview.place(at: CGPoint(x: bounds.minX + CGFloat(column) * (size + gap),
                                      y: bounds.minY + CGFloat(row) * (size + AchievementsCardLayout.rowGap)),
                          proposal: ProposedViewSize(width: size, height: size))
        }
    }
}

private extension View {
    /// Centres a line of text on its capital letters in a `.center` row: the row's centre falls on the middle of the
    /// cap height, not of the line box (small uppercase sat about 1 pt low in the folded bar). No effect on a
    /// baseline-aligned row.
    func capCentered(size: CGFloat, weight: NSFont.Weight) -> some View {
        let capHeight = NSFont.systemFont(ofSize: size, weight: weight).capHeight
        return alignmentGuide(VerticalAlignment.center) { $0[.firstTextBaseline] - capHeight / 2 }
    }
}

private struct SlotBoundsKey: PreferenceKey {
    static let defaultValue: [AchievementID: Anchor<CGRect>] = [:]
    static func reduce(value: inout [AchievementID: Anchor<CGRect>], nextValue: () -> [AchievementID: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// One place: the print, the waiting tool, or the press. Still unless a press plays; ready ones are buttons.
struct AchievementSlotView: View {
    var slot: AchievementSlot
    var size: CGFloat
    var press: StampPress?
    var animating: Bool
    var onHover: (Bool) -> Void
    var onStamp: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tilt = 0.0
    @State private var pointer = CGPoint.zero
    @State private var tiltTarget = 0.0
    @State private var tiltTask: Task<Void, Never>?

    var body: some View {
        Group {
            if slot.isReady, press == nil {
                Button(action: onStamp) { face.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AchievementText.accessibilityLabel(slot.status))
            } else {
                face
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(AchievementText.accessibilityLabel(slot.status))
            }
        }
        .accessibilityValue(AchievementText.condition(slot.id, tier: max(slot.status.level, 1), locale: Formatting.uiLocale))
        .onContinuousHover { phase in
            switch phase {
            case .active(let p):
                pointer = CGPoint(x: p.x / size * 2 - 1, y: p.y / size * 2 - 1)
                step(to: 1)
                onHover(true)
            case .ended:
                step(to: 0)
                onHover(false)
            }
        }
    }

    @ViewBuilder private var face: some View {
        if let press {
            if press.reduced {
                StampCrossfade(press: press, size: size)
            } else {
                TimelineView(.animation(minimumInterval: 1 / StampMotion.fps, paused: !animating)) { context in
                    let frame = StampMotion.frame(at: context.date.timeIntervalSince(press.start))
                    StampFrameView(art: frame.stamped ? press.to : press.from, frame: frame, face: press.face, size: size)
                }
            }
        } else if let face = slot.face {
            StampFrameView(art: slot.art, frame: StampMotion.ready, face: face, size: size)
        } else {
            let angles = HoverTilt.angles(pointer: pointer, phase: reduceMotion ? 0 : tilt)
            StampArtView(art: slot.art, size: size)
                .scaleEffect(angles.scale)
                .rotation3DEffect(.degrees(angles.x), axis: (1, 0, 0), perspective: HoverTilt.perspective)
                .rotation3DEffect(.degrees(angles.y), axis: (0, 1, 0), perspective: HoverTilt.perspective)
        }
    }

    /// The tilt in two 12 fps steps, in or out; ready stamps and Reduce Motion don't tilt.
    private func step(to target: Double) {
        tiltTask?.cancel()
        guard !slot.isReady, press == nil, !reduceMotion else { return tilt = 0 }
        guard tiltTarget != target else { return }
        tiltTarget = target
        tiltTask = Task {
            tilt = 0.5
            try? await Task.sleep(for: .seconds(HoverTilt.stepDuration))
            guard !Task.isCancelled else { return }
            tilt = target
            tiltTask = nil
        }
    }
}

/// The layers of one stamp state on their shared canvas (1.2 S, centred on the slot).
struct StampArtView: View {
    var art: AchievementArt
    var size: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            ForEach(art.layers, id: \.self) { layer in
                Image(art.image(layer, dark: scheme == .dark)).resizable().interpolation(.high)
            }
            if art.isSecret {
                Circle()
                    .stroke(AchievementPaper.secondary(scheme).opacity(0.6),
                            style: StrokeStyle(lineWidth: max(1.2, size / 30), dash: [size / 16, size / 22]))
                    .padding(size * 0.12)
            }
        }
        .frame(width: size * 1.2, height: size * 1.2)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// One frame of a slot: the ground shadow on the paper, the print, the tool over it, press lines and stars.
struct StampFrameView: View {
    static let starImage = 32.0 / 22

    var art: AchievementArt
    var frame: StampMotion.Frame
    var face: StampFace
    var size: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        ZStack(alignment: .topLeading) {
            if let g = frame.ground {
                Ellipse()
                    .fill(dark ? Color.black.opacity(0.45) : Color(red: 29 / 255, green: 23 / 255, blue: 17 / 255).opacity(0.16))
                    .frame(width: 2 * g.radii.width * size, height: 2 * g.radii.height * size)
                    .offset(x: (g.center.x - g.radii.width) * size, y: (g.center.y - g.radii.height) * size)
            }
            StampArtView(art: art, size: size)
            if let tool = frame.tool {
                StampToolView(face: face, tool: tool, size: size)
            }
            if frame.pressLines, let tool = frame.tool {
                PressLines(tool: tool, size: size)
                    .stroke(dark ? AchievementPaper.label(.dark) : AchievementPaper.label(.light),
                            style: StrokeStyle(lineWidth: max(1.2, 0.025 * size), lineCap: .round))
            }
            if let star = frame.readyStar {
                // As in `Stamp.dc.html`: a parchment rim (4 units), then gold with a 1.4-unit ink line, in the
                // 100-unit stamp box; the same in Light and Dark.
                let unit = size / 100
                ZStack {
                    ReadyStarShape().stroke(AchievementPaper.background(.light), style: StrokeStyle(lineWidth: 4 * unit, lineJoin: .round))
                    ReadyStarShape().fill(Color(hex: "#D6A43C")!)
                    ReadyStarShape().stroke(AchievementPaper.label(.light), style: StrokeStyle(lineWidth: 1.4 * unit, lineJoin: .round))
                }
                .frame(width: star.size * size, height: star.size * size)
                .offset(x: (star.center.x - star.size / 2) * size, y: (star.center.y - star.size / 2) * size)
            }
            ForEach(Array(frame.stars.enumerated()), id: \.offset) { _, star in
                // The sizes are the star's own; it fills 22 of the image's 32 px.
                let image = star.size * size * Self.starImage
                Image("Achievements/star").resizable().interpolation(.high)
                    .frame(width: image, height: image)
                    .offset(x: star.center.x * size - image / 2, y: star.center.y * size - image / 2)
            }
        }
        .frame(width: size, height: size, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

/// The stamp tool, its parts on one 63 × 85.5 pt canvas; the pad's bottom centre at (31.5, 82.5).
struct StampToolView: View {
    static let canvas = CGSize(width: 63, height: 85.5)
    static let origin = CGPoint(x: 31.5, y: 82.5)
    /// The handle's bottom edge on the canvas: it squashes towards it.
    static let handleBottom = 61.5
    /// Half the block's width on the canvas, for the press lines.
    static let blockHalfWidth = 29.5

    var face: StampFace
    var tool: StampMotion.Tool
    var size: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let k = tool.width * size / Self.canvas.width
        let origin = UnitPoint(x: Self.origin.x / Self.canvas.width, y: Self.origin.y / Self.canvas.height)
        let handle = UnitPoint(x: 0.5, y: Self.handleBottom / Self.canvas.height)
        ZStack {
            ForEach(StampFace.parts, id: \.self) { part in
                let isHandle = part.hasPrefix("handle")
                Image(face.image(part, dark: scheme == .dark)).resizable().interpolation(.high)
                    // Squashed: the handle shortens towards its bottom, block and pad widen; shadows go with them.
                    .scaleEffect(x: tool.squashed && !isHandle ? 1.05 : 1, y: tool.squashed && isHandle ? 0.88 : 1,
                                 anchor: isHandle ? handle : origin)
            }
        }
        .frame(width: Self.canvas.width * k, height: Self.canvas.height * k)
        .rotationEffect(.degrees(tool.rotation), anchor: origin)
        .offset(x: size / 2 - Self.origin.x * k, y: tool.padBottom * size - Self.origin.y * k)
        .accessibilityHidden(true)
    }
}

/// The ready star of `Stamp.dc.html`: four curved points, “M0 -9 C1.6 -2 2 -1.6 9 0 …” scaled to the frame.
struct ReadyStarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY), k = min(rect.width, rect.height) / 18
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: c.x + x * k, y: c.y + y * k) }
        var path = Path()
        path.move(to: p(0, -9))
        path.addCurve(to: p(9, 0), control1: p(1.6, -2), control2: p(2, -1.6))
        path.addCurve(to: p(0, 9), control1: p(2, 1.6), control2: p(1.6, 2))
        path.addCurve(to: p(-9, 0), control1: p(-1.6, 2), control2: p(-2, 1.6))
        path.addCurve(to: p(0, -9), control1: p(-2, -1.6), control2: p(-1.6, -2))
        path.closeSubpath()
        return path
    }
}

/// Three short strokes on each side of the pressed tool.
struct PressLines: Shape {
    var tool: StampMotion.Tool
    var size: CGFloat

    func path(in rect: CGRect) -> Path {
        let k = tool.width * size / StampToolView.canvas.width
        let edge = StampToolView.blockHalfWidth * k * 1.05 + 0.05 * size
        let length = 0.2 * size
        var path = Path()
        for side in [-1.0, 1.0] {
            let x0 = size / 2 + side * edge
            for (y0, y1) in [(0.66, 0.58), (0.78, 0.78), (0.90, 0.98)] {
                path.move(to: CGPoint(x: x0, y: y0 * size))
                path.addLine(to: CGPoint(x: x0 + side * length, y: y1 * size))
            }
        }
        return path
    }
}

/// Reduce Motion: the old print, the tool and its shadow fade into the new print in 0.25 s. No press, no stars.
struct StampCrossfade: View {
    var press: StampPress
    var size: CGFloat
    @State private var done = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            StampFrameView(art: press.from, frame: StampMotion.Frame(tool: StampMotion.readyTool, ground: StampMotion.readyGround),
                           face: press.face, size: size)
                .opacity(done ? 0 : 1)
            StampArtView(art: press.to, size: size).opacity(done ? 1 : 0)
        }
        .frame(width: size, height: size, alignment: .topLeading)
        .onAppear { withAnimation(.linear(duration: StampMotion.reducedDuration)) { done = true } }
    }
}

/// The hover popover (CARD.md): name, tier, condition, date, next goal.
struct AchievementPopover: View {
    static let width: CGFloat = 214
    var text: AchievementPopoverText
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(text.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.vyLabel)
            if let tier = text.tier {
                Text(tier).textCase(.uppercase).font(.system(size: 11, weight: .semibold)).tracking(0.44)
                    .foregroundStyle(Color.vyLabelSecondary)
            }
            Text(text.condition).font(.system(size: 12)).foregroundStyle(Color.vyLabel)
            if let date = text.date { Text(date).font(.system(size: 12)).foregroundStyle(Color.vyLabelSecondary) }
            if let next = text.next { Text(next).font(.system(size: 12)).foregroundStyle(Color.vyLabelSecondary) }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(width: Self.width, alignment: .leading)
        .background(scheme == .dark ? Color(hex: "#2C2C2E")! : Color.white,
                    in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(scheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.18), radius: 12, y: 8)
    }
}
