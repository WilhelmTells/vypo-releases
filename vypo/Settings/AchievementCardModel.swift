import Foundation

// What the achievements card shows, as pure data: which art each slot draws, the counter and the secrets line, the
// popover's lines and the press, step by step. Values from `design/achievements/final/vypo-achievements/` (CARD.md,
// MOTION.md); the views are in `AchievementsCard.swift`.

/// The printed layers of one stamp state, stacked bottom to top with no offset (README of the package).
struct AchievementArt: Equatable {
    let id: AchievementID
    /// `locked` (the pre-print), `unlocked` (Discover), `found` (Curious) or `tier1` … `tier5`.
    let state: String

    /// The art for `stamped` tiers: the pre-print until the first stamp.
    init(id: AchievementID, stamped: Int) {
        self.id = id
        let kind = Achievements.definition(id).kind
        switch (kind, stamped) {
        case (_, 0): state = "locked"
        case (.discover, _): state = "unlocked"
        case (.curious, _): state = "found"
        default: state = "tier\(stamped)"
        }
    }

    /// A found Curious before its first stamp: the package has no pre-print for it (hidden ones are never drawn), so
    /// the card draws the dashed circle of the secrets line instead.
    var isSecret: Bool { state == "locked" && Achievements.definition(id).kind == .curious }

    var layers: [String] {
        if isSecret { return [] }
        switch state {
        case "locked": return ["shadow", "shape", "motif"]
        case "unlocked": return ["shape", "motif"]
        case "found": return ["shadow", "paperEdge", "shape", "recess", "motif", "outline"]
        default:
            let tier = Int(state.dropFirst(4)) ?? 1
            // The ultramarine ground only under Time Back's fifth tier; the pressed edge only on foil (not vermilion).
            var layers: [String] = []
            if id == .timeBack && tier == 5 { layers.append("ground") }
            if tier > 1 { layers.append("shadow") }
            layers.append("shape")
            layers += (1...tier).map { "ring\($0)" }
            layers.append("motif")
            return layers
        }
    }

    func image(_ layer: String, dark: Bool) -> String {
        "Achievements/\(id.rawValue)-\(dark ? "dark" : "light")-\(state)-\(layer)"
    }
}

/// The stamp tool's face: vermilion for a first stamp, bronze for a tier-up.
enum StampFace: String {
    case vermilion, bronze

    /// Back to front, as in the package: shadows, block, handle, pad.
    static let parts = ["blockShadow", "handleShadow", "padShadow", "block", "handle", "pad"]

    func image(_ part: String, dark: Bool) -> String { "Achievements/tool-\(rawValue)-\(dark ? "dark" : "light")-\(part)" }
}

/// One place in the grid.
struct AchievementSlot: Equatable, Identifiable {
    let status: AchievementStatus
    var id: AchievementID { status.id }

    /// What lies on the paper now: the pre-print, or the last stamped tier (a ready tier-up keeps the old print).
    var art: AchievementArt { AchievementArt(id: status.id, stamped: status.stampedLevel) }
    /// What a click prints: the highest reached tier (one click stamps every ready tier).
    var stampedArt: AchievementArt { AchievementArt(id: status.id, stamped: status.level) }
    var isReady: Bool { status.isReady }
    /// The tool waiting over a ready slot; nil when nothing is ready.
    var face: StampFace? { status.isReady ? (status.isStamped ? .bronze : .vermilion) : nil }
}

/// The whole card: the visible slots in order, the counter and the secrets line.
struct AchievementCardContent: Equatable {
    static let kindOrder: [AchievementKind] = [.discover, .milestone, .habit, .curious]

    let slots: [AchievementSlot]
    /// Reached (stamped or ready), of all 20.
    let reached: Int
    let total: Int
    let ready: Int
    let secretsLeft: Int

    /// Discover, Milestones, the Habit, then the found Curious; within a kind in the order of `AchievementID`.
    /// Hidden Curious are never drawn, only counted.
    init(_ all: [AchievementStatus]) {
        let order = AchievementID.allCases
        slots = all.filter { !$0.isHidden }
            .sorted {
                let a = Self.kindOrder.firstIndex(of: $0.kind)!, b = Self.kindOrder.firstIndex(of: $1.kind)!
                return a != b ? a < b : order.firstIndex(of: $0.id)! < order.firstIndex(of: $1.id)!
            }
            .map(AchievementSlot.init)
        reached = all.filter { !$0.isLocked }.count
        total = all.count
        ready = all.filter(\.isReady).count
        secretsLeft = all.filter(\.isHidden).count
    }

