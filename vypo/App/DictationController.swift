import AppKit
import Carbon.HIToolbox
import CoreAudio

/// Where and how a recording started.
struct RecordingContext: Sendable {
    var bundleID: String?
    var appName: String?
    var pid: pid_t?
    var startedAt: Date
    var duration: TimeInterval = 0
    /// The app's profile mode when the recording started (§23.5).
    var mode: AppMode = .standard
    /// Started with a double tap (Hands Free achievement).
    var handsFree = false
    /// The text around the cursor, read off the main thread while the user talks (§23.1).
    /// nil when smart spacing is off.
    var insertion: Task<InsertionContext?, Never>?
}

/// One dictation on its way through processing.
@MainActor
final class DictationJob {
    /// A newer dictation started: this one goes on for History only, nothing is pasted or counted.
    fileprivate(set) var isLeftover = false
    /// The paste has begun. Set right before it; from then on the job can't become a leftover.
    var inserted = false
}

/// Runs a dictation: hotkey effects → recording → processing → back to ready (§7, §8).
@MainActor
final class DictationController {
    enum Phase: Equatable {
        case idle
        case recording(handsFree: Bool)
        case processing
    }

    private let app: AppState
    private let recorder: AudioRecorder
    private let muter: AudioMuter
    let hotkey: HotkeyMonitor

    /// Returns an error that prevents recording (model missing, app excluded, …).
    var preflight: (RecordingContext) -> PillError? = { _ in nil }
    /// The frontmost app's profile mode (§23.5).
    var modeForApp: (String?) -> AppMode = { _ in .standard }
    /// Called when a recording starts (pill screen, model preload).
    var onRecordingStarted: (RecordingContext) -> Void = { _ in }
    /// Transcribes, cleans up and pastes. Must check for cancellation and `DictationJob.isLeftover` before pasting.
    var process: ([Float], RecordingContext, DictationJob) async -> Void = { _, _, _ in }
    /// The input device to record from.
    var inputDevice: () -> AudioDeviceID? = { AudioDevices.defaultInputDevice() }

    private(set) var phase: Phase = .idle
    private var context: RecordingContext?
    private var processingTask: Task<Void, Never>?
    private var processingJob: DictationJob?
    /// The dictation a newer one sent to the background. Only one at a time.
    private var leftover: (job: DictationJob, task: Task<Void, Never>)?
    private var handsFreeTimer: Timer?
    private var muteWork: DispatchWorkItem?
    /// The capture session started on key-down (`prepare`), and the one kept after a short tap.
    private var preRoll = PreRoll()
    /// Stops a lingering pre-roll session when the double-tap window is over.
    private var lingerWork: DispatchWorkItem?
    /// Polls until the microphone delivers sound, then plays the start sound.
    private var liveTimer: Timer?
    private var startSoundPlayed = false

    static let handsFreeLimit: TimeInterval = 600
    static let handsFreeSilenceLimit: TimeInterval = 60

    init(app: AppState, recorder: AudioRecorder, muter: AudioMuter, hotkey: HotkeyMonitor) {
        self.app = app
        self.recorder = recorder
        self.muter = muter
        self.hotkey = hotkey
        hotkey.onEffect = { [weak self] in self?.handle($0) }
        hotkey.onEscape = { [weak self] in self?.escape() ?? false }
        app.onStopTapped = { [weak self] in self?.stopHandsFreeFromPill() }
    }

    private func handle(_ effect: HotkeyStateMachine.Effect) {
        switch effect {
        case .startPushToTalk: begin(handsFree: false)
        case .startHandsFree: begin(handsFree: true)
        case .stopPushToTalk, .stopHandsFree: finish()
        case .cancelPushToTalk: cancel()
        case .prepare: prepare()
        case .discardPrepared: lingerPrepared()
        }
    }

    // MARK: Pre-roll

