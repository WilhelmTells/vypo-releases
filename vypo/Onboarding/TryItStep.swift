import SwiftUI

/// Step 6: a real text field to dictate into, with the live pill.
struct TryItStep: View {
    @Environment(AppState.self) private var app
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let key = app.prefs.dictationKey.spoken
        StepHeader(title: "Try it", text: "Click the field, hold \(key) and say something.")
        if case .downloading(let p) = app.models?.state ?? .notInstalled {
            HStack(spacing: Space.s3) {
                Text("Downloading \(ModelCatalog.speech.info.name)… \(Int(p * 100)) %")
                    .font(.callout)
                    .foregroundStyle(Color.vyLabelSecondary)
                    .fixedSize()
                ProgressBar(value: p)
            }
        }
        VStack(spacing: Space.s3) {
            // The pill appears while dictating, as on screen; its place stays reserved meanwhile.
            ZStack {
                if let liveMode {
                    StaticPill(mode: liveMode, color: app.prefs.pillColor, customColor: Color(hex: app.prefs.pillCustomColor) ?? .vyAccent, surface: app.prefs.pillBackground, level: { [meter = app.levelMeter] in meter.level })
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
            .frame(height: PillMetrics.height)
            .animation(.spring(Motion.pillSpring(reduceMotion: false)), value: liveMode == nil)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .frame(height: 4 * 18 + 4)
                    .accessibilityLabel("Try it")
                if text.isEmpty {
                    Text("Your words appear here.")
                        .foregroundStyle(Color.vyLabelTertiary)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .padding(.vertical, Space.s2)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: Radius.sm).fill(Color.vyBgWindow))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Color.vyBorderControl, lineWidth: 1))
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: Radius.md).fill(Color.vyBgGroup))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Color.vySeparator, lineWidth: 0.5))
        .onAppear { focused = true }
    }

    /// The real pill state; nil while idle.
    private var liveMode: PillMode? {
        if let e = app.persistentError, app.pillBase == .ready { return .error(e) }
        return app.pillBase == .collapsed || app.pillBase == .ready ? nil : app.pillBase
    }
}