    /// “12 of 20”.
    var reachedPart: String { String(localized: "\(reached) of \(total)") }
    /// “2 ready to stamp”; nil when nothing is ready.
    var readyPart: String? { ready > 0 ? String(localized: "\(ready) ready to stamp") : nil }
    /// “12 of 20, 2 ready to stamp”; without the second part when nothing is ready.
    var counter: String { readyPart.map { "\(reachedPart), \($0)" } ?? reachedPart }

    /// “4 secrets left”; nil when none is left.
    var secrets: String? { secretsLeft > 0 ? String(localized: "\(secretsLeft) secrets left") : nil }
}

/// The card's words: names, the popover's lines and the accessibility labels.
enum AchievementText {
    /// Names stay English in every language (like “Pill”); Regular has a name per tier.
    static func name(_ id: AchievementID, tier: Int = 1) -> String {
        switch id {
        case .firstWords: String(localized: "First Words")
        case .wordKeeper: String(localized: "Word Keeper")
        case .bookworm: String(localized: "Bookworm")
        case .swapArtist: String(localized: "Swap Artist")
        case .rightTool: String(localized: "Right Tool")
        case .handsFree: String(localized: "Hands Free")
        case .secondThoughts: String(localized: "Second Thoughts")
        case .polyglot: String(localized: "Polyglot")
        case .tales: String(localized: "Tales")
        case .timeBack: String(localized: "Time Back")
        case .longBreath: String(localized: "Long Breath")
        case .wordCollector: String(localized: "Word Collector")
        case .bookshelf: String(localized: "Bookshelf")
        case .regular:
            switch tier {
            case 3: String(localized: "Old Friend")
            case 2: String(localized: "Familiar Voice")
            default: String(localized: "Regular")
            }
        case .nightOwl: String(localized: "Night Owl")
        case .earlyBird: String(localized: "Early Bird")
        case .threeTongues: String(localized: "Three Tongues")
        case .chatterbox: String(localized: "Chatterbox")
        case .sayMyName: String(localized: "Say My Name")
        case .wellTravelled: String(localized: "Well Travelled")
        }
    }

    /// The tier's material, as printed (CARD.md): tier 1 is vermilion ink, the last tiers gold.
    static func material(tier: Int, of tiers: Int) -> String {
        let materials = tiers == 3 ? ["ink", "silver", "gold"] : ["ink", "bronze", "silver", "gold", "gold"]
        switch materials[min(max(tier, 1), materials.count) - 1] {
        case "bronze": return String(localized: "bronze")
        case "silver": return String(localized: "silver")
        case "gold": return String(localized: "gold")
        default: return String(localized: "ink")
        }
    }

    static func number(_ n: Double, locale: Locale) -> String { Int(n.rounded()).formatted(.number.locale(locale)) }

