@preconcurrency import AVFoundation
import CoreAudio
import CoreMedia
import Synchronization

enum AudioRecorderError: Error {
    case noInputDevice
    case engineFailed(String)
}

/// Records the selected input as 16 kHz mono Float32, in memory only (§8).
///
/// Uses a capture session rather than AVAudioEngine: the engine's input node first binds to the system
/// default input, which flips a Bluetooth headset into its call mode even when another mic is selected,
/// and the resulting format change stops the engine mid-recording. A capture session opens only the
/// device asked for, follows its format changes, and converts to 16 kHz itself.
final class AudioRecorder: Sendable {
    static let sampleRate: Double = 16_000
    static let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!

    private struct Running {
        let session: AVCaptureSession
        /// `startRunning` and `stopRunning` block for a while, so they never run on the main thread.
        /// Each session has its own queue: a stop that hangs (it sometimes does right after a start)
        /// mustn't hold up the next session's start.
        let queue: DispatchQueue
        let sink: CaptureSink
        let errorObserver: NSObjectProtocol
    }

    private let meter: LevelMeter
    private let samples = Mutex<[Float]>([])
    private let running = Mutex<Running?>(nil)
    /// Bumped on every start and stop; buffers from an earlier session are dropped.
    private let generation = Atomic<Int>(0)
    private let bufferQueue = DispatchQueue(label: "vypo.recorder.buffers", qos: .userInteractive)

    init(meter: LevelMeter) {
        self.meter = meter
    }

    var isRunning: Bool { running.withLock { $0 != nil } }

    /// Starts capturing from `device`; audio arrives shortly after this returns.
    /// With `keepSamples == false` it only meters (Settings → Level).
    func start(device: AudioDeviceID?, keepSamples: Bool = true) throws {
        stopSession()
        samples.withLock { $0.removeAll(keepingCapacity: true) }
        meter.reset()

        guard let device, let uid = AudioDevices.uid(of: device),
              let capture = AVCaptureDevice(uniqueID: uid) ?? AVCaptureDevice.default(for: .audio) else {
            throw AudioRecorderError.noInputDevice
        }
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: capture)
        } catch {
            throw AudioRecorderError.engineFailed(error.localizedDescription)
        }
        let output = AVCaptureAudioDataOutput()
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: true,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let session = AVCaptureSession()
        session.beginConfiguration()
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            throw AudioRecorderError.engineFailed("session")
        }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()

        let gen = generation.add(1, ordering: .sequentiallyConsistent).newValue
        let sink = CaptureSink(recorder: self, generation: gen, keepSamples: keepSamples)
        output.setSampleBufferDelegate(sink, queue: bufferQueue)
        let observer = NotificationCenter.default.addObserver(forName: AVCaptureSession.runtimeErrorNotification,
                                                              object: session, queue: nil) { note in
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? Error
            Log.audio.error("Capture session error: \(error?.localizedDescription ?? "unknown", privacy: .public)")
        }
        let queue = DispatchQueue(label: "vypo.recorder.session.\(gen)")
        running.withLock { $0 = Running(session: session, queue: queue, sink: sink, errorObserver: observer) }
        queue.async { Self.timed("Starting") { session.startRunning() } }
    }

    /// Logs a start or stop that blocks for long: the microphone stays open until a stop returns.
    private static func timed(_ what: String, _ body: () -> Void) {
        let began = ContinuousClock.now
        body()
        let ms = (ContinuousClock.now - began) / .milliseconds(1)
        if ms > 500 { Log.audio.notice("\(what, privacy: .public) the capture session took \(Int(ms)) ms") }
    }

    /// Stops and returns everything recorded since `start`.
    @discardableResult
    func stop() -> [Float] {
        stopSession()
        return samples.withLock { s in
            defer { s = [] }
            return s
        }
    }

    /// Drops what was captured so far and keeps capturing: a reused pre-roll starts at the new key-down.
    func clearSamples() {
        samples.withLock { $0.removeAll(keepingCapacity: true) }
    }

    fileprivate var currentGeneration: Int { generation.load(ordering: .sequentiallyConsistent) }

    fileprivate func process(_ chunk: UnsafeBufferPointer<Float>, keep: Bool) {
        meter.process(chunk)
        if keep { samples.withLock { $0.append(contentsOf: chunk) } }
    }

    private func stopSession() {
        generation.add(1, ordering: .sequentiallyConsistent)
        let old = running.withLock { r -> Running? in
            defer { r = nil }
            return r
        }
        guard let old else { return }
        NotificationCenter.default.removeObserver(old.errorObserver)
        old.queue.async { Self.timed("Stopping") { old.session.stopRunning() } }
    }
}

/// Runs on the buffer queue: hands each 16 kHz buffer to the recorder while its session is current.
private final class CaptureSink: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private weak var recorder: AudioRecorder?
    private let generation: Int
    private let keepSamples: Bool

    init(recorder: AudioRecorder, generation: Int, keepSamples: Bool) {
        self.recorder = recorder
        self.generation = generation
        self.keepSamples = keepSamples
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let recorder, recorder.currentGeneration == generation else { return }
        var list = AudioBufferList()
        var block: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: &list,
            bufferListSize: MemoryLayout<AudioBufferList>.size, blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil, flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &block)
        guard status == noErr, let data = list.mBuffers.mData else { return }
        let count = Int(list.mBuffers.mDataByteSize) / MemoryLayout<Float>.size
        recorder.process(UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: count), keep: keepSamples)
    }
}

/// What happens to a finished recording (§7.2): too short is an accidental tap and goes silently;
/// too quiet (AirPods in their case, the wrong microphone) says so instead of letting the model
/// guess words from noise.
enum RecordingFilter {
    enum Verdict: Equatable {
        case transcribe, tooShort, tooQuiet
    }

    static let minimumDuration: TimeInterval = 0.3
    /// Speech close to a microphone peaks around −25 to −10 dBFS.
    static let minimumPeakDB: Float = -40

    static func verdict(sampleCount: Int, sampleRate: Double = AudioRecorder.sampleRate, peakDB: Float) -> Verdict {
        if Double(sampleCount) / sampleRate < minimumDuration { return .tooShort }
        if peakDB < minimumPeakDB { return .tooQuiet }
        return .transcribe
    }
}

/// Silence around a recording before transcription: Parakeet tends to drop a word that starts at the
/// very first sample, and Bluetooth microphones begin with a moment of digital silence.
enum AudioPadding {
    static let seconds = 0.3

    static func padded(_ samples: [Float], sampleRate: Double = AudioRecorder.sampleRate) -> [Float] {
        let silence = [Float](repeating: 0, count: Int(seconds * sampleRate))
        return silence + samples + silence
    }
}