    /// Starts capturing on key-down so the words in the 200 ms hold window are kept. Not for
    /// Bluetooth mics (every fn press would switch them into call mode), and never where a
    /// recording couldn't start anyway.
    private func prepare() {
        guard phase == .idle, preRoll.prepared == nil, Permissions.micGranted, !IsSecureEventInputEnabled(),
              let device = inputDevice(), !AudioDevices.isBluetooth(device) else { return }
        lingerWork?.cancel()
        lingerWork = nil
        switch preRoll.prepare(device) {
        case .reuse:
            // The second press of a double tap: the session is still running; the pre-roll starts now.
            recorder.clearSamples()
        case .start:
            do {
                try recorder.start(device: device)
            } catch {
                preRoll.discard()
                Log.audio.error("Pre-roll failed to start: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// After a short tap the session keeps running through the double-tap window: stopping a capture
    /// session right after it started sometimes hangs in CoreMedia for seconds, and a second press
    /// would have had to wait for it.
    private func lingerPrepared() {
        guard preRoll.linger() else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.preRoll.lingerEnded() else { return }
                self.lingerWork = nil
                self.recorder.stop()
            }
        }
        lingerWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + HotkeyStateMachine.doubleTapWindow + 0.05, execute: work)
    }

    /// Stops a prepared or lingering session now.
    private func discardPrepared() {
        lingerWork?.cancel()
        lingerWork = nil
        if preRoll.discard() { recorder.stop() }
    }

    // MARK: Start

    private func begin(handsFree: Bool) {
        guard phase == .idle else {
            // A new recording during processing: the old dictation finishes in the background.
            guard phase == .processing else { return }
            moveProcessingToBackground()
            return begin(handsFree: handsFree)
        }
        if app.pillBase == .add { app.cancelAdd() }

        let front = NSWorkspace.shared.frontmostApplication
        var ctx = RecordingContext(bundleID: front?.bundleIdentifier, appName: front?.localizedName,
                                   pid: front?.processIdentifier, startedAt: Date())
        ctx.mode = modeForApp(ctx.bundleID)
        ctx.handsFree = handsFree
        if ctx.mode == .excluded {
            fail(.offInThisApp)
            return
        }

        if let error = preflight(ctx) {
            fail(error)
            return
        }
        if IsSecureEventInputEnabled() {
            fail(.secureInput)
            return
        }
        if Permissions.micDenied {
            fail(.micNotAllowed)
            return
        }
        if Permissions.micStatus == .notDetermined {
            hotkey.resetGesture()
            Task { _ = await Permissions.requestMic() }
            return
        }

        // The pill goes up first; the recorder starts its session off the main thread.
        app.setPill(handsFree ? .handsfree : .listening)
        let device = inputDevice()
        Log.audio.notice("Recording from \(device.flatMap(AudioDevices.name(of:)) ?? "no device", privacy: .public)")
        do {
            if let device, preRoll.take(device) {
                Log.audio.notice("Using the audio captured since key-down")
            } else {
                discardPrepared()
                try recorder.start(device: device)
            }
        } catch {
            Log.audio.error("Recording failed to start: \(String(describing: error), privacy: .public)")
            fail(.noMicrophone)
            return
        }

        if app.prefs.smartSpacing && app.prefs.pasteAutomatically {
            ctx.insertion = Task.detached(priority: .userInitiated) { ContextReader.insertionContext() }
        }
        context = ctx
        phase = .recording(handsFree: handsFree)
        startAudioEffects()
        onRecordingStarted(ctx)
        if handsFree { startHandsFreeWatch() }
    }

    private func fail(_ error: PillError) {
        discardPrepared()
        hotkey.resetGesture()
        app.showError(error)
    }

    // MARK: Stop

    /// Ends the recording and transcribes it.
    func finish() {
        guard case .recording = phase, var ctx = context else { return }
        stopHandsFreeWatch()
        let samples = recorder.stop()
        stopAudioEffects()
        ctx.duration = Date().timeIntervalSince(ctx.startedAt)
        context = nil

        let seconds = Double(samples.count) / AudioRecorder.sampleRate
        let peak = app.levelMeter.peakDB
        let verdict = RecordingFilter.verdict(sampleCount: samples.count, peakDB: peak)
        guard verdict == .transcribe else {
            Log.audio.notice("Discarded recording (\(String(describing: verdict), privacy: .public)): \(seconds, format: .fixed(precision: 2)) s, peak \(peak, format: .fixed(precision: 1)) dBFS")
            phase = .idle
            if verdict == .tooQuiet { app.showError(.tooQuiet) } else { app.setPill(.ready) }
            app.report(.nothingHeard)
            return
        }
        Log.audio.notice("Recorded \(seconds, format: .fixed(precision: 2)) s, peak \(peak, format: .fixed(precision: 1)) dBFS")
        startProcessing(samples, ctx)
    }

    func startProcessing(_ samples: [Float], _ ctx: RecordingContext) {
        phase = .processing
        app.setPill(.processing)
        let process = self.process
        let job = DictationJob()
        processingJob = job
        processingTask = Task { [weak self] in
            await process(samples, ctx, job)
            guard let self else { return }
            if self.leftover?.job === job { self.leftover = nil }
            guard self.processingJob === job else { return }
            self.phase = .idle
            if self.app.pillBase == .processing { self.app.setPill(.ready) }
            self.processingJob = nil
            self.processingTask = nil
        }
    }

    /// A new dictation takes over from the one in processing, which is never lost silently: it finishes for History.
    func moveProcessingToBackground() {
        guard phase == .processing, let job = processingJob, let task = processingTask else { return }
        // Already pasted: only its History entry and count are left, and they finish by themselves.
        if !job.inserted {
            if app.prefs.saveHistory {
                if let oldest = leftover {
                    oldest.task.cancel()
                    Log.asr.notice("Cancelled the dictation in the background: a third one started")
                }
                job.isLeftover = true
                leftover = (job, task)
                Log.asr.notice("A new dictation started: the one in processing finishes in the background, for History only")
            } else {
                task.cancel()
                Log.asr.notice("A new dictation started: the one in processing is dropped, History is off")
            }
        }
        processingJob = nil
        processingTask = nil
        phase = .idle
        hotkey.resetGesture()
        app.setPill(.ready)
    }

    /// Discards the recording or transcription; nothing is pasted.
    func cancel() {
        switch phase {
        case .idle:
            return
        case .recording:
            stopHandsFreeWatch()
            recorder.stop()
            stopAudioEffects()
            context = nil
        case .processing:
            processingTask?.cancel()
            processingTask = nil
            processingJob = nil
        }
        phase = .idle
        hotkey.resetGesture()
        app.setPill(.ready)
    }

    private func stopHandsFreeFromPill() {
        guard phase == .recording(handsFree: true) else { return }
        hotkey.resetGesture()
        finish()
    }

    /// Esc during listening, hands-free or processing cancels and is consumed (§23.3).
    private func escape() -> Bool {
        guard phase != .idle else { return false }
        cancel()
        return true
    }

    // MARK: Hands-free limits

    private func startHandsFreeWatch() {
        handsFreeTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let ctx = self.context else { return }
                let now = Date()
                if now.timeIntervalSince(ctx.startedAt) >= Self.handsFreeLimit
                    || now.timeIntervalSince(self.app.levelMeter.lastLoudAt) >= Self.handsFreeSilenceLimit {
                    self.hotkey.resetGesture()
                    self.finish()
                }
            }
        }
    }

    private func stopHandsFreeWatch() {
        handsFreeTimer?.invalidate()
        handsFreeTimer = nil
    }

    // MARK: Sounds and muting (§8, §8.1)

    /// The start sound waits until the microphone delivers sound (up to 1.5 s), so it tells you
    /// when to start talking: right away with a pre-rolled mic, after ~0.7 s with Bluetooth.
    private func startAudioEffects() {
        startSoundPlayed = false
        let began = Date()
        if playStartSoundIfLive(began: began) { return }
        let timer = Timer(timeInterval: 0.01, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.playStartSoundIfLive(began: began) else { return }
                self.liveTimer?.invalidate()
                self.liveTimer = nil
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        liveTimer = timer
    }

    /// Plays the start sound once the mic is live or the wait is over; true when done waiting.
    private func playStartSoundIfLive(began: Date) -> Bool {
        guard case .recording = phase else { return true }
        let waited = Date().timeIntervalSince(began)
        let live = app.levelMeter.peakDB > LevelMeter.liveDB
        guard live || waited > 1.5 else { return false }
        Log.audio.notice("Start sound after \(Int(waited * 1000)) ms (\(live ? "mic live" : "timed out", privacy: .public))")
        playStartAndMute()
        return true
    }

    private func playStartAndMute() {
        var delay: TimeInterval = 0
        if let sound = app.prefs.recordingSound.start {
            sound.play()
            delay = sound.duration
        }
        startSoundPlayed = true
        guard app.prefs.muteWhileRecording else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, case .recording = self.phase else { return }
                self.muter.mute()
            }
        }
        muteWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func stopAudioEffects() {
        liveTimer?.invalidate()
        liveTimer = nil
        muteWork?.cancel()
        muteWork = nil
        muter.restore()
        if startSoundPlayed { app.prefs.recordingSound.stop?.play() }
        startSoundPlayed = false
    }

    /// At quit: put the audio back.
    func shutdown() {
        if case .recording = phase { recorder.stop() }
        discardPrepared()
        muter.restore()
    }
}