    /// “10 hours”, in words, in vypo's language.
    static func hours(minutes: Double, locale: Locale) -> String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours], width: .wide).locale(locale))
    }

    /// “3 min”, as the Stats pane writes minutes (`StatsMath.savedText`); no abbreviation point, so none doubles up
    /// with a sentence's.
    static func minutes(seconds: Double) -> String {
        String(localized: "\(Int((seconds / 60).rounded())) min")
    }

    /// “1 min 14 s”, “34 s”, “3 min”.
    static func length(seconds: Double) -> String {
        let total = Int(seconds.rounded()), m = total / 60, s = total % 60
        if m == 0 { return String(localized: "\(s) s") }
        return s == 0 ? String(localized: "\(m) min") : String(localized: "\(m) min \(s) s")
    }

    private static func work(_ words: Double) -> String {
        Work.all.first { Double($0.words) == words }?.title() ?? ""
    }

    /// Line 3: what the tier asks for. One sentence that reads as a goal while locked and as a fact once reached.
    static func condition(_ id: AchievementID, tier: Int, locale: Locale) -> String {
        let d = Achievements.definition(id)
        let goal = d.thresholds[min(max(tier, 1), d.tiers) - 1]
        let n = number(goal, locale: locale)
        switch id {
        case .firstWords: return String(localized: "A first dictation.")
        case .wordKeeper: return String(localized: "A first word in the glossary.")
        case .bookworm: return String(localized: "Glossary words taken from a document.")
        case .swapArtist: return String(localized: "A replacement of your own.")
        case .rightTool: return String(localized: "An app set to Prompt or Writing.")
        case .handsFree: return String(localized: "A hands-free dictation.")
        case .secondThoughts: return String(localized: "A dictation undone.")
        case .polyglot: return String(localized: "Dictations in two languages.")
        case .tales: return String(localized: "\(n) dictations.")
        case .timeBack: return String(localized: "\(hours(minutes: goal, locale: locale)) saved by dictating instead of typing.")
        case .longBreath: return String(localized: "One dictation over \(minutes(seconds: goal)).")
        case .wordCollector: return String(localized: "\(n) words in the glossary.")
        case .bookshelf: return String(localized: "As many words as \(work(goal)).")
        case .regular: return String(localized: "Dictated on \(n) different days.")
        case .nightOwl: return String(localized: "A dictation between midnight and 4 a.m.")
        case .earlyBird: return String(localized: "A dictation between 4 and 6 a.m.")
        case .threeTongues: return String(localized: "Three languages in one day.")
        case .chatterbox: return String(localized: "\(n) dictations in one day.")
        case .sayMyName: return String(localized: "“vypo” in a dictation.")
        case .wellTravelled: return String(localized: "Dictated in \(n) different apps.")
        }
    }

    /// Line 5: towards the next tier, only for achievements with tiers while one is left. Before the first tier it
    /// only says how far.
    static func next(_ s: AchievementStatus, locale: Locale) -> String? {
        guard s.tiers > 1, let goal = s.next else { return nil }
        let rest = max(0, goal - s.value)
        let n = number(goal, locale: locale)
        let first = s.level == 0
        switch s.id {
        case .tales:
            let left = amount(rest, .dictations, locale: locale)
            return first ? String(localized: "\(left) to go.") : String(localized: "Next tier at \(n) dictations, \(left) to go.")
        case .timeBack:
            let saved = StatsMath.savedText(minutes: rest)
            return first ? String(localized: "\(saved) to go.")
                : String(localized: "Next tier at \(hours(minutes: goal, locale: locale)), \(saved) to go.")
        case .longBreath:
            let longest = length(seconds: s.value)
            if first { return s.value > 0 ? String(localized: "Longest so far: \(longest).") : nil }
            return String(localized: "Next tier at one dictation over \(minutes(seconds: goal)). Longest so far: \(longest).")
        case .wordCollector:
            let left = amount(rest, .words, locale: locale)
            return first ? String(localized: "\(left) to go.") : String(localized: "Next tier at \(n) glossary words, \(left) to go.")
        case .bookshelf:
            let left = amount(rest, .words, locale: locale)
            return first ? String(localized: "\(left) to go.") : String(localized: "Next tier: as many words as \(work(goal)). \(left) to go.")
        case .regular:
            let left = amount(rest, .days, locale: locale)
            return first ? String(localized: "\(left) to go.") : String(localized: "Next tier at \(n) days, \(left) to go.")
        case .chatterbox:
            return String(localized: "Next tier at \(n) dictations in one day. Record so far: \(amount(s.value, .dictations, locale: locale)).")
        case .wellTravelled:
            return String(localized: "Next tier at \(n) apps, \(amount(rest, .apps, locale: locale)) to go.")
        default:
            return nil
        }
    }

    enum Unit { case dictations, words, days, apps }

    /// “854 dictations”, “1 day”, in vypo's language and number format: what is left always says what it counts.
    static func amount(_ value: Double, _ unit: Unit, locale: Locale) -> String {
        let n = number(value, locale: locale)
        let one = Int(value.rounded()) == 1
        switch unit {
        case .dictations: return one ? String(localized: "1 dictation") : String(localized: "\(n) dictations")
        case .words: return one ? String(localized: "1 word") : String(localized: "\(n) words")
        case .days: return one ? String(localized: "1 day") : String(localized: "\(n) days")
        case .apps: return one ? String(localized: "1 app") : String(localized: "\(n) apps")
        }
    }

    /// The popover's lines (CARD.md). Locked: name and condition. A ready one shows the tier it reached.
    static func popover(_ s: AchievementStatus, locale: Locale) -> AchievementPopoverText {
        let tier = max(s.level, 1)
        var tierLine: String?
        if s.tiers > 1, s.level > 0 {
            tierLine = s.kind == .curious ? String(localized: "Tier \(s.level) of \(s.tiers)")
                : String(localized: "Tier \(s.level) of \(s.tiers), \(material(tier: s.level, of: s.tiers))")
        }
        var date: String?
        if s.isReady {
            date = String(localized: "Ready to stamp.")
        } else if let day = s.stampedOn.flatMap(Self.date) {
            date = String(localized: "Stamped \(day.formatted(.dateTime.day().month(.abbreviated).year().locale(locale)))")
        }
        return AchievementPopoverText(name: name(s.id, tier: tier), tier: tierLine, condition: condition(s.id, tier: tier, locale: locale),
                                      date: date, next: next(s, locale: locale))
    }

    /// “yyyy-MM-dd” as noon of that local day.
    static func date(_ day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    /// The slot for VoiceOver: name and state; the tier where there are tiers.
    static func accessibilityLabel(_ s: AchievementStatus) -> String {
        let name = name(s.id, tier: max(s.level, 1))
        if s.isReady { return String(localized: "\(name), ready to stamp. Click to stamp.") }
        if s.isLocked { return String(localized: "\(name), locked.") }
        if s.tiers > 1 { return String(localized: "\(name), stamped, tier \(s.stampedLevel) of \(s.tiers).") }
        return String(localized: "\(name), stamped.")
    }
}

