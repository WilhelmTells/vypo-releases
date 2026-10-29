import SwiftUI

/// The Done story as numbers: where every layer is at a frame (12 fps, cut-out puppet style). Pure, so it is tested
/// and the final still is the same code as the last frame. Timings follow the onboarding design.
enum DoneStoryLayout {
    static let fps = 12.0
    static let lastFrame = 95
    /// The boy sits and text appears.
    static let textFrame = 54
    /// Frame 20: the tablet breaks.
    static let breakFrame = 20

    /// The polygons the tablet breaks along, in tablet coordinates (96 x 150 image at 95.5 pt).
    static let polygons: [[CGPoint]] = [
        [(0, 20), (30, 20), (26, 48), (0, 52)], [(30, 20), (57, 20), (54, 46), (26, 48)], [(57, 20), (86, 20), (86, 50), (54, 46)],
        [(0, 52), (26, 48), (30, 82), (0, 82)], [(26, 48), (54, 46), (52, 82), (30, 82)], [(54, 46), (86, 50), (86, 82), (52, 82)],
        [(0, 82), (40, 82), (36, 152), (0, 152)], [(40, 82), (86, 82), (86, 152), (36, 152)],
    ].map { $0.map { CGPoint(x: $0.0, y: $0.1) } }
    static let spin: [Double] = [0.2, -0.6, 0.5, -0.3, 0.8, -0.9, 0.4, -0.2]
    static let crack: [CGPoint] = [(57, 20), (55, 30), (54, 46), (40, 47), (26, 48), (28, 62), (30, 82)].map { CGPoint(x: $0.0, y: $0.1) }
    static let tabletOrigin = CGPoint(x: 96, y: 20)

    struct Piece: Equatable {
        var polygon: [CGPoint]
        var center: CGPoint
        var offset: CGSize
        var degrees: Double
    }

    struct Puff: Equatable {
        var origin: CGPoint
        var scale: Double
        var opacity: Double
    }

    struct Star: Equatable {
        var offset: CGPoint
        var scale: Double
        var degrees: Double
        var opacity: Double
    }

    struct Frame: Equatable {
        var pieces: [Piece]
        var puffs: [Puff]
        var crackPoints: [CGPoint]?
        /// nil once the stonemason has left the stage.
        var mason: (index: Int, offset: CGPoint, mirrored: Bool, tilt: Double)?
        var boyOffset: CGPoint
        var boyScaleY: Double
        var legL: Double
        var legR: Double
        var blowing: Bool
        var stars: [Star]
        var textVisible: Bool

        static func == (a: Frame, b: Frame) -> Bool {
            a.pieces == b.pieces && a.puffs == b.puffs && a.crackPoints == b.crackPoints
                && a.mason?.index == b.mason?.index && a.mason?.offset == b.mason?.offset && a.mason?.mirrored == b.mason?.mirrored
                && a.boyOffset == b.boyOffset && a.boyScaleY == b.boyScaleY && a.legL == b.legL && a.legR == b.legR
                && a.blowing == b.blowing && a.stars == b.stars && a.textVisible == b.textVisible
        }
    }

