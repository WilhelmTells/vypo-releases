import AppKit
import QuartzCore

/// The menu bar mark's motion as pure functions of time (timings and easing follow the
/// animation spec of the mark; where the spec and its preview differ, the preview wins). Lengths are SVG units.
enum MenuBarMotion {
    static func easeOut(_ t: Double) -> Double { 1 - pow(1 - t, 3) }
    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    /// Start: the whole mark tips back about the tip of the V and springs back.
    static let startDuration = 0.37

    /// Degrees at `elapsed` seconds: 0 → −14 (110 ms) → +4 (140 ms) → 0 (120 ms), each eased out.
    static func startRotation(_ elapsed: Double) -> Double {
        switch elapsed {
        case ..<0: 0
        case ..<0.11: lerp(0, -14, easeOut(elapsed / 0.11))
        case ..<0.25: lerp(-14, 4, easeOut((elapsed - 0.11) / 0.14))
        case ..<startDuration: lerp(4, 0, easeOut((elapsed - 0.25) / 0.12))
        default: 0
        }
    }

    /// Listening: the bell is a little larger even in silence, and breathes with the voice.
    static func bellScale(level: Double) -> Double { 1.04 + 0.11 * min(max(level, 0), 1) }
    /// Per-frame smoothing of the level at 60 Hz, as in the preview.
    static let levelSmoothing = 0.35
    static let bellReleaseDuration = 0.12

    /// Processing: a punched-out gap rides the coaster path once per lap.
    static let coasterDuration = 0.65
    static let coasterGap = 20.0
    static let coasterWidth = 6.0

    /// The dash phase at lap progress `t`: the gap enters at the mouthpiece and leaves past the bell.
    static func coasterPhase(_ t: Double, length: Double) -> Double { lerp(coasterGap, -length, t) }

    /// The gap fades in and out over the first and last eighth of a lap.
    static func coasterOpacity(_ t: Double) -> Double { max(0, min(1, t * 8, (1 - t) * 8)) }

    /// Inserted: a star flies out of the bell and fades.
    static let starDuration = 0.52

    /// Distance from the bell's centre along its axis, radius and opacity at progress `t`.
    static func star(_ t: Double) -> (distance: Double, radius: Double, opacity: Double) {
        (lerp(2, 26, easeOut(t)), lerp(3, 9, min(1, t * 2.5)), t < 0.6 ? 1 : max(0, 1 - (t - 0.6) / 0.4))
    }

    /// Error: a short horizontal shake.
    static let shakeDuration = 0.38

    static func shake(_ t: Double) -> Double { sin(t * .pi * 6) * 3.2 * (1 - t) }

    /// Colour fades in and out over 160 ms.
    static let tintDuration = 0.16
    /// After the star starts, the colour waits this long before it fades.
    static let tintAfterStar = 0.22
}

/// One drawn state of the mark.
struct MenuBarMarkFrame: Equatable {
    /// Degrees about the tip of the V; positive turns clockwise.
    var rotation = 0.0
    /// Horizontal offset in SVG units.
    var shake = 0.0
    var bell = 1.0
    /// Lap progress of the coaster gap, nil without one.
    var coaster: Double?
    /// Progress of the star, nil without one.
    var star: Double?
    /// 0 is the template image, 1 is fully `accent`.
    var tint = 0.0

    static let rest = MenuBarMarkFrame()
}

/// What the mark is doing, advanced by the display link (times in seconds, any clock). A value type,
/// so the whole sequence is testable without a menu bar.
struct MenuBarMarkTimeline {
    /// “Color the menu bar icon while dictating”.
    var tintOption = false
    /// No motion at all; the mark is coloured while dictating instead, whatever the option.
    var reduceMotion = false

    private(set) var recording = false
    private(set) var processing = false
    private var startAt: Double?
    private var coasterAt: Double?
    private var starAt: Double?
    private var shakeAt: Double?
    private var releaseAt: Double?
    private var releaseFrom = 1.0
    /// From the start of a dictation until its end; the tint follows it.
    private var colored = false
    private var uncolorAt: Double?
    private var level = 0.0
    private var bell = 1.0
    private var tint = 0.0
    private var lastTick: Double?

    private var tintTarget: Double { colored && (tintOption || reduceMotion) ? 1 : 0 }