struct AchievementPopoverText: Equatable {
    var name: String
    var tier: String?
    var condition: String
    var date: String?
    var next: String?
}

/// The press, in 12 fps steps (MOTION.md). Positions in units of the stamp size S from the slot's top left.
enum StampMotion {
    static let fps = 12.0
    /// Step 13 (1.08 s): the stars are gone, at rest.
    static let steps = 13
    static var duration: Double { Double(steps) / fps }
    static let reducedDuration = 0.25

    struct Tool: Equatable {
        /// The pad's bottom edge, centred on the slot.
        var padBottom: Double
        /// Drawn width; the tool's canvas is 63 pt wide at 1×.
        var width: Double
        /// Pressed: the handle squashes, block and pad widen.
        var squashed = false
        var rotation = 0.0
    }

    struct Ellipse: Equatable {
        var center: CGPoint
        var radii: CGSize
    }

    struct Star: Equatable {
        var center: CGPoint
        var size: Double
    }

    struct Frame: Equatable {
        /// The new print is on the paper.
        var stamped = false
        var tool: Tool?
        var ground: Ellipse?
        /// The burst after the lift (the star image).
        var stars: [Star] = []
        /// The one still star over a ready slot, drawn as the stamp renderer's vector star.
        var readyStar: Star?
        var pressLines = false
    }

    static let readyTool = Tool(padBottom: 0.45, width: 0.68)
    static let readyGround = Ellipse(center: CGPoint(x: 0.5, y: 0.78), radii: CGSize(width: 0.34, height: 0.05))
    /// `Stamp.dc.html` (“ready-star”): radius 9 in the 100-unit stamp box, so 0.18 S across its points.
    static let readyStar = Star(center: CGPoint(x: 0.80, y: -0.22), size: 0.18)
    /// Waiting for the click: completely still.
    static let ready = Frame(tool: readyTool, ground: readyGround, readyStar: readyStar)

    static let pressWidth = 1.23
    /// The burst around the stamp's centre after the lift.
    static let burst: [Star] = [
        Star(center: CGPoint(x: -0.58, y: -0.68), size: 0.35),
        Star(center: CGPoint(x: 0.64, y: -0.83), size: 0.42),
        Star(center: CGPoint(x: 0.74, y: -0.01), size: 0.27),
        Star(center: CGPoint(x: -0.70, y: 0.14), size: 0.27),
        Star(center: CGPoint(x: 0.04, y: -1.04), size: 0.29),
    ]

    static func step(at t: Double) -> Int { Int((max(0, t) * fps + 1e-6).rounded(.down)) }

    /// The press at `t` seconds after the click; the unlock and the tier-up share it.
    static func frame(at t: Double) -> Frame {
        let n = step(at: t)
        switch n {
        case 0...1:
            return Frame(tool: Tool(padBottom: 0.33, width: pressWidth),
                         ground: Ellipse(center: CGPoint(x: 0.5, y: 0.80), radii: CGSize(width: 0.40, height: 0.06)))
        case 2:
            return Frame(tool: Tool(padBottom: 0.85, width: pressWidth))
        case 3...5:
            return Frame(tool: Tool(padBottom: 0.88, width: pressWidth, squashed: true), pressLines: true)
        case 6:
            return Frame(stamped: true, tool: Tool(padBottom: 0.06, width: pressWidth, rotation: -4))
        case 7..<steps:
            // Every step after the first: 0.04 S down and 10 % smaller.
            let k = Double(n - 7)
            return Frame(stamped: true, stars: burst.map {
                Star(center: CGPoint(x: 0.5 + $0.center.x, y: 0.5 + $0.center.y + 0.04 * k), size: $0.size * (1 - 0.1 * k))
            })
        default:
            return Frame(stamped: true)
        }
    }
}

/// The tilt towards the pointer while hovering a stamp (MOTION.md), in two steps in and out.
enum HoverTilt {
    static let maxAngle = 10.0
    static let scale = 1.05
    /// Perspective distance 3.7 S.
    static let perspective = 1 / 3.7
    static let stepDuration = 1 / 12.0
    static let popoverDelay = 0.25

    /// `pointer` from -1 to 1 across the stamp on each axis; `phase` 0, 0.5 or 1.
    static func angles(pointer: CGPoint, phase: Double) -> (x: Double, y: Double, scale: Double) {
        let px = min(max(pointer.x, -1), 1), py = min(max(pointer.y, -1), 1)
        // The side under the pointer dips away from the viewer.
        return (x: py * maxAngle * phase, y: -px * maxAngle * phase, scale: 1 + (scale - 1) * phase)
    }
}
