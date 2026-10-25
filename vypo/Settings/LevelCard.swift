import SwiftUI

/// The level card at the top of the Stats pane: rank, a progress bar and the words to the next rank.
/// A rank reached since the pane was last seen plays the fanfare once, here and nowhere else.
struct LevelCard: View {
    let level: LevelStore
    /// Debug → Mascot: shown instead of the real level while active; nothing of it is saved.
    let preview: LevelPreview

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var windowVisible = false
    @State private var levelUp: LevelUpRun?
    @State private var catchUp: CatchUp?

    /// On opening the pane, the words since it was last seen: he waits a moment where he was, then walks.
    private struct CatchUp: Equatable {
        static let pause = 0.3
        var from: Int
        var start = Date()
        /// The stage has the new words and walks; the numbers follow when he's there.
        var walking = false
    }

    /// The pane is on screen in a visible window (the Settings window is kept when closed).
    private var visible: Bool { appeared && windowVisible }

    /// The rank and words to show when nothing is playing: the preview's, or the real ones.
    private var current: (rank: Rank, words: Int) {
        guard preview.isActive else { return (level.rank, level.xpWords) }
        let rank = preview.rank ?? level.rank
        guard let next = rank.next else { return (rank, preview.rank == nil ? level.xpWords : rank.threshold) }
        let progress = preview.progress ?? (preview.rank == nil ? rank.progress(words: level.xpWords) : 0)
        return (rank, rank.threshold + Int(Double(next.threshold - rank.threshold) * progress))
    }

    /// The old rank while the fanfare plays, and while a new one waits to be seen.
    private var shownRank: Rank {
        if let levelUp, !levelUp.reduced { return levelUp.from }
        let waiting = levelUp == nil && !preview.isActive && level.rank.level > level.lastSeenLevel
        return waiting ? level.lastSeenRank : current.rank
    }

    var body: some View {
        let rank = shownRank
        // The old rank shows the words it was last seen with.
        let words = rank == current.rank ? current.words : levelUp?.words ?? level.lastSeenWords
        LevelCardLayout(rank: rank, words: catchUp?.from ?? words) {
            LevelStage(rank: rank, words: catchUp.map { $0.walking ? words : $0.from } ?? words, visible: visible, levelUp: levelUp)
        }
        // A new rank replaces the old card: crossfaded with Reduce Motion, at once after the fanfare.
        .id(rank)
        .transition(.opacity)
        // The art is 760 pt wide: wider windows centre the card.
        .frame(maxWidth: LevelSceneGeometry.artWidth)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityText(rank: current.rank, words: current.words))
        .background(WindowVisibilityReader { windowVisible = $0 })
        .onAppear { appeared = true }
        .onDisappear {
            appeared = false
            levelUp = nil
            catchUp = nil
        }
        .onChange(of: visible) { check(opening: true) }
        .onChange(of: level.xpWords) { check() }
        .onChange(of: preview.playRequested) { check() }
        .onChange(of: preview.isActive) { check() }
        .task(id: catchUp?.start) {
            guard catchUp != nil else { return }
            try? await Task.sleep(for: .seconds(CatchUp.pause))
            guard !Task.isCancelled else { return }
            catchUp?.walking = true
            try? await Task.sleep(for: .seconds(MascotMotion.walkDuration))
            guard !Task.isCancelled else { return }
            catchUp = nil
            check()
        }
        .task(id: levelUp?.start) {
            guard let run = levelUp else { return }
            try? await Task.sleep(for: .seconds(run.reduced ? LevelUpMotion.reducedDuration : LevelUpMotion.duration))
            guard !Task.isCancelled, levelUp?.start == run.start else { return }
            levelUp = nil
            // A preview ends on the next rank, at its start.
            if run.preview, !run.reduced {
                preview.rank = run.from.next
                preview.progress = nil
            }
            check()
        }
    }

    /// While the pane is seen: a new rank starts the fanfare (counted as seen right away, even if the
    /// pane is left during it); otherwise the words are remembered as seen, and on opening he walks there.
    /// A requested preview plays instead, from what the card shows (from the one below on the highest
    /// rank) and touches nothing saved.
    private func check(opening: Bool = false) {
        guard visible, levelUp == nil, catchUp == nil else { return }
        if preview.playRequested {
            preview.playRequested = false
            let shown = current
            let from = shown.rank.next == nil ? (Rank.highest.previous ?? shown.rank) : shown.rank
            let run = LevelUpRun(from: from, words: from == shown.rank ? shown.words : from.threshold, start: Date(),
                                 reduced: reduceMotion, preview: true)
            guard reduceMotion else { return levelUp = run }
            return withAnimation(.easeInOut(duration: 0.4)) {
                levelUp = run
                preview.rank = from.next
                preview.progress = nil
            }
        }
        guard !preview.isActive else { return }
        guard level.rank.level > level.lastSeenLevel else {
            // Within the rank: on opening, show the way since the last visit (not for a hair's breadth).
            let rank = level.rank
            if opening, !reduceMotion, rank == level.lastSeenRank,
               rank.progress(words: level.xpWords) - rank.progress(words: level.lastSeenWords) >= 0.01 {
                catchUp = CatchUp(from: level.lastSeenWords)
            }
            return level.markSeen()
        }
        let from = level.lastSeenRank
        let run = LevelUpRun(from: from, words: level.lastSeenWords, start: Date(), reduced: reduceMotion)
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.4)) {
                levelUp = run
                level.markSeen()
            }
        } else {
            levelUp = run
            level.markSeen()
        }
    }

    /// Formatted like the other figures on the pane.
    static func number(_ n: Int) -> String { n.formatted() }

    /// “Level 3 of 10, Page. 13,200 words to the next level.”
    static func accessibilityText(rank: Rank, words: Int) -> String {
        guard let next = rank.next else {
            return String(localized: "Level \(rank.level) of \(Rank.highest.level), \(rank.name). \(number(words)) words.")
        }
        return String(localized: "Level \(rank.level) of \(Rank.highest.level), \(rank.name). \(number(next.threshold - words)) words to the next level.")
    }
}

