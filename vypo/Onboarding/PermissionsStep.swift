import AppKit
import SwiftUI

/// Step 2: Microphone and Accessibility in one step, polled every second. One path per permission:
/// the microphone asks with the system prompt (or, once refused, points to System Settings);
/// Accessibility asks with the system prompt, whose button opens System Settings, and a floating
/// “Back to vypo” panel waits next to it.
struct PermissionsStep: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var accessibilityAsked: Bool
    @State private var askedAt: Date?
    @State private var showDetails: Bool
    @State private var showPane = false

    init(asked: Bool = false, details: Bool = false) {
        _accessibilityAsked = State(initialValue: asked)
        _showDetails = State(initialValue: details)
    }

    var body: some View {
        let mic = app.permissions.micGranted
        let denied = app.permissions.micDenied
        let ax = app.permissions.accessibilityTrusted
        VStack(spacing: 10) {
            OBTitle(title: "Two permissions")
                .padding(.bottom, 8)
            PermissionCard(symbol: "mic", title: "Microphone",
                           line: denied ? "Microphone access is off for vypo. Turn it on in System Settings."
                                        : "So vypo can hear you while you dictate.",
                           allowed: mic) {
                if denied {
                    Button("Open System Settings") { openMicrophoneSettings() }.buttonStyle(.ob(.rowPrimary))
                } else {
                    Button("Allow microphone…") { requestMic() }.buttonStyle(.ob(mic ? .rowBordered : .rowPrimary))
                }
            }
            PermissionCard(symbol: "accessibility", title: "Accessibility",
                           line: "So vypo notices your dictation key and can type the text for you.",
                           allowed: ax) {
                if accessibilityAsked {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Waiting for the switch…").font(OBFont.secondary).foregroundStyle(Color.vyLabelSecondary)
                        if showPane {
                            Button("Open System Settings") {
                                Permissions.openAccessibilitySettings()
                            }
                            .buttonStyle(.ob(.small))
                        }
                    }
                    .transition(.statusLine(reduceMotion: reduceMotion))
                } else {
                    // Only the next permission's button is filled.
                    Button("Allow Accessibility…") { requestAccessibility() }.buttonStyle(.ob(mic ? .rowPrimary : .rowBordered))
                }
            }
            if accessibilityAsked && !ax {
                SwitchIllustration()
                    .padding(.top, 6)
                    .transition(.opacity)
            }
            DisclosureGroup(isExpanded: $showDetails) {
                VStack(alignment: .leading, spacing: 6) {
                    detail("Accessibility", ["Notice when you press your dictation key.", "Paste your text into the field you’re typing in.",
                                             "Nothing vypo sees is saved or sent. vypo doesn’t record your screen."])
                    detail("Microphone", ["vypo listens only while you dictate. Your audio is turned into text on this Mac and then discarded. It is never saved."])
                }
                .padding(.top, 6)
            } label: {
                Text("What do these allow?").font(OBFont.secondary).foregroundStyle(Color.vyLabelSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
        .frame(width: 460)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.2), value: accessibilityAsked)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.2), value: ax)
        .task(id: askedAt) {
            // The system prompt can be dismissed with “Deny”; after a while the card offers the pane directly.
            showPane = false
            guard askedAt != nil else { return }
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled { showPane = true }
        }
        .onChange(of: ax) { _, on in if on { accessibilityAsked = true } }
    }

    private func detail(_ title: LocalizedStringKey, _ lines: [LocalizedStringKey]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(OBFont.secondarySemibold).foregroundStyle(Color.vyLabel)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line).font(OBFont.secondary).foregroundStyle(Color.vyLabelSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func requestMic() {
        Task {
            _ = await Permissions.requestMic()
            app.permissions.poll()
        }
    }

    private func openMicrophoneSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }

    private func requestAccessibility() {
        accessibilityAsked = true
        askedAt = Date()
        Permissions.requestAccessibility()
    }
}

