import KeyboardShortcuts
import SwiftUI

/// Step 5: your dictation key as big keycaps. Press it to see it detected. fn needs the Globe key setting in
/// macOS to be “Do Nothing”, or macOS opens the emoji picker while vypo listens.
struct DictationKeyStep: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressed: Bool
    @State private var detected: Bool
    @State private var showEdit = false

    init(pressed: Bool = false, detected: Bool = false) {
        _pressed = State(initialValue: pressed)
        _detected = State(initialValue: detected)
    }

    var body: some View {
        let key = app.prefs.dictationKey
        let warn = OnboardingRules.globeWarningShown(key: key, globeKeyUsage: app.permissions.globeKeyUsage)
        VStack(spacing: 0) {
            OBTitle(title: "Your dictation key", text: "Hold to talk. Double-tap for hands-free.")
                .padding(.bottom, 24)
            HStack(spacing: 12) {
                ForEach(Array(key.onboardingKeycaps.enumerated()), id: \.offset) { _, content in
                    Keycap(content: content, pressed: pressed)
                }
            }
            if key == .fn {
                Text("Default").font(OBFont.caption).foregroundStyle(Color.vyLabelSecondary)
                    .padding(.horizontal, 8).frame(height: 18)
                    .overlay(Capsule().strokeBorder(Color.vySeparator, lineWidth: 1))
                    .padding(.top, 10)
            }
            status(key: key)
                .frame(height: 20)
                .padding(.top, key == .fn ? 8 : 18)
            HStack(spacing: 8) {
                Button("Edit shortcut…") { showEdit.toggle() }
                    .buttonStyle(.ob(.rowBordered))
                    .popover(isPresented: $showEdit, arrowEdge: .bottom) { KeyEditor() }
                if key != .fn {
                    Button("Use fn (default)") { app.prefs.dictationKey = .fn; detected = false }
                        .buttonStyle(.ob(.rowBordered))
                }
            }
            .padding(.top, 12)
            if warn {
                GlobeWarningCard()
                    .padding(.top, 16)
                    .transition(.opacity)
            }
        }
        .frame(width: 460)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.2), value: warn)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.2), value: detected)
        .onAppear {
            app.onKeyChange = { down in
                pressed = down
                if down { detected = true }
            }
        }
        .onDisappear { app.onKeyChange = { _ in } }
        .onChange(of: key) { detected = false }
    }

    @ViewBuilder private func status(key: DictationKey) -> some View {
        if detected {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.vySuccess)
                Text("Detected").font(OBFont.bodySemibold).foregroundStyle(Color.vySuccess)
                Text(key.spoken).font(OBFont.body).foregroundStyle(Color.vyLabelSecondary)
            }
            .transition(.statusLine(reduceMotion: reduceMotion))
        } else {
            Text("Press \(key.spoken) to try it.").font(OBFont.body).foregroundStyle(Color.vyLabelSecondary)
        }
    }
}

/// The calm card under the keycaps while fn is the key and macOS also uses it.
private struct GlobeWarningCard: View {
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(Color.vyWarning)
                Text("fn also opens Emoji & Symbols.").font(OBFont.bodySemibold).foregroundStyle(Color.vyLabel)
            }
            Text("Set “Press 🌐 key to” or “Press fn key to” to “Do Nothing”.").font(OBFont.secondary).foregroundStyle(Color.vyLabelSecondary)
            Button("Open Keyboard Settings") { Permissions.openKeyboardSettings() }
                .buttonStyle(.ob(.small))
                .padding(.top, 4)
        }
        .multilineTextAlignment(.center)
        .padding(.vertical, 12).padding(.horizontal, 16)
        .frame(width: 360)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.vyBgGroup))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.vySeparator, lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }
}

/// Choose another single key, or record a shortcut.
private struct KeyEditor: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var prefs = app.prefs
        VStack(alignment: .leading, spacing: 10) {
            Text("Dictation key").font(OBFont.bodySemibold)
            Picker("Dictation key", selection: $prefs.dictationKey) {
                ForEach(DictationKey.singleKeys + (prefs.dictationKey == .custom ? [.custom] : [])) { Text($0.name).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            HStack {
                Text("Shortcut").font(OBFont.secondary).foregroundStyle(Color.vyLabelSecondary)
                KeyboardShortcuts.Recorder(for: .dictation) { shortcut in
                    if shortcut != nil { prefs.dictationKey = .custom }
                }
            }
        }
        .padding(14)
        .frame(width: 280)
    }
}