/// A level-up being played: from where he sat in the old rank.
struct LevelUpRun: Equatable {
    var from: Rank
    var words: Int
    var start: Date
    var reduced: Bool
    /// Debug → Mascot → Play level-up.
    var preview = false
}

/// The card's face: the scene, and over it the rank, the next rank and the numbers. Shared by the card
/// and the snapshots, so both lay out the same.
struct LevelCardLayout<Scene: View>: View {
    var rank: Rank
    var words: Int
    @ViewBuilder var scene: Scene

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Level \(rank.level) of \(Rank.highest.level)")
                        .textCase(.uppercase)
                        .font(.vyTier)
                        .tracking(0.6)
                        .foregroundStyle(LevelSceneText.secondary)
                    Text(rank.name)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(LevelSceneText.title)
                }
                Spacer(minLength: Space.s2)
                // The next rank's name stays a surprise: only the top rank says so.
                if rank.next == nil {
                    Text("Highest rank")
                        .font(.callout)
                        .foregroundStyle(LevelSceneText.secondary)
                }
            }
            Spacer(minLength: 0)
            LevelNumbers(rank: rank, words: words).padding(.horizontal, LevelStage.inset)
        }
        // The card is a picture, the same in Light and Dark; a hard print shadow keeps the text off it.
        .shadow(color: LevelSceneText.shadow.opacity(contrast == .increased ? 0.95 : 0.55), radius: 0, y: 1)
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: LevelSceneGeometry.height)
        .background { scene }
        .clipShape(RoundedRectangle(cornerRadius: LevelSceneGeometry.cornerRadius, style: .continuous))
        .environment(\.colorScheme, .dark)
    }
}

/// Text colours on the scene (LAYERS.md).
enum LevelSceneText {
    static let title = Color(red: 0xf3 / 255, green: 0xe9 / 255, blue: 0xcf / 255)
    static let secondary = Color(red: 0xe9 / 255, green: 0xdc / 255, blue: 0xbc / 255)
    static let shadow = Color(red: 15 / 255, green: 10 / 255, blue: 5 / 255)
}

/// Where everything sits on the level card, in points from its top left. Taken
/// from the scene's design layout, except that the walk ends 16 pt earlier and the castle
/// is drawn at 0.85, so it stands wholly inside the card at every width.
struct LevelSceneGeometry: Equatable {
    static let height: CGFloat = 285
    static let cornerRadius: CGFloat = 12
    /// The sky, hills, ground and paper are this wide and cropped from the middle.
    static let artWidth: CGFloat = 760
    static let barStart: CGFloat = 60
    /// LAYERS.md: 60.
    static let barEndInset: CGFloat = 76
    static let barTop: CGFloat = 208
    static let barHeight: CGFloat = 12
    /// The bar images overhang the bar by 3 pt on every side (paper edge, ink).
    static let overhang: CGFloat = 3
    static let castleImage = CGSize(width: 69.3, height: 81.3)
    /// The gate's threshold in the castle image; it sits on the bar's top edge.
    static let castleAnchor = CGPoint(x: 24.2, y: 66.7)
    static let castleScale: CGFloat = 0.85
    /// The gate lies this far right of the walk's end, so he arrives next to it.
    static let gate: CGFloat = 28
    static let castleMargin: CGFloat = 8