/// A permission as a card: icon, title, one line, and a button or “Allowed” on the right.
struct PermissionCard<Trailing: View>: View {
    var symbol: String
    var title: LocalizedStringKey
    var line: LocalizedStringKey
    var allowed: Bool
    @ViewBuilder var trailing: Trailing
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(Color.vyLabelSecondary)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(OBFont.bodySemibold).foregroundStyle(Color.vyLabel)
                Text(line).font(OBFont.secondary).foregroundStyle(Color.vyLabelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if allowed {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .font(OBFont.secondarySemibold).foregroundStyle(Color.vySuccess)
                    .transition(.statusLine(reduceMotion: reduceMotion))
            } else {
                trailing
            }
        }
        .padding(.vertical, 9).padding(.horizontal, 14)
        .frame(minHeight: 54)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.vyBgGroup))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.vySeparator, lineWidth: 0.5))
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.2), value: allowed)
    }
}

/// A drawing of System Settings with the switch next to vypo, and what to do. The pointer glides to the switch,
/// clicks, the knob slides, holds, resets (2.4 s); with Reduce motion a still frame.
struct SwitchIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Group {
                if reduceMotion {
                    Image(scheme == .dark ? "Onboarding/accessibility-switch-dark" : "Onboarding/accessibility-switch-light")
                        .resizable().interpolation(.high)
                } else {
                    TimelineView(.animation) { context in
                        drawing(at: context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4))
                    }
                }
            }
            .frame(width: 248, height: 107)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Turn on the switch next to vypo.").font(OBFont.bodySemibold).foregroundStyle(Color.vyLabel)
                Text("macOS may ask for your password or Touch ID.").font(OBFont.secondary).foregroundStyle(Color.vyLabelSecondary)
                Text("vypo needs this only to notice your key and paste your text.").font(OBFont.secondary).foregroundStyle(Color.vyLabelSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Phases of the loop: glide 0 to 0.6, click 0.6 to 0.7, knob 0.7 to 0.9, hold to 2.1, reset to 2.4.
    static func phases(at t: Double) -> (pointer: Double, press: Double, knob: Double, fade: Double) {
        func ease(_ x: Double) -> Double { let c = min(max(x, 0), 1); return c * c * (3 - 2 * c) }
        let pointer = ease(t / 0.6)
        let press = t >= 0.6 && t < 0.7 ? 1.0 : 0
        let knob = 1 - pow(1 - min(max((t - 0.7) / 0.2, 0), 1), 2)
        let fade = t >= 2.1 ? ease((t - 2.1) / 0.3) : 0
        return (pointer, press, knob * (1 - fade), fade)
    }

    private func drawing(at t: Double) -> some View {
        let p = Self.phases(at: t)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.vyBgGroup)
            RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.vySeparator, lineWidth: 0.5)
            VStack(alignment: .leading, spacing: 7) {
                Text("Privacy & Security").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.vyLabelSecondary)
                Text("Accessibility").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.vyLabel)
                RoundedRectangle(cornerRadius: 3).fill(Color.vyFillTrack).frame(width: 90, height: 8)
                HStack(spacing: 6) {
                    Image("AppIconImage").resizable().frame(width: 16, height: 16)
                    Text("vypo").font(.system(size: 12)).foregroundStyle(Color.vyLabel)
                    Spacer()
                    ZStack(alignment: .leading) {
                        Capsule().fill(p.knob > 0.5 ? Color(red: 0, green: 0.478, blue: 1) : Color.vyFillTrack).frame(width: 30, height: 18)
                        Circle().fill(.white).frame(width: 14, height: 14).shadow(radius: 0.5).offset(x: 2 + 12 * p.knob)
                    }
                }
            }
            .padding(12)
            Image(systemName: "cursorarrow")
                .font(.system(size: 16))
                .foregroundStyle(Color.vyLabel)
                .scaleEffect(1 - 0.1 * p.press)
                .offset(x: 120 + (190 - 120) * p.pointer, y: 30 + (78 - 30) * p.pointer)
        }
    }
}
