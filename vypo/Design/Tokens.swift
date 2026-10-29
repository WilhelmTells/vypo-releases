import AppKit
import SwiftUI

/// Design tokens (§5). Colors come from `Colors.xcassets`.
extension Color {
    static let vyBgWindow = Color("bg-window")
    /// The Settings content area in the solid window styles: a warm off-white or near-black.
    static let vyBgContent = Color("bg-content")
    static let vyBgSidebar = Color("bg-sidebar")
    static let vyBgGroup = Color("bg-group")
    static let vyBgControl = Color("bg-control")
    static let vyBgMenu = Color("bg-menu")
    static let vyBgHover = Color("bg-hover")
    static let vyBgSelected = Color("bg-selected")
    static let vyFillTrack = Color("fill-track")
    static let vySeparator = Color("separator")
    static let vyBorderControl = Color("border-control")
    static let vyLabel = Color("label")
    static let vyLabelSecondary = Color("label-secondary")
    static let vyLabelTertiary = Color("label-tertiary")
    static let vyOnAccent = Color("on-accent")
    static let vyDanger = Color("danger")
    static let vyWarning = Color("warning")
    static let vySuccess = Color("success")
    /// Pastel orange behind search matches.
    static let vySearchHighlight = Color("search-highlight")
    static let vyPillBg = Color("pill-bg")
    static let vyPillBorder = Color("pill-border")
    static let vyPillInk = Color("pill-ink")
    /// vypo's vermilion, straight from the asset: `Color.accentColor` turns system blue in the menu
    /// and pill panels. Window roots also set it as `.tint` for switches and prominent buttons.
    static let vyAccent = Color("accent")
    /// The fill of the onboarding's primary buttons (white text on it, 4.6:1): #D4421F in light and dark. Fixed, not
    /// the `accent-fill` asset, whose dark variant is the lighter #F2583A.
    static let vyAccentFill = Color(.sRGB, red: 0xD4 / 255, green: 0x42 / 255, blue: 0x1F / 255)
}

extension Color {
    /// "#RRGGBB" in sRGB.
    init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(.sRGB, red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}

extension NSColor {
    /// "#RRGGBB" in sRGB.
    var hex: String {
        let c = usingColorSpace(.sRGB) ?? self
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
    }
}

enum Space {
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 20
    static let s6: CGFloat = 32
}

enum Radius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 10
    static let lg: CGFloat = 16
}

enum Motion {
    static let fast: Double = 0.12
    static func pillSpring(reduceMotion: Bool) -> Spring {
        Spring(duration: 0.3, bounce: reduceMotion ? 0 : 0.2)
    }
}

extension Font {
    static let vyKey = Font.system(size: 11, weight: .medium, design: .monospaced)
    static let vyWordmark = Font.system(size: 28, weight: .bold, design: .rounded)
    static let vyTier = Font.system(size: 10, weight: .semibold)
    static let vyBadge = Font.system(size: 10, weight: .semibold)
}

extension View {
    /// `shadow-pill` (light/dark), solid pill only.
    func pillShadow(_ scheme: ColorScheme) -> some View {
        let dark = scheme == .dark
        return self
            .shadow(color: .black.opacity(dark ? 0.5 : 0.14), radius: 7, x: 0, y: 4)
    }
}