    var width: CGFloat

    var x0: CGFloat { Self.barStart }
    /// The end of the walk (100 %).
    var x1: CGFloat { width - Self.barEndInset }
    var gateX: CGFloat { x1 + Self.gate }
    /// Where the 760 pt art starts, so the card shows its middle.
    var artX: CGFloat { -(Self.artWidth - width) / 2 }

    func boyX(_ progress: Double) -> CGFloat { x0 + (x1 - x0) * progress }

    /// The road from the start into the castle gate.
    var emptyBar: CGRect {
        CGRect(x: x0 - Self.overhang, y: Self.barTop - Self.overhang,
               width: gateX - x0 + 2 * Self.overhang, height: Self.barHeight + 2 * Self.overhang)
    }

    /// The filled part, up to the boy; never shorter than its two ends.
    func fillBar(_ progress: Double) -> CGRect {
        CGRect(x: x0 - Self.overhang, y: Self.barTop - Self.overhang,
               width: max(14, boyX(progress) - x0) + 2 * Self.overhang, height: Self.barHeight + 2 * Self.overhang)
    }

    var castle: CGRect {
        let s = Self.castleScale
        return CGRect(x: gateX - Self.castleAnchor.x * s, y: Self.barTop - Self.castleAnchor.y * s,
                      width: Self.castleImage.width * s, height: Self.castleImage.height * s)
    }
}

/// The scene behind the card's text, moving: the boy walks, blinks and plays the level-up here.
struct LevelStage: View {
    /// The numbers row lines up with the bar's start.
    static let inset: CGFloat = 44

    var rank: Rank
    var words: Int
    var visible: Bool
    var levelUp: LevelUpRun?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var walk: Walk?

    private struct Walk {
        var from: Double
        var to: Double
        var start: Date
    }

    /// Moves only while the pane is on screen: no timer otherwise. With Reduce Motion only the
    /// level-up's stars fade.
    private var animating: Bool { visible && (!reduceMotion || levelUp != nil) }

    var body: some View {
        let progress = rank.progress(words: words)
        TimelineView(.animation(minimumInterval: 1 / MascotMotion.fps, paused: !animating)) { context in
            LevelScene(frame: frame(progress: progress, at: animating ? context.date : nil))
        }
        .onChange(of: words) { old, new in
            let from = rank.progress(words: old)
            let to = rank.progress(words: new)
            guard animating, !reduceMotion, levelUp == nil, Rank(words: old) == rank, to > from else { return walk = nil }
            walk = Walk(from: walk.map { shown(at: Date(), walk: $0) } ?? from, to: to, start: Date())
        }
    }

    /// What the stage shows at `date`; nil is still.
    private func frame(progress: Double, at date: Date?) -> LevelUpFrame {
        guard let date else { return LevelUpFrame(progress: progress, pose: .rest) }
        if let levelUp {
            let t = date.timeIntervalSince(levelUp.start)
            if levelUp.reduced {
                return LevelUpFrame(progress: progress, pose: .rest, stars: LevelUpMotion.reducedStars(at: t))
            }
            if t < LevelUpMotion.duration { return LevelUpMotion.frame(at: t, from: levelUp.from.progress(words: levelUp.words)) }
        }
        let pose = reduceMotion ? .rest : MascotMotion.idle(at: date.timeIntervalSinceReferenceDate)
        guard let walk, walk.to == progress else { return LevelUpFrame(progress: progress, pose: pose) }
        return LevelUpFrame(progress: shown(at: date, walk: walk), pose: pose)
    }

    private func shown(at date: Date, walk: Walk) -> Double {
        let t = date.timeIntervalSince(walk.start)
        return t >= MascotMotion.walkDuration ? walk.to : MascotMotion.walk(from: walk.from, to: walk.to, after: t)
    }
}

/// One frame of the scene, back to front as in LAYERS.md: sky, its stars, the far hill, the castle,
/// the grass, the boy's locks, the road and its filled part, the rest of the boy (his lower legs hang in
/// front of the road), whatever flies, and the paper over everything.
struct LevelScene: View {
    var frame: LevelUpFrame

