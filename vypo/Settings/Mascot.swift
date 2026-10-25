import AppKit
import SwiftUI

/// The canvas all mascot layers share (`Mascot/…` in the asset catalog): 90 × 146 units from the top
/// left, shown at 83.6 × 135.7 pt (0.2323 pt per layer pixel; boy and
/// raven about 115 pt). The artwork's source PNGs are this canvas at 4× (360 × 584 px); every point below is
/// measured on those PNGs, in pixels ÷ 4.
enum MascotCanvas {
    static let size = CGSize(width: 90, height: 146)
    static let top: CGFloat = 0
    static let scale: CGFloat = 0.2323 * 4
    static var frame: CGSize { CGSize(width: size.width * scale, height: size.height * scale) }

    /// Where he sits: `boyCenterX` is placed on the bar's progress, `seatLineY` on the bar's top edge.
    static let seat = CGPoint(x: 180 / 4, y: 468.6 / 4)
    /// The middle of the fanfare's bell at his mouth (`funnel.center`), where the stars start, and the
    /// direction they fly in (`funnel.directionDeg`, degrees above the horizontal).
    static let bell = CGPoint(x: 238.6 / 4, y: 336.4 / 4)
    static let bellDirection = 55.1
    /// The bell while the fanfare lies on his lap: not in the JSON, measured in `boy-armsIdle.png`
    /// (middle of the opening).
    static let lapBell = CGPoint(x: 208 / 4, y: 381 / 4)
    /// Where the falling feathers start (`singles.raven-feather.spawn`).
    static let featherSpawn = CGPoint(x: 215.8 / 4, y: 110.9 / 4)

    static let legL = CGPoint(x: 156.2 / 4, y: 488.9 / 4)
    static let legR = CGPoint(x: 203.8 / 4, y: 488.9 / 4)
    static let eyes = CGPoint(x: 180 / 4, y: 257.6 / 4)
    static let cap = CGPoint(x: 125.1 / 4, y: 223 / 4)
    static let ravenHead = CGPoint(x: 163.3 / 4, y: 103.7 / 4)
    static let ravenBody = CGPoint(x: 203.8 / 4, y: 133.6 / 4)
    static let ravenWing = CGPoint(x: 191.9 / 4, y: 96.6 / 4)

    /// The star and the feather are separate images at the same scale (4 px per unit), in points.
    static var starSize: CGFloat { 65 / 4 * scale }
    static var featherSize: CGSize { CGSize(width: 59 / 4 * scale, height: 70 / 4 * scale) }

    /// A canvas point as an anchor in the figure's frame.
    static func anchor(_ p: CGPoint) -> UnitPoint {
        UnitPoint(x: p.x / size.width, y: (p.y - top) / size.height)
    }

    /// A canvas point in points from the figure's top left.
    static func point(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * scale, y: (p.y - top) * scale)
    }
}

/// Everything about the boy and the raven that moves.
struct MascotPose: Equatable {
    /// Degrees from each leg as drawn (the images have their ±8° already), around the knee.
    var legL: Double = 0
    var legR: Double = 0
    var eyesClosed = false
    var mouthOpen = false
    /// Degrees from the cap as drawn (the image already has its −6° tilt); the raven turns with it.
    var cap: Double = 0
    var ravenHead: Double = 0
    var ravenPuffed = false
    /// Degrees, around the wing root, while it shows.
    var wingAngle: Double = 0
    /// The fanfare at his mouth instead of on his lap.
    var blowing = false
    /// Points up.
    var hop: CGFloat = 0
    /// The raven off the cap, in points (negative y is up).
    var ravenLift: CGSize = .zero
    var wingUp = false
    var ruffled = false

    static let rest = MascotPose()
}

/// The resting motion, in steps like paper cut-outs: no springs, no easing. Timing from the motion test
/// in `mascot-app-pivots.json` (`timeline`), 12 fps, a 9 s loop.
enum MascotMotion {
    static let fps = 12.0
    static let loop = 9.0
    /// Legs swing ±12° on a sine of 1.6 s, against each other.
    static let legPeriod = 1.6
    static let legSwing = 12.0
    /// Each blink lasts two frames.
    static let blinks = [1.2, 3.7, 7.6]
    /// Calling: mouth open, the cap wobbling ±5°.
    static let call = 2.0..<2.9
    static let capWobble = 5.0
    static let headTilt = 3.0..<3.9
    static let headTiltAngle = 16.0

