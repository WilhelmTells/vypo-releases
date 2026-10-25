import AppKit
import KeyboardShortcuts
import SwiftUI

/// Settings → Recording (§15).
struct RecordingPane: View {
    @Environment(AppState.self) private var app
    @State private var devices: [AudioInputDevice] = []
    @State private var meter = LevelMeter()
    @State private var recorder: AudioRecorder?

    var body: some View {
        @Bindable var prefs = app.prefs
        Form {
            Section {
                Picker("Dictation key", selection: $prefs.dictationKey) {
                    ForEach(DictationKey.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.menu)
                if prefs.dictationKey == .custom {
                    ShortcutRow(title: "Shortcut", description: "Any key with modifiers, e.g. ⌃⌥D. Hold it or double-tap it like a single key.", name: .dictation)
                }
                if prefs.dictationKey == .fn && app.globeKeyUsage != 0 {
                    GlobeKeyWarning()
                }
                Toggle("Hold to talk", isOn: $prefs.holdToTalk)
                    .disabled(!prefs.doubleTapHandsFree)
                Toggle("Double-tap for hands-free", isOn: $prefs.doubleTapHandsFree)
                    .disabled(!prefs.holdToTalk)
                ShortcutRow(title: "Undo last dictation", name: .undoDictation)
                ShortcutRow(title: "Add selected word to glossary", name: .addToGlossary)
            } header: {
                PaneSectionHeader(pane: .recording, title: "Shortcut")
            } footer: {
                Text("Hold the key while you talk. Double-tap it to keep listening until you tap again. Esc cancels a recording.")
            }

            Section {
                Picker("Input device", selection: $prefs.inputDeviceUID) {
                    Text("System default").tag(String?.none)
                    ForEach(devices) { Text($0.name).tag(String?.some($0.uid)) }
                }
                .pickerStyle(.menu)
                Toggle(isOn: $prefs.preferBuiltInMic) {
                    RowLabel(title: "Always use built-in microphone",
                             description: "Records with the Mac’s own microphone, so AirPods keep playing in full quality. Not used with the lid closed.")
                }
                LabeledContent("Level") {
                    VoiceBars(color: .vyAccent, level: { [meter] in meter.level })
                }
                Picker(selection: $prefs.recordingSound) {
                    ForEach(RecordingSound.allCases, id: \.self) { Text($0.name).tag($0) }
                } label: {
                    RowLabel(title: "Sound", description: "Plays when a recording starts and stops.")
                }
                .pickerStyle(.menu)
                .onChange(of: prefs.recordingSound) { prefs.recordingSound.preview() }
                Toggle(isOn: $prefs.muteWhileRecording) {
                    RowLabel(title: "Mute audio while recording", description: "Mutes other sound while you dictate, so it doesn’t end up in the recording.")
                }
            } header: {
                Text("Microphone")
            }
        }
        .formStyle(.grouped)
        .onAppear { devices = AudioDevices.inputDevices() }
        .task {
            // Starting the engine blocks for a moment (much longer with Bluetooth), so the pane
            // draws first and the Level row comes alive right after.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            startMetering()
        }
        .onDisappear { stopMetering() }
        .onChange(of: prefs.inputDeviceUID) {
            stopMetering()
            startMetering()
        }
    }

    /// Runs an engine for the Level row only; it never mutes.
    private func startMetering() {
        guard Permissions.micGranted else { return }
        let r = AudioRecorder(meter: meter)
        let device = AudioDevices.resolveInputDevice(selectedUID: app.prefs.inputDeviceUID, preferBuiltIn: app.prefs.preferBuiltInMic)
        do {
            try r.start(device: device, keepSamples: false)
            recorder = r
        } catch {
            Log.audio.error("Level metering failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func stopMetering() {
        recorder?.stop()
        recorder = nil
    }
}

/// “The Globe key is still assigned in System Settings.” (§15)
struct GlobeKeyWarning: View {
    var body: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.vyWarning)
                .accessibilityLabel("Warning")
            Text("The Globe key is still assigned in System Settings.")
                .font(.callout)
                .foregroundStyle(Color.vyLabel)
            Spacer(minLength: Space.s2)
            Button("Open Keyboard Settings…") { Permissions.openKeyboardSettings() }
        }
    }
}

/// A row with a label, an optional description and a shortcut recorder.
struct ShortcutRow: View {
    var title: LocalizedStringKey
    var description: LocalizedStringKey?
    var name: KeyboardShortcuts.Name

    var body: some View {
        LabeledContent {
            KeyboardShortcuts.Recorder(for: name)
        } label: {
            RowLabel(title: title, description: description)
        }
    }
}

/// Colour swatches for the pill's bars; the last one opens the colour panel for a colour of your own.
struct PillColorPicker: View {
    @Binding var selection: PillColor
    @Binding var customHex: String

    private var custom: Color { Color(hex: customHex) ?? .vyAccent }

    var body: some View {
        HStack(spacing: Space.s2) {
            ForEach(PillColor.allCases, id: \.self) { color in
                Button {
                    selection = color
                    if color == .custom {
                        ColorPanel.open(hex: customHex) { customHex = $0 }
                    }
                } label: {
                    swatch(color)
                        .frame(width: 16, height: 16)
                        .padding(3)
                        .overlay(Circle().strokeBorder(selection == color ? Color.vyAccent : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .help(color.name)
                .accessibilityLabel(color.name)
                .accessibilityAddTraits(selection == color ? .isSelected : [])
            }
        }
        .onDisappear { ColorPanel.close() }
    }

    /// The custom swatch shows its colour inside a rainbow ring.
    @ViewBuilder private func swatch(_ color: PillColor) -> some View {
        if color == .custom {
            Circle().fill(custom)
                .padding(3)
                .overlay(Circle().strokeBorder(AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red], center: .center), lineWidth: 3))
        } else {
            Circle()
                .fill(color == .white ? Color(white: 0.92) : color.color(on: .dark, custom: custom))
                .overlay(Circle().strokeBorder(Color.black.opacity(0.15), lineWidth: 0.5))
        }
    }
}

/// The shared macOS colour panel, reporting each change as "#RRGGBB".
@MainActor
private enum ColorPanel {
    private final class Target: NSObject {
        var onChange: (String) -> Void = { _ in }
        @objc func changed(_ panel: NSColorPanel) { onChange(panel.color.hex) }
    }

    private static let target = Target()

    static func open(hex: String, onChange: @escaping (String) -> Void) {
        let panel = NSColorPanel.shared
        target.onChange = { _ in }
        panel.showsAlpha = false
        panel.mode = .wheel
        panel.color = NSColor(Color(hex: hex) ?? .vyAccent)
        target.onChange = onChange
        panel.setTarget(target)
        panel.setAction(#selector(Target.changed(_:)))
        panel.isContinuous = true
        panel.orderFront(nil)
    }

    static func close() {
        guard NSColorPanel.sharedColorPanelExists else { return }
        NSColorPanel.shared.setTarget(nil)
        NSColorPanel.shared.close()
    }
}
