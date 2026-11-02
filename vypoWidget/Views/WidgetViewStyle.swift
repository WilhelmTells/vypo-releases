import SwiftUI
import WidgetKit

/// The two looks of “Edit Widget”.
enum WidgetLook: String, Sendable {
    case woodcut, plain

    /// The “Woodcut look” switch of “Edit Widget”.
    init(woodcut: Bool) { self = woodcut ? .woodcut : .plain }
}

/// Where the widget's images are: its own catalog, or the tests' copy.
enum WidgetAssets {
    private final class Marker {}
    nonisolated(unsafe) static var bundle = Bundle(for: Marker.self)
}

/// The colours of `SPEC.md`, per look and mode.
struct WidgetPalette {
    let label: Color
    let secondary: Color
    let track: Color
    let fill: Color
    /// Five steps, empty to busiest.
    let activity: [Color]
    let accented: Bool

    private static let vermilion = Color(hex: 0xC2462B)

    init(look: WidgetLook, dark: Bool, accented: Bool) {
        self.accented = accented
        if accented {
            label = .primary
            secondary = .secondary
            track = .white.opacity(0.26)
            fill = .white
            activity = [0.14, 0.36, 0.56, 0.78, 1].map { Color.white.opacity($0) }
            return
        }
        switch (look, dark) {
        case (.woodcut, false):
            label = Color(hex: 0x1D1711)
            secondary = Color(hex: 0x5A4F42)
            activity = [Color(hex: 0x1D1711).opacity(0.09)] + [0.28, 0.50, 0.75, 1].map { Self.vermilion.opacity($0) }
        case (.woodcut, true):
            label = Color(hex: 0xF3E9CF)
            secondary = Color(hex: 0xB8AD95)
            activity = [Color(hex: 0xF3E9CF).opacity(0.10)] + [0.42, 0.62, 0.82, 1].map { Self.vermilion.opacity($0) }
        case (.plain, false):
            label = Color(hex: 0x1D1D1F)
            secondary = Color(hex: 0x636366)
            activity = [0xE3E3E8, 0xF6C6B8, 0xEB9E87, 0xE2714F, 0xD4421F].map { Color(hex: $0) }
        case (.plain, true):
            label = Color(hex: 0xF5F5F7)
            secondary = Color(hex: 0x98989D)
            activity = [0x48484A, 0x6B3226, 0x9C3F2B, 0xCC4C30, 0xF2583A].map { Color(hex: $0) }
        }
        track = Color(hex: dark ? 0x48484A : 0xE3E3E8)
        fill = Color(hex: dark ? 0xF2583A : 0xD4421F)
    }
}

extension Color {
    fileprivate init(hex: UInt32) {
        self.init(.sRGB, red: Double(hex >> 16 & 255) / 255, green: Double(hex >> 8 & 255) / 255, blue: Double(hex & 255) / 255)
    }
}

/// The widget's words in vypo's language, which may differ from the system's, and its numbers in the system's format.
struct WidgetText {
    let bundle: Bundle
    let locale: Locale
    private static let topLevel = 10

    init(snapshot: WidgetSnapshot) {
        locale = Locale(identifier: snapshot.numberLocale)
        bundle = Bundle.main.path(forResource: snapshot.uiLanguage, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    }

    func number(_ n: Int) -> String { n.formatted(.number.locale(locale)) }

    func level(_ n: Int) -> String { String(localized: "Level \(n)", bundle: bundle) }
    func levelOf(_ n: Int) -> String { let top = Self.topLevel; return String(localized: "Level \(n) of \(top)", bundle: bundle) }
    var next: String { String(localized: "widget.next", defaultValue: "Next", bundle: bundle, comment: "Caption over the next rank on the widget") }
    var madeIt: String { String(localized: "You made it.", bundle: bundle) }
    func toGo(_ n: Int) -> String { let s = number(n); return String(localized: "\(s) to go", bundle: bundle) }
    func toRank(_ n: Int, _ rank: String) -> String { let s = number(n); return String(localized: "\(s) to \(rank)", bundle: bundle, comment: "Words left to the next rank") }
    func ofWords(_ a: Int, _ b: Int) -> String { let x = number(a), y = number(b); return String(localized: "\(x) / \(y) words", bundle: bundle) }
    func words(_ n: Int) -> String { let s = number(n); return String(localized: "\(s) words", bundle: bundle) }
    func todayLabel(_ n: Int) -> String { n == 1 ? String(localized: "word today", bundle: bundle) : String(localized: "words today", bundle: bundle) }
    var todayCaption: String { String(localized: "Words today", bundle: bundle) }
    var saved: String { String(localized: "saved", bundle: bundle, comment: "After a time, on the widget: 3 h 20 min saved") }
    var comparison: String { String(localized: "Compared with typing at 40 wpm", bundle: bundle) }
    var lastMonths: String { String(localized: "Last 6 months", bundle: bundle) }
    var less: String { String(localized: "Less", bundle: bundle) }
    var more: String { String(localized: "More", bundle: bundle) }
    var fillsIn: String { String(localized: "Fills in as you dictate", bundle: bundle) }
    var readyToStamp: String { String(localized: "Ready to stamp", bundle: bundle) }
    var firstStamp: String { String(localized: "Your first dictation stamps it.", bundle: bundle) }
    var suggestionPrefix: String { String(localized: "Glossary suggestion:", bundle: bundle) }
    var statsOffTitle: String { String(localized: "Stats are off", bundle: bundle) }
    var statsOffBody: String { String(localized: "Turn on Collect stats in vypo.", bundle: bundle) }
    var openTitle: String { String(localized: "Open vypo", bundle: bundle) }
    var openBody: String { String(localized: "Your level shows up here.", bundle: bundle) }

    /// “Unlocked yesterday”, from the day it was stamped.
    func unlocked(day: String?, now: Date, calendar: Calendar = .current) -> String {
        let parts = (day ?? "").split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else {
            return String(localized: "Unlocked today", bundle: bundle)
        }
        let days = calendar.dateComponents([.day], from: date, to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ...0: return String(localized: "Unlocked today", bundle: bundle)
        case 1: return String(localized: "Unlocked yesterday", bundle: bundle)
        default: return String(localized: "Unlocked \(days) days ago", bundle: bundle)
        }
    }
}

/// A sample for the widget gallery, before the app has written anything: the design's middle state.
extension WidgetSnapshot {
    static var sample: WidgetSnapshot {
        var s = WidgetSnapshot()
        s.level = 4
        s.rankName = "Scribe"
        s.nextRankName = "Herald"
        s.words = 40_000
        s.rankStart = 25_000
        s.nextStart = 50_000
        s.progress = 0.6
        s.today = Date()
        s.wordsToday = 1_240
        s.savedText = "3 h 20 min"
        s.activity = (0..<27).map { c in (0..<7).map { r in c > 8 && (c * 7 + r) % 3 != 0 ? (c * 31 + r * 17) % 100 : 0 } }
        s.latest = Achievement(id: "wordKeeper", name: "Word Keeper", day: nil)
        s.numberLocale = Locale.current.identifier
        return s
    }
}