    /// `t` on the 12 fps grid.
    static func frameTime(_ t: Double) -> Double { (t * fps).rounded(.down) / fps }

    /// The resting pose at `t` seconds.
    static func idle(at time: Double) -> MascotPose {
        let t = frameTime(time)
        var pose = MascotPose()
        let leg = legSwing * sin(2 * .pi * t / legPeriod)
        pose.legL = leg
        pose.legR = -leg
        let l = t - (t / loop).rounded(.down) * loop
        pose.eyesClosed = blinks.contains { l >= $0 && l < $0 + 2 / fps }
        if call.contains(l) {
            pose.mouthOpen = true
            // Two wobbles over the call, ending level.
            pose.cap = -capWobble * sin(2 * .pi * (l - call.lowerBound) / ((call.upperBound - call.lowerBound) / 2))
        }
        if headTilt.contains(l) { pose.ravenHead = -headTiltAngle }
        return pose
    }

    /// Progress while walking from `from` to `to`: 8 steps over 1.2 s.
    static func walk(from: Double, to: Double, after t: Double) -> Double {
        let step = min(8, max(0, Int(t / 0.15) + 1))
        return from + (to - from) * Double(step) / 8
    }
    static let walkDuration = 1.2
}

/// A star or a feather flying during the level-up, placed from its start point.
struct MascotSprite: Equatable {
    /// Points from the start point.
    var offset: CGSize
    var size: CGFloat
    var rotation: Double = 0
    var opacity: Double = 1
}

/// One moment of the level-up.
struct LevelUpFrame: Equatable {
    /// The bar's progress in the old rank.
    var progress: Double
    var pose: MascotPose
    /// From the fanfare's bell.
    var stars: [MascotSprite] = []
    /// From the feather's spawn point on the raven.
    var feathers: [MascotSprite] = []
}

/// The level-up, played once on the Stats pane: he slides to the bar's end, then the fanfare from the
/// motion test (`timeline.levelUp`, times from its start): he hops, three stars fly out of the bell, the
/// raven flutters up, a feather falls, and it lands ruffled. Stepped at 12 fps like the rest.
enum LevelUpMotion {
    static let slide = 1.2
    /// Until the raven is no longer ruffled (7.4 − 4.5 s); he blows until 2.4 s (6.9 − 4.5).
    static let fanfare = 2.9
    static let blowing = 2.4
    static var duration: Double { slide + fanfare }
    /// With Reduce Motion: the stars stand at the bell and fade, nothing else moves.
    static let reducedDuration = 1.2

    /// One hop of 14.3 px.
    static let hop = (start: 0.05, duration: 0.42, height: 14.3 / 4 * MascotCanvas.scale)
    static let stars = (start: 0.3, stagger: 0.12, life: 0.9)
    /// Flutters 35.8 px up and lands; puffed up (1.1) right after landing, ruffled until the end.
    static let raven = (start: 0.25, duration: 0.75, lift: 35.8 / 4 * MascotCanvas.scale)
    static let feather = (start: 0.35, life: 1.8)

    /// 1.75, 1.45 and 1.2 times the star image (26, 22 and 18 pt), LAYERS.md.
    private static let starSizes: [CGFloat] = [1.75, 1.45, 1.2].map { MascotCanvas.starSize * $0 }
    /// Degrees above the horizontal each star flies at: the bell's direction +22°, −3°, −25°.
    private static let starAngles: [Double] = [21.8, -3.4, -25.2].map { MascotCanvas.bellDirection + $0 }
    /// Points from the bell where the level-up still shows them, at full size and still opaque
    /// (60 % of their flight); they fly on to 1 / 0.6 of that.
    private static let starStill: [CGFloat] = [17.2, 28.8, 18.3]
    private static let stillAt = 0.6