    /// `animated` false is the final still (Reduce motion, and the settled state after the story).
    static func frame(_ f: Int, animated: Bool) -> Frame {
        let fb = 20
        var pieces: [Piece] = []
        var puffs: [Puff] = []
        for (i, pts) in polygons.enumerated() {
            let cx = pts.map(\.x).reduce(0, +) / CGFloat(pts.count)
            let cy = pts.map(\.y).reduce(0, +) / CGFloat(pts.count)
            let vx = Double(cx - 43) * 0.9 + spin[i] * 10 - 6
            let vy = -40 - abs(spin[i]) * 30
            let g = 520.0
            let drop = max(4, 138 - Double(cy))
            let tLand = (-vy + (vy * vy + 2 * g * drop).squareRoot()) / g
            let landFrame = fb + Int((tLand * 12).rounded(.up))
            var tx = 0.0, ty = 0.0, rot = 0.0
            if f >= fb {
                let tt = min(Double(f - fb) / 12, tLand)
                tx = vx * tt
                ty = vy * tt + g / 2 * tt * tt
                rot = spin[i] * 260 * tt
                if i % 2 == 0, animated {
                    let k = f - landFrame
                    let sc = [0.5, 1, 0.85, 0.6], op = [1, 0.9, 0.55, 0.25]
                    if k >= 0 && k < 4 {
                        puffs.append(Puff(origin: CGPoint(x: tabletOrigin.x + cx + CGFloat(vx * tLand) - 12, y: tabletOrigin.y + 138 + 8),
                                          scale: sc[k], opacity: op[k]))
                    }
                }
            }
            pieces.append(Piece(polygon: pts, center: CGPoint(x: cx, y: cy), offset: CGSize(width: tx, height: ty), degrees: rot.rounded()))
        }

        var crackPoints: [CGPoint]?
        if animated && f >= 18 && f < fb { crackPoints = f == 18 ? Array(crack.prefix(4)) : crack }

        // The stonemason: strip frames 0 to 17 chisel, then the sad poses.
        var mason: (index: Int, offset: CGPoint, mirrored: Bool, tilt: Double)?
        if animated && f < 50 {
            var index = min(f, 17)
            if f >= 21 { index = 18 }
            if f >= 23 { index = 19 }
            if f >= 26 { index = 20 }
            if f >= 29 { index = 21 }
            if f >= 32 { index = 22 }
            var offset = tabletOrigin
            var tilt = 0.0
            if f >= 38 {
                let w = f - 38
                offset = CGPoint(x: tabletOrigin.x - 17 * CGFloat(w),
                                 y: tabletOrigin.y - 3.5 * CGFloat(abs(sin(Double.pi * Double(w % 3) / 3))))
                tilt = (w / 3) % 2 == 1 ? 2 : -2
            }
            mason = (index, offset, f >= 37, tilt)
        }

        // The boy walks in from the right, hops onto the hill, sits.
        var boy = CGPoint(x: 218.5, y: 13.8)
        var scaleY = 1.0, legL = 0.0, legR = 0.0
        let blowing = !animated || f >= 58
        if animated && f < 44 {
            boy.x = 600
        } else if animated && f < 52 {
            let u = Double(f - 44)
            boy = CGPoint(x: 540 - 36 * u, y: 43 - 3.5 * abs(sin(Double.pi * (u.truncatingRemainder(dividingBy: 3)) / 3)))
            legL = 12 * sin(Double.pi * u / 2)
            legR = -legL
        } else if animated && f == 52 {
            boy = CGPoint(x: 232, y: 22); legL = -8; legR = 8
        } else if animated && f == 53 {
            scaleY = 0.94
        }
        if animated && f >= 54 {
            let q = Double((f - 54) / 2)
            legL = 8 * sin(q * Double.pi / 4.75)
            legR = -legL
        }

        var stars: [Star] = []
        for (i, start) in [60, 61, 62].enumerated() where animated {
            let k = f - start
            guard k >= 0 && k <= 11 else { continue }
            let a = -55 * Double.pi / 180 + Double(i - 1) * 0.3
            let dist = 4 + 5 * Double(k)
            let sc = min(i == 2 ? 0.7 : 1, 0.35 + 0.22 * Double(k))
            stars.append(Star(offset: CGPoint(x: 218.5 + 54.9 + cos(a) * dist * 1.3 - 10, y: 13.8 + 77.4 + sin(a) * dist * 1.3 - 10),
                              scale: sc, degrees: Double(k * 30), opacity: k > 7 ? max(0, 1 - 0.3 * Double(k - 7)) : 1))
        }

        return Frame(pieces: pieces, puffs: puffs, crackPoints: crackPoints, mason: mason, boyOffset: boy, boyScaleY: scaleY,
                     legL: legL, legR: legR, blowing: blowing, stars: stars, textVisible: !animated || f >= textFrame)
    }
}

/// A polygon as a clip shape.
private struct PolygonShape: Shape {
    var points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: first)
        points.dropFirst().forEach { p.addLine(to: $0) }
        p.closeSubpath()
        return p
    }
}

/// The 520 x 180 woodcut stage with the story. Plays once from the first frame to the last when `play` is true.
struct DoneStage: View {
    var frameNumber: Int
    var animated: Bool

