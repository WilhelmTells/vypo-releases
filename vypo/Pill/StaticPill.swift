import SwiftUI

/// A pill drawn inside a window (Settings preview, onboarding stage).
struct StaticPill: View {
    var mode: PillMode
    var color: PillColor = .white
    var customColor: Color = .vyAccent
    var surface: PillBackground = .dark
    var level: () -> Float = { 0 }
    var showsShadow = true

    var body: some View {
        let size = PillMetrics.size(for: mode)
        PillView(mode: mode, color: color, customColor: customColor, surface: surface, level: level, size: size, interactive: false, showsShadow: showsShadow)
            .frame(width: size.width, height: size.height)
            .animation(.spring(Motion.pillSpring(reduceMotion: false)), value: size)
    }
}