    static func frame(at time: Double, from start: Double) -> LevelUpFrame {
        var pose = MascotMotion.idle(at: time)
        pose.mouthOpen = false
        pose.cap = 0
        pose.ravenHead = 0
        guard time >= slide else {
            return LevelUpFrame(progress: time < 0 ? start : MascotMotion.walk(from: start, to: 1, after: time), pose: pose)
        }
        let f = MascotMotion.frameTime(min(time - slide, fanfare))
        pose.blowing = f < blowing
        if f >= hop.start, f < hop.start + hop.duration {
            pose.hop = hop.height * sin(.pi * (f - hop.start) / hop.duration)
        }
        ravenPose(at: f, into: &pose)
        let flying = (0..<3).compactMap { star($0, at: f - stars.start - stars.stagger * Double($0)) }
        let feathers = [falling(at: f - feather.start)].compactMap { $0 }
        return LevelUpFrame(progress: 1, pose: pose, stars: flying, feathers: feathers)
    }

    /// With Reduce Motion: only the stars, standing at the bell on his lap and fading in three steps.
    static func reducedStars(at t: Double) -> [MascotSprite] {
        guard t >= 0, t < reducedDuration else { return [] }
        let opacity = 1 - Double(Int(t / (reducedDuration / 3))) / 3
        return (0..<3).map { i in
            let angle = starAngles[i] * .pi / 180
            return MascotSprite(offset: CGSize(width: cos(angle) * starStill[i], height: -sin(angle) * starStill[i]),
                                size: starSizes[i], opacity: opacity)
        }
    }

    /// Out of the bell along its direction, growing from 0.35 to full size by the still's moment, turning,
    /// fading after it.
    private static func star(_ i: Int, at t: Double) -> MascotSprite? {
        guard t >= 0, t < stars.life else { return nil }
        let k = t / stars.life
        let angle = starAngles[i] * .pi / 180
        let distance = starStill[i] / stillAt * k
        return MascotSprite(offset: CGSize(width: cos(angle) * distance, height: -sin(angle) * distance),
                            size: starSizes[i] * min(1, 0.35 + 0.65 * k / stillAt), rotation: 120 * k,
                            opacity: k < stillAt ? 1 : (1 - k) / (1 - stillAt))
    }

    private static func ravenPose(at f: Double, into pose: inout MascotPose) {
        pose.ravenLift = ravenLift(at: f)
        let landed = raven.start + raven.duration
        if f >= raven.start, f < landed {
            pose.wingUp = true
            // The wing beats between −28° and +12°, frame by frame.
            pose.wingAngle = Int((f * MascotMotion.fps).rounded()) % 2 == 0 ? -28 : 12
        } else if f >= landed {
            pose.ruffled = true
            pose.ravenPuffed = f < landed + 4 / MascotMotion.fps
        }
    }

    static func ravenLift(at f: Double) -> CGSize {
        guard f >= raven.start, f < raven.start + raven.duration else { return .zero }
        return CGSize(width: 0, height: -raven.lift * sin(.pi * (f - raven.start) / raven.duration))
    }

    /// Drifts down and to the right, swinging ±35°, fading at the end.
    private static func falling(at t: Double) -> MascotSprite? {
        guard t >= 0, t < feather.life else { return nil }
        let k = t / feather.life
        return MascotSprite(offset: CGSize(width: 14 * k, height: 42 * k), size: MascotCanvas.featherSize.height,
                            rotation: 35 * sin(2 * .pi * k * 2), opacity: k < 0.7 ? 1 : (1 - k) / 0.3)
    }
}

/// The boy with the raven on his cap, built from layers so the print kit's images can replace the
/// placeholders. Hidden from VoiceOver: the card describes the level.
struct MascotFigure: View {
    var pose: MascotPose
    /// On the level card the road runs between his locks and the rest of him.
    var part: Part = .all