    var body: some View {
        let f = DoneStoryLayout.frame(frameNumber, animated: animated)
        ZStack(alignment: .topLeading) {
            Image("Onboarding/done-stage").resizable().interpolation(.high).frame(width: 520, height: 180)
            Image("Onboarding/woodcut-hill").resizable().interpolation(.high)
                .frame(width: 130, height: 67.7).paperShadow()
                .offset(x: 195, y: 113.5)
            // The broken tablet: eight pieces of one image, each clipped to its polygon.
            ForEach(Array(f.pieces.enumerated()), id: \.offset) { _, piece in
                Image("Onboarding/journey-tablet").resizable().interpolation(.high)
                    .frame(width: 95.5, height: 150)
                    .clipShape(PolygonShape(points: piece.polygon))
                    .rotationEffect(.degrees(piece.degrees), anchor: UnitPoint(x: piece.center.x / 95.5, y: piece.center.y / 150))
                    .offset(x: piece.offset.width, y: piece.offset.height)
                    .offset(x: DoneStoryLayout.tabletOrigin.x, y: DoneStoryLayout.tabletOrigin.y)
            }
            ForEach(Array(f.puffs.enumerated()), id: \.offset) { _, puff in
                Image("Onboarding/journey-dust2").resizable().interpolation(.high)
                    .aspectRatio(contentMode: .fit).frame(width: 24)
                    .scaleEffect(puff.scale, anchor: .bottom)
                    .opacity(puff.opacity)
                    .offset(x: puff.origin.x, y: puff.origin.y - 24 * 81 / 136)
            }
            if let crack = f.crackPoints {
                Path { p in
                    p.move(to: crack[0])
                    crack.dropFirst().forEach { p.addLine(to: $0) }
                }
                .stroke(Color(red: 0.114, green: 0.09, blue: 0.067), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                .offset(x: DoneStoryLayout.tabletOrigin.x, y: DoneStoryLayout.tabletOrigin.y)
            }
            if let mason = f.mason {
                // The strip is 23 frames of 95.5 pt; the window shows one of them.
                Image("Onboarding/journey-stonemason-strip").resizable().interpolation(.high)
                    .frame(width: 2196.5, height: 150)
                    .offset(x: -CGFloat(mason.index) * 95.5)
                    .frame(width: 95.5, height: 150, alignment: .leading)
                    .clipped()
                    .rotationEffect(.degrees(mason.tilt), anchor: UnitPoint(x: 76 / 95.5, y: 1))
                    .scaleEffect(x: mason.mirrored ? -1 : 1, anchor: UnitPoint(x: 76 / 95.5, y: 1))
                    .offset(x: mason.offset.x, y: mason.offset.y)
            }
            boy(f)
            ForEach(Array(f.stars.enumerated()), id: \.offset) { _, star in
                Image("Onboarding/inserted-star").resizable().frame(width: 20, height: 20)
                    .scaleEffect(star.scale).rotationEffect(.degrees(star.degrees))
                    .opacity(star.opacity)
                    .offset(x: star.offset.x, y: star.offset.y)
            }
        }
        .frame(width: 520, height: 180, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.vySeparator, lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The vypo boy sits on a woodcut hill under a night sky and blows his fanfare, the raven sits on his cap, the broken tablet lies on the ground")
    }

    private func boy(_ f: DoneStoryLayout.Frame) -> some View {
        let size = CGSize(width: 83, height: 134.5)
        func layer(_ name: String) -> some View {
            Image("Onboarding/\(name)").resizable().interpolation(.high).frame(width: size.width, height: size.height)
        }
        return ZStack {
            layer("journey-boy-legL").rotationEffect(.degrees(f.legL), anchor: UnitPoint(x: 36 / 83, y: 112.7 / 134.5))
            layer("journey-boy-legR").rotationEffect(.degrees(f.legR), anchor: UnitPoint(x: 47 / 83, y: 112.7 / 134.5))
            layer(f.blowing ? "journey-boy-blow-nolegs" : "journey-boy-idle-nolegs")
        }
        .frame(width: size.width, height: size.height)
        .paperShadow(opacity: 0.5)
        .scaleEffect(y: f.boyScaleY, anchor: UnitPoint(x: 0.5, y: 1))
        .offset(x: f.boyOffset.x, y: f.boyOffset.y)
    }
}

/// Plays the story once at 12 fps; with Reduce motion it is the final still.
struct DoneStoryPlayer: View {
    @Binding var textVisible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        Group {
            if reduceMotion {
                DoneStage(frameNumber: DoneStoryLayout.lastFrame, animated: false)
            } else {
                TimelineView(.periodic(from: start, by: 1 / DoneStoryLayout.fps)) { context in
                    let frame = min(DoneStoryLayout.lastFrame, Int(context.date.timeIntervalSince(start) * DoneStoryLayout.fps))
                    DoneStage(frameNumber: frame, animated: true)
                        .onChange(of: frame >= DoneStoryLayout.textFrame) { _, shown in textVisible = shown }
                }
            }
        }
        .onAppear {
            start = Date()
            textVisible = reduceMotion
        }
    }
}

/// Step 7: “No more chiseling.”
struct DoneStep: View {
    var start: () -> Void
    /// Snapshots only: show the text without waiting for the story.
    var showTextAtOnce = false
    @State private var textVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var shown: Bool { textVisible || showTextAtOnce }

