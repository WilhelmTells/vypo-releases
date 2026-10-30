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
    /// The name of the device “System default” resolves to; read off the main thread with the list.
    @State private var defaultName: String?
    @State private var meter = LevelMeter()
    @State private var recorder: AudioRecorder?
    /// Counts starts: a start that finishes after the step was left, or after another device was chosen, is stopped.
    @State private var meterGeneration = 0
    @State private var metering = false
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
        .task { await loadDevices() }
        .task { await meterLoop() }
        .onDisappear {
            metering = false
            stopMetering()
        }
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

    /// From the list read when the step opened: the body never asks CoreAudio itself.
    private var deviceName: String {
        if let uid = app.prefs.inputDeviceUID, let d = devices.first(where: { $0.uid == uid }) { return d.name }
        return defaultName ?? String(localized: "System default")
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

    /// When the meter starts: after the step's 0.25 s transition, so opening the microphone never competes with it.
    static let meterDelay: Duration = .milliseconds(300)
    /// A tick of the level loop this much later than due means the main thread was blocked; it is logged.
    static let hangThreshold = 0.1

    /// Reads the input devices off the main thread: the first CoreAudio query in a process took 50–110 ms (2026-10-29).
    private func loadDevices() async {
        guard previewLevel == nil else { return }
        let preferBuiltIn = app.prefs.preferBuiltInMic
        let began = ContinuousClock.now
        let (list, name) = await Task.detached(priority: .userInitiated) {
            (AudioDevices.inputDevices(),
             AudioDevices.resolveInputDevice(selectedUID: nil, preferBuiltIn: preferBuiltIn).flatMap(AudioDevices.name(of:)))
        }.value
        devices = list
        defaultName = name
        Log.audio.notice("Microphone step: \(list.count) input devices read in \((ContinuousClock.now - began).milliseconds) ms (off the main thread)")
    }

    /// Starts the level meter after the transition, then reads the level 30 times a second.
    private func meterLoop() async {
        guard previewLevel == nil else { return }
        try? await Task.sleep(for: Self.meterDelay)
        guard !Task.isCancelled else { return }
        metering = true
        startMetering()
        detector = MicHeardDetector(now: ProcessInfo.processInfo.systemUptime)
        var due = ProcessInfo.processInfo.systemUptime + 0.033
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(33))
            let now = ProcessInfo.processInfo.systemUptime
            if now - due > Self.hangThreshold {
                Log.audio.notice("Microphone step: the main thread was blocked for about \(Int((now - due) * 1000)) ms")
            }
            due = now + 0.033
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

    /// Runs a capture session for the meter only; it never mutes. Finding the device and building the session took
    /// 60–130 ms on the main thread the first time (2026-10-29), so that happens off it; the session starts on its own
    /// queue as always.
    private func startMetering() {
        guard metering, Permissions.micGranted, recorder == nil, previewLevel == nil else { return }
        meterGeneration += 1
        let generation = meterGeneration
        let r = AudioRecorder(meter: meter)
        let uid = app.prefs.inputDeviceUID, preferBuiltIn = app.prefs.preferBuiltInMic
        let began = ContinuousClock.now
        Task {
            let failure: String? = await Task.detached(priority: .userInitiated) {
                do {
                    try r.start(device: AudioDevices.resolveInputDevice(selectedUID: uid, preferBuiltIn: preferBuiltIn), keepSamples: false)
                    return nil
                } catch {
                    return String(describing: error)
                }
            }.value
            if let failure {
                return Log.audio.error("Level metering failed: \(failure, privacy: .public)")
            }
            Log.audio.notice("Microphone step: level meter set up in \((ContinuousClock.now - began).milliseconds) ms (off the main thread)")
            // Left, or another device chosen, while it started.
            guard generation == meterGeneration, metering else { return _ = r.stop() }
            recorder = r
        }
    }

    private func stopMetering() {
        meterGeneration += 1
        _ = recorder?.stop()
        recorder = nil
    }
}