    mutating func beginRecording(at now: Double) {
        recording = true
        processing = false
        colored = true
        uncolorAt = nil
        level = 0
        releaseAt = nil
        starAt = nil
        shakeAt = nil
        if !reduceMotion { startAt = now }
    }

    mutating func beginProcessing(at now: Double) {
        endRecording(at: now)
        processing = true
        if !reduceMotion && coasterAt == nil { coasterAt = now }
    }

    /// Text was pasted or copied.
    mutating func inserted(at now: Double) {
        endRecording(at: now)
        processing = false
        if !reduceMotion { starAt = now }
        if colored { uncolorAt = now + MenuBarMotion.tintAfterStar }
    }

    mutating func failed(at now: Double) {
        endRecording(at: now)
        processing = false
        if !reduceMotion { shakeAt = now }
        if colored { uncolorAt = now + (reduceMotion ? 0 : MenuBarMotion.shakeDuration) }
    }

    /// Cancelled, discarded or finished without text; keeps a colour fade already planned.
    mutating func ended(at now: Double) {
        endRecording(at: now)
        processing = false
        if colored && uncolorAt == nil { uncolorAt = now }
    }

    private mutating func endRecording(at now: Double) {
        guard recording else { return }
        recording = false
        if !reduceMotion && bell != 1 {
            releaseAt = now
            releaseFrom = bell
        }
    }

    /// Whether frames still change; false means the display link can stop.
    var isAnimating: Bool {
        startAt != nil || (recording && !reduceMotion) || releaseAt != nil || coasterAt != nil || starAt != nil
            || shakeAt != nil || uncolorAt != nil || tint != tintTarget
    }

    /// Moves to `now`; `level` is the microphone level 0–1.
    mutating func advance(to now: Double, level target: Double) -> MenuBarMarkFrame {
        // A long pause between frames (the link was stopped) must not count as one step.
        let dt = min(max(now - (lastTick ?? now), 0), 0.05)
        lastTick = now
        var frame = MenuBarMarkFrame()

        if let at = uncolorAt, now >= at {
            colored = false
            uncolorAt = nil
        }
        let step = dt / MenuBarMotion.tintDuration
        tint = tint < tintTarget ? min(tintTarget, tint + step) : max(tintTarget, tint - step)
        frame.tint = tint

        if let at = startAt {
            let elapsed = now - at
            if elapsed >= MenuBarMotion.startDuration { startAt = nil } else { frame.rotation = MenuBarMotion.startRotation(elapsed) }
        }

        if recording && !reduceMotion {
            let k = 1 - pow(1 - MenuBarMotion.levelSmoothing, dt * 60)
            level += (target - level) * k
            bell = MenuBarMotion.bellScale(level: level)
        } else if let at = releaseAt {
            let t = (now - at) / MenuBarMotion.bellReleaseDuration
            if t >= 1 {
                releaseAt = nil
                bell = 1
            } else {
                bell = MenuBarMotion.lerp(releaseFrom, 1, t)
            }
        } else {
            bell = 1
        }
        frame.bell = bell

        if let at = coasterAt {
            var t = (now - at) / MenuBarMotion.coasterDuration
            if t >= 1 {
                // Another lap while still processing; otherwise the lap just ends.
                if processing && !reduceMotion {
                    coasterAt = now
                    t = 0
                } else {
                    coasterAt = nil
                }
            }
            if coasterAt != nil { frame.coaster = t }
        }

        if let at = starAt {
            let t = (now - at) / MenuBarMotion.starDuration
            if t >= 1 { starAt = nil } else { frame.star = t }
        }

        if let at = shakeAt {
            let t = (now - at) / MenuBarMotion.shakeDuration
            if t >= 1 { shakeAt = nil } else { frame.shake = MenuBarMotion.shake(t) }
        }
        return frame
    }
}

/// Draws a frame of the mark from `MenuBarMarkPaths`.
@MainActor
enum MenuBarMarkRenderer {
    /// 18 pt for the mark plus a point of room on each side and two above and below, so the tilt,
    /// the shake and the star aren't cut off.
    static let canvas = NSSize(width: 20, height: 22)
    private static let viewBox = CGRect(x: 13.72, y: 9.87, width: 101.5, height: 101.5)
    private static let markSize: CGFloat = 18
    /// The tip of the V, the pivot of the start tilt and the bell.
    static let tip = CGPoint(x: 62, y: 104)
    /// The bell's centre and the direction it points in, from the tip.
    static let bellCentre = CGPoint(x: 94, y: 36)
    static let bellAxis: CGVector = {
        let dx = bellCentre.x - tip.x, dy = bellCentre.y - tip.y, l = (dx * dx + dy * dy).squareRoot()
        return CGVector(dx: dx / l, dy: dy / l)
    }()