    var body: some View {
        VStack(spacing: 0) {
            DoneStoryPlayer(textVisible: $textVisible)
                .padding(.top, 36)
            VStack(spacing: 0) {
                Text("No more chiseling.")
                    .font(OBFont.heroTitle).tracking(-0.3).foregroundStyle(Color.vyLabel)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 6)
                Text("You’re set.\nYour voice and your text stay on this Mac and never go to a cloud.")
                    .font(OBFont.bodyLarge).foregroundStyle(Color.vyLabel)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 16)
                HStack(alignment: .top, spacing: 14) {
                    DoneCard(caption: "vypo in the menu bar") { MenuBarIllustration() }
                    DoneCard(caption: "The pill appears while you dictate. Drag it wherever you like.") { PillIllustration() }
                }
                .frame(width: 480)
                Text("Add names and terms vypo should spell your way in Settings → Words.")
                    .font(OBFont.secondary).foregroundStyle(Color.vyLabelSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 14).padding(.bottom, 14)
                Button("Start dictating", action: start)
                    .buttonStyle(.ob(.hero))
                    .keyboardShortcut(.defaultAction)
            }
            .frame(width: 600)
            .padding(.top, 16)
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 6)
            .allowsHitTesting(shown)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: shown)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct DoneCard<Illustration: View>: View {
    var caption: LocalizedStringKey
    @ViewBuilder var illustration: Illustration

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            illustration
                .frame(maxWidth: .infinity).frame(height: 56)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.vyBgGroup))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.vySeparator, lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(caption).font(OBFont.secondary).foregroundStyle(Color.vyLabelSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// A strip of the menu bar with three neutral glyphs and the vypo mark in a 2 pt accent ring.
private struct MenuBarIllustration: View {
    var body: some View {
        HStack(spacing: 9) {
            Spacer()
            RoundedRectangle(cornerRadius: 2).fill(Color.vyLabelTertiary).frame(width: 9, height: 7)
            RoundedRectangle(cornerRadius: 2).fill(Color.vyLabelTertiary).frame(width: 28, height: 6)
            Image("Onboarding/menubar-glyph").resizable().renderingMode(.template).foregroundStyle(Color.vyLabel)
                .frame(width: 13, height: 13)
                .frame(width: 22, height: 16)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.vyBgGroup))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.vyAccent, lineWidth: 2))
        }
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.vyFillTrack))
        .padding(.horizontal, 12)
        .overlay(alignment: .topTrailing) {
            // The pointer under the mark.
            Triangle().fill(Color.vyAccent).frame(width: 10, height: 6).padding(.trailing, 26).padding(.top, 22)
        }
        .accessibilityHidden(true)
    }
}

/// A dashed outline where the pill was, a dashed arrow, and the Glass pill at its new place.
private struct PillIllustration: View {
    var body: some View {
        HStack(spacing: 8) {
            Capsule().strokeBorder(Color.vyLabelTertiary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])).frame(width: 48, height: 20)
            Image(systemName: "arrow.right").font(.system(size: 14)).foregroundStyle(Color.vyLabelSecondary)
            GlassStagePill(size: CGSize(width: 48, height: 20), content: .bars(flat: false), level: { 0.4 },
                           barWidth: 2, gap: 2, minHeight: 3, maxHeight: 14)
        }
        .accessibilityHidden(true)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