/// The pre-roll's bookkeeping (§8): which device a session was prepared for, and which one lingers
/// after a short tap so a quick second press reuses it instead of restarting the capture session.
struct PreRoll: Equatable {
    enum Start: Equatable {
        /// A new session; `AudioRecorder.start` stops a lingering one for another device itself.
        case start
        /// The lingering session for this device keeps running.
        case reuse
    }

    private(set) var prepared: AudioDeviceID?
    private(set) var lingering: AudioDeviceID?

    mutating func prepare(_ device: AudioDeviceID) -> Start {
        let reuse = lingering == device
        prepared = device
        lingering = nil
        return reuse ? .reuse : .start
    }

    /// A short tap: the prepared session lingers. False if there was none.
    mutating func linger() -> Bool {
        guard let prepared else { return false }
        lingering = prepared
        self.prepared = nil
        return true
    }

    /// The double-tap window is over: true if a session still lingers and should stop.
    mutating func lingerEnded() -> Bool {
        guard lingering != nil else { return false }
        lingering = nil
        return true
    }

    /// A recording takes the prepared session if it is for `device`.
    mutating func take(_ device: AudioDeviceID) -> Bool {
        guard prepared == device else { return false }
        prepared = nil
        return true
    }

    /// Forgets both; true if a session was running and should stop.
    @discardableResult
    mutating func discard() -> Bool {
        defer {
            prepared = nil
            lingering = nil
        }
        return prepared != nil || lingering != nil
    }
}