    static let tube: CGPath = {
        let p = CGMutablePath()
        let v = MenuBarMarkPaths.tube
        p.move(to: CGPoint(x: v[0], y: v[1]))
        var i = 2
        while i + 5 < v.count {
            p.addCurve(to: CGPoint(x: v[i + 4], y: v[i + 5]), control1: CGPoint(x: v[i], y: v[i + 1]),
                       control2: CGPoint(x: v[i + 2], y: v[i + 3]))
            i += 6
        }
        return p
    }()

    static let arm = polygon(MenuBarMarkPaths.arm)
    static let mouthpiece = polygon(MenuBarMarkPaths.mouthpiece)
    static let rim: CGPath = {
        var t = CGAffineTransform(translationX: bellCentre.x, y: bellCentre.y).rotated(by: 25.2 * .pi / 180)
            .translatedBy(x: -bellCentre.x, y: -bellCentre.y)
        let rx: CGFloat = 16.2, ry: CGFloat = 5.7
        return CGPath(ellipseIn: CGRect(x: bellCentre.x - rx, y: bellCentre.y - ry, width: rx * 2, height: ry * 2), transform: &t)
    }()

    /// The band plus a line up into the bell: the coaster's track.
    static let coasterTrack: CGPath = {
        let p = tube.mutableCopy()!
        p.addLine(to: bellCentre)
        return p
    }()

    /// Length of `coasterTrack`, measured along flattened curves.
    static let coasterLength: Double = {
        let v = MenuBarMarkPaths.tube.map(Double.init)
        var length = 0.0
        var (x, y) = (v[0], v[1])
        var i = 2
        while i + 5 < v.count {
            for s in 1...24 {
                let t = Double(s) / 24, u = 1 - t
                let nx = u * u * u * x + 3 * u * u * t * v[i] + 3 * u * t * t * v[i + 2] + t * t * t * v[i + 4]
                let ny = u * u * u * y + 3 * u * u * t * v[i + 1] + 3 * u * t * t * v[i + 3] + t * t * t * v[i + 5]
                length += hypot(nx - x, ny - y)
                (x, y) = (nx, ny)
            }
            i += 6
        }
        return length + hypot(Double(bellCentre.x) - x, Double(bellCentre.y) - y)
    }()