    enum Part {
        case all
        case behindBar
        case inFrontOfBar
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if part != .inFrontOfBar { layer("boy-locks") }
            if part != .behindBar { front }
        }
        .frame(width: MascotCanvas.frame.width, height: MascotCanvas.frame.height)
        .offset(y: -pose.hop)
        .accessibilityHidden(true)
    }

    private var front: some View {
        ZStack(alignment: .topLeading) {
            layer("boy-legL").rotationEffect(.degrees(pose.legL), anchor: MascotCanvas.anchor(MascotCanvas.legL))
            layer("boy-legR").rotationEffect(.degrees(pose.legR), anchor: MascotCanvas.anchor(MascotCanvas.legR))
            layer("boy-shorts")
            layer("boy-body")
            if !pose.blowing { layer("boy-armsIdle") }
            layer("boy-head")
            layer("boy-eyes").scaleEffect(x: 1, y: pose.eyesClosed ? 0.12 : 1, anchor: MascotCanvas.anchor(MascotCanvas.eyes))
            layer(pose.mouthOpen && !pose.blowing ? "boy-mouthOpen" : "boy-mouthShut")
            if pose.blowing {
                layer("boy-cheeks")
                layer("boy-armsBlowing")
            }
            layer("boy-cap").rotationEffect(.degrees(pose.cap), anchor: MascotCanvas.anchor(MascotCanvas.cap))
            raven
        }
    }

    /// The raven sits on the cap and turns with it, around the cap's pivot.
    private var raven: some View {
        ZStack(alignment: .topLeading) {
            layer("raven-feet")
            layer("raven-body").scaleEffect(pose.ravenPuffed ? 1.1 : 1,
                                            anchor: MascotCanvas.anchor(MascotCanvas.ravenBody))
            if pose.wingUp {
                layer("raven-wing").rotationEffect(.degrees(pose.wingAngle), anchor: MascotCanvas.anchor(MascotCanvas.ravenWing))
            }
            if pose.ruffled { layer("raven-ruffled") }
            layer("raven-head").rotationEffect(.degrees(pose.ravenHead), anchor: MascotCanvas.anchor(MascotCanvas.ravenHead))
        }
        .rotationEffect(.degrees(pose.cap), anchor: MascotCanvas.anchor(MascotCanvas.cap))
        .offset(pose.ravenLift)
    }

    private func layer(_ name: String) -> some View {
        Image("Mascot/\(name)")
            .resizable()
            .interpolation(.high)
            .frame(width: MascotCanvas.frame.width, height: MascotCanvas.frame.height)
    }
}

/// The hard shadow of the level card's print (LAYERS.md).
enum PrintShadow {
    static let color = Color(red: 28 / 255, green: 16 / 255, blue: 6 / 255)
}

extension View {
    /// A hard, offset shadow, as if printed: no blur.
    func printShadow() -> some View {
        compositingGroup().shadow(color: PrintShadow.color.opacity(0.45), radius: 0, x: 1.3, y: 1.6)
    }

    /// A paper edge of 1.4 pt around the shape, like the cut-outs in the scene.
    func paperRim() -> some View {
        let edge = LevelSceneText.title
        return compositingGroup()
            .shadow(color: edge, radius: 0, x: 1.4, y: 0)
            .shadow(color: edge, radius: 0, x: -1.4, y: 0)
            .shadow(color: edge, radius: 0, x: 0, y: 1.4)
            .shadow(color: edge, radius: 0, x: 0, y: -1.4)
    }

    /// A white edge of about 2 pt around the whole shape and a hard, slightly offset shadow, like a
    /// sticker. Drawn live, so the edge stays closed while parts move.
    func sticker() -> some View {
        compositingGroup()
            .shadow(color: .white, radius: 0, x: 2, y: 0)
            .shadow(color: .white, radius: 0, x: -2, y: 0)
            .shadow(color: .white, radius: 0, x: 0, y: 2)
            .shadow(color: .white, radius: 0, x: 0, y: -2)
            .shadow(color: .black.opacity(0.28), radius: 0, x: 1.5, y: 3)
    }
}

/// Reports whether the window holding this view is on screen and not covered, so animations can
/// stop while the Settings window is closed or hidden (it is kept, not released, when closed).
struct WindowVisibilityReader: NSViewRepresentable {
    var onChange: (Bool) -> Void

    func makeNSView(context: Context) -> ReaderView { ReaderView(onChange: onChange) }
    func updateNSView(_ view: ReaderView, context: Context) { view.onChange = onChange }

    final class ReaderView: NSView {
        var onChange: (Bool) -> Void
        private var observers: [NSObjectProtocol] = []

        init(onChange: @escaping (Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return report(false) }
            let names = [NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification,
                         NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification]
            observers = names.map { name in
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] note in
                    let closing = note.name == NSWindow.willCloseNotification
                    MainActor.assumeIsolated { self?.update(closing: closing) }
                }
            }
            update(closing: false)
        }

        private func update(closing: Bool) {
            guard let window, !closing else { return report(false) }
            report(window.isVisible && window.occlusionState.contains(.visible))
        }

        private func report(_ visible: Bool) {
            let onChange = onChange
            DispatchQueue.main.async { onChange(visible) }
        }
    }
}