    var body: some View {
        GeometryReader { geo in scene(LevelSceneGeometry(width: geo.size.width)) }
    }

    private func scene(_ g: LevelSceneGeometry) -> some View {
        let seat = MascotCanvas.point(MascotCanvas.seat)
        let figure = CGPoint(x: g.boyX(frame.progress) - seat.x, y: LevelSceneGeometry.barTop - seat.y)
        // The stars start at the bell in his hands, or on his lap with Reduce Motion.
        let bell = MascotCanvas.point(frame.pose.blowing ? MascotCanvas.bell : MascotCanvas.lapBell)
        let featherStart = MascotCanvas.point(MascotCanvas.featherSpawn)
        let empty = g.emptyBar, fill = g.fillBar(frame.progress), castle = g.castle
        return ZStack(alignment: .topLeading) {
            art("sky", g)
            art("sky-stars", g)
            art("ground-far", g)
            Image("LevelScene/castle").resizable().interpolation(.high)
                .frame(width: castle.width, height: castle.height)
                .offset(x: castle.minX, y: castle.minY)
            art("ground", g)
            MascotFigure(pose: frame.pose, part: .behindBar)
                .printShadow()
                .offset(x: figure.x, y: figure.y)
            Image("LevelScene/bar-empty")
                .resizable(capInsets: EdgeInsets(top: 0, leading: 11, bottom: 0, trailing: 35))
                .frame(width: empty.width, height: empty.height)
                .shadow(color: PrintShadow.color.opacity(0.40), radius: 0, x: 0.8, y: 1.2)
                .offset(x: empty.minX, y: empty.minY)
            Image("LevelScene/bar-fill")
                .resizable(capInsets: EdgeInsets(top: 0, leading: 11, bottom: 0, trailing: 9))
                .frame(width: fill.width, height: fill.height)
                .opacity(frame.progress > 0 ? 1 : 0)
                .offset(x: fill.minX, y: fill.minY)
            MascotFigure(pose: frame.pose, part: .inFrontOfBar)
                .printShadow()
                .offset(x: figure.x, y: figure.y)
            ForEach(Array(frame.feathers.enumerated()), id: \.offset) { _, feather in
                let width = feather.size * MascotCanvas.featherSize.width / MascotCanvas.featherSize.height
                Image("Mascot/raven-feather").resizable().interpolation(.high)
                    .frame(width: width, height: feather.size)
                    .rotationEffect(.degrees(feather.rotation))
                    .printShadow()
                    .opacity(feather.opacity)
                    .offset(x: figure.x + featherStart.x + feather.offset.width - width / 2,
                            y: figure.y + featherStart.y + feather.offset.height - feather.size / 2)
            }
            ForEach(Array(frame.stars.enumerated()), id: \.offset) { _, star in
                Image("LevelScene/star-bright").resizable().interpolation(.high)
                    .frame(width: star.size, height: star.size)
                    .rotationEffect(.degrees(star.rotation))
                    .paperRim()
                    .printShadow()
                    .opacity(star.opacity)
                    .offset(x: figure.x + bell.x + star.offset.width - star.size / 2,
                            y: figure.y + bell.y + star.offset.height - star.size / 2)
            }
            art("paper", g).opacity(0.38)
        }
        .frame(width: g.width, height: LevelSceneGeometry.height, alignment: .topLeading)
        .clipped()
        .accessibilityHidden(true)
    }

    private func art(_ name: String, _ g: LevelSceneGeometry) -> some View {
        Image("LevelScene/\(name)").resizable().interpolation(.high)
            .frame(width: LevelSceneGeometry.artWidth, height: LevelSceneGeometry.height)
            .offset(x: g.artX)
    }
}

/// The words so far and to go, on the grass under the road.
struct LevelNumbers: View {
    var rank: Rank
    var words: Int

    var body: some View {
        HStack {
            if let next = rank.next {
                Text("\(LevelCard.number(words)) / \(LevelCard.number(next.threshold)) words")
                Spacer(minLength: Space.s2)
                Text("\(LevelCard.number(next.threshold - words)) to go")
            } else {
                Text("\(LevelCard.number(words)) words")
                Spacer(minLength: Space.s2)
                Text("You made it.")
            }
        }
        .font(.callout)
        .monospacedDigit()
        .foregroundStyle(LevelSceneText.secondary)
    }
}
