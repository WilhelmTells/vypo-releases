import AppKit
import SwiftUI

/// Plays once when the voice was clearly measured (a rising pair, the style of the start sound).
@MainActor
enum ConfirmSound {
    private static var sound: NSSound?

    static func play() {
        if sound == nil, let url = Bundle.main.url(forResource: "confirm", withExtension: "wav", subdirectory: "Sounds")
            ?? Bundle.main.url(forResource: "confirm", withExtension: "wav") {
            sound = NSSound(contentsOf: url, byReference: true)
        }
        sound?.play()
    }
}

/// Step 3: the Glass pill is the live level meter on the night scene.
struct MicrophoneStep: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: OnboardingModel
    @State private var devices: [AudioInputDevice] = []
    @State private var meter = LevelMeter()
    @State private var recorder: AudioRecorder?
    @State private var detector = MicHeardDetector(now: ProcessInfo.processInfo.systemUptime)
    @State private var line: String?
    @State private var silentLong: Bool
    private let previewLevel: Float?

    /// The `preview…` values show a state without a microphone (snapshots).
    init(model: OnboardingModel, previewLine: String? = nil, previewSilent: Bool = false, previewLevel: Float? = nil) {
        self.model = model
        _line = State(initialValue: previewLine)
        _silentLong = State(initialValue: previewSilent)
        self.previewLevel = previewLevel
        if let previewLevel {
            let meter = LevelMeter()
            let samples = [Float](repeating: previewLevel, count: 480)
            for _ in 0..<30 { samples.withUnsafeBufferPointer { meter.process($0) } }
            _meter = State(initialValue: meter)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            OBTitle(title: "Say a short sentence.")
                .padding(.bottom, 14)
            ZStack {
                WoodcutStage()
                GlassStagePill(size: CGSize(width: 200, height: 80), content: .bars(flat: false),
                               level: { [meter] in meter.level }, barWidth: 7, gap: 7, minHeight: 7, maxHeight: 53)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Microphone level")
            }
            Text(statusText)
                .id(statusText)
                .font(model.micHeard ? OBFont.bodySemibold : OBFont.body)
                .foregroundStyle(silentLong && !model.micHeard ? Color.vyLabel : (model.micHeard ? Color.vySuccess : Color.vyLabelSecondary))
                .multilineTextAlignment(.center)
                .frame(height: 20)
                .padding(.top, 12)
                .transition(.statusLine(reduceMotion: reduceMotion))
            devicePicker.padding(.top, 14)
            if hasBuiltIn {
                Text("vypo understands you best through your Mac’s built-in microphone. Bluetooth headphones record in lower quality.")
                    .font(OBFont.secondary).foregroundStyle(Color.vyLabelSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .padding(.top, 8)
            }
        }
        .frame(width: 460)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.2), value: statusText)
        .onAppear { devices = AudioDevices.inputDevices() }
        .task { await meterLoop() }
        .onDisappear { stopMetering() }
        .onChange(of: app.prefs.inputDeviceUID) {
            stopMetering()
            startMetering()
        }
    }

    private var hasBuiltIn: Bool { devices.contains(where: \.isBuiltIn) }

    private var statusText: String {
        if let line, model.micHeard { return line }
        if silentLong { return String(localized: "Nothing heard. Check the microphone or pick another one.") }
        return String(localized: "Listening…")
    }

    private var deviceName: String {
        if let uid = app.prefs.inputDeviceUID, let d = devices.first(where: { $0.uid == uid }) { return d.name }
        if let id = AudioDevices.resolveInputDevice(selectedUID: nil, preferBuiltIn: app.prefs.preferBuiltInMic),
           let name = AudioDevices.name(of: id) { return name }
        return String(localized: "System default")
    }

    private var devicePicker: some View {
        @Bindable var prefs = app.prefs
        return Menu {
            Button("System default") { prefs.inputDeviceUID = nil }
            ForEach(devices) { device in
                Button(device.name) { prefs.inputDeviceUID = device.uid }
            }
        } label: {
            HStack(spacing: 6) {
                Text("Microphone: \(deviceName)").font(OBFont.secondary).foregroundStyle(Color.vyLabel)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.vyLabelSecondary)
            }
            .padding(.horizontal, 10).frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.vyBgControl))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.vySeparator, lineWidth: 0.5))
        }
        .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.plain).fixedSize()
        .accessibilityLabel("Microphone")
    }

    // MARK: Metering

    /// Starts the level meter after the step has drawn, then reads the level 30 times a second.
    private func meterLoop() async {
        guard previewLevel == nil else { return }
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled else { return }
        startMetering()
        detector = MicHeardDetector(now: ProcessInfo.processInfo.systemUptime)
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(33))
            let now = ProcessInfo.processInfo.systemUptime
            if let event = detector.feed(level: meter.level, now: now) {
                guard case .phrase(let number) = event else { continue }
                if number == 1 { ConfirmSound.play() }
                line = MicHeardDetector.playfulLine(forPhrase: number)
                model.micHeard = true
                silentLong = false
            }
            let skip = detector.showsSkip(now: now)
            if skip != silentLong { silentLong = skip }
            if model.micShowsSkip != skip { model.micShowsSkip = skip }
        }
    }

    /// Runs an engine for the meter only; it never mutes.
    private func startMetering() {
        guard Permissions.micGranted, recorder == nil, previewLevel == nil else { return }
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
        _ = recorder?.stop()
        recorder = nil
    }
}