    private static func polygon(_ v: [CGFloat]) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: v[0], y: v[1]))
        for i in stride(from: 2, to: v.count - 1, by: 2) { p.addLine(to: CGPoint(x: v[i], y: v[i + 1])) }
        p.closeSubpath()
        return p
    }

    /// The four-pointed star (eight points, inner radius 40 %).
    static func star(at c: CGPoint, radius r: CGFloat) -> CGPath {
        let p = CGMutablePath()
        for i in 0..<8 {
            let a = CGFloat(i) / 8 * 2 * .pi - .pi / 2, rr = i % 2 == 1 ? r * 0.4 : r
            let pt = CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }

    /// A template image at tint 0; otherwise drawn in the menu bar's ink blended toward `accent`.
    static func image(_ frame: MenuBarMarkFrame) -> NSImage {
        let tint = CGFloat(frame.tint)
        let image = NSImage(size: canvas, flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let color: NSColor
            if tint > 0 {
                // Resolved in the appearance the status button draws in.
                let ink = NSColor.textColor.usingColorSpace(.sRGB) ?? .black
                let accent = (NSColor(named: "accent") ?? .controlAccentColor).usingColorSpace(.sRGB) ?? .red
                color = ink.blended(withFraction: tint, of: accent) ?? accent
            } else {
                color = .black
            }
            draw(frame, in: ctx, color: color.cgColor)
            return true
        }
        image.isTemplate = tint == 0
        return image
    }

    static func draw(_ frame: MenuBarMarkFrame, in ctx: CGContext, color: CGColor) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        let k = markSize / viewBox.width
        ctx.translateBy(x: (canvas.width - markSize) / 2, y: (canvas.height - markSize) / 2)
        ctx.scaleBy(x: k, y: k)
        ctx.translateBy(x: -viewBox.minX + frame.shake, y: -viewBox.minY)
        ctx.translateBy(x: tip.x, y: tip.y)
        ctx.rotate(by: frame.rotation * .pi / 180)
        ctx.translateBy(x: -tip.x, y: -tip.y)

        ctx.setFillColor(color)
        ctx.setStrokeColor(color)
        ctx.setLineJoin(.round)
        // A layer of its own, so the coaster gap punches through the mark only.
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.setLineWidth(10.5)
        ctx.addPath(tube)
        ctx.strokePath()
        ctx.setLineWidth(1.5)
        ctx.addPath(mouthpiece)
        ctx.drawPath(using: .fillStroke)
        ctx.saveGState()
        ctx.translateBy(x: tip.x, y: tip.y)
        ctx.scaleBy(x: frame.bell, y: frame.bell)
        ctx.translateBy(x: -tip.x, y: -tip.y)
        ctx.addPath(arm)
        ctx.drawPath(using: .fillStroke)
        ctx.addPath(rim)
        ctx.fillPath()
        ctx.restoreGState()
        if let t = frame.coaster {
            let length = coasterLength, period = length + 2 * MenuBarMotion.coasterGap
            let phase = MenuBarMotion.coasterPhase(t, length: length).truncatingRemainder(dividingBy: period)
            ctx.saveGState()
            ctx.setBlendMode(.destinationOut)
            ctx.setAlpha(MenuBarMotion.coasterOpacity(t))
            ctx.setLineWidth(MenuBarMotion.coasterWidth)
            ctx.setLineCap(.round)
            ctx.setLineDash(phase: phase < 0 ? phase + period : phase, lengths: [MenuBarMotion.coasterGap, length + MenuBarMotion.coasterGap])
            ctx.addPath(coasterTrack)
            ctx.strokePath()
            ctx.restoreGState()
        }
        ctx.endTransparencyLayer()

        if let t = frame.star {
            let s = MenuBarMotion.star(t)
            let c = CGPoint(x: bellCentre.x + bellAxis.dx * s.distance, y: bellCentre.y + bellAxis.dy * s.distance)
            ctx.setAlpha(s.opacity)
            ctx.addPath(star(at: c, radius: s.radius))
            ctx.fillPath()
        }
    }
}

/// Plays the mark's states on the status button. Runs a display link only while something moves;
/// at rest nothing is scheduled.
@MainActor
final class MenuBarIconAnimator: NSObject {
    private weak var button: NSStatusBarButton?
    private let level: () -> Float
    private var timeline = MenuBarMarkTimeline()
    private var link: CADisplayLink?
    private var shown: MenuBarMarkFrame?

    var tintOption: Bool {
        get { timeline.tintOption }
        set {
            guard newValue != timeline.tintOption else { return }
            timeline.tintOption = newValue
            kick()
        }
    }

    init(button: NSStatusBarButton, level: @escaping () -> Float) {
        self.button = button
        self.level = level
        super.init()
        show(.rest)
    }

    func beginRecording() { event { $0.beginRecording(at: $1) } }
    func beginProcessing() { event { $0.beginProcessing(at: $1) } }
    func inserted() { event { $0.inserted(at: $1) } }
    func failed() { event { $0.failed(at: $1) } }
    func ended() { event { $0.ended(at: $1) } }

    private func event(_ apply: (inout MenuBarMarkTimeline, Double) -> Void) {
        timeline.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        apply(&timeline, CACurrentMediaTime())
        kick()
    }

    private func kick() {
        guard link == nil, let button else { return }
        let link = button.displayLink(target: self, selector: #selector(step))
        link.add(to: .main, forMode: .common)
        self.link = link
        tick()
    }

    @objc private func step(_ link: CADisplayLink) { tick() }

    private func tick() {
        let frame = timeline.advance(to: CACurrentMediaTime(), level: Double(level()))
        show(frame)
        if !timeline.isAnimating {
            link?.invalidate()
            link = nil
        }
    }

    private func show(_ frame: MenuBarMarkFrame) {
        guard frame != shown, let button else { return }
        shown = frame
        let image = MenuBarMarkRenderer.image(frame)
        image.accessibilityDescription = timeline.recording ? String(localized: "vypo, recording") : "vypo"
        button.image = image
    }
}
