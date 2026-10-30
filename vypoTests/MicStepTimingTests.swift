import AppKit
import AVFoundation
import XCTest
@testable import vypo

/// Measures what entering the onboarding's Microphone step does on the main thread, call by call, the first and the
/// second time in the process. Opt-in (`VYPO_MIC_TIMING=<file>`, as `TEST_RUNNER_VYPO_MIC_TIMING`), since it opens the
/// default microphone for a moment. Writes one line per call to the file.
@MainActor
final class MicStepTimingTests: XCTestCase {
    private var lines: [String] = []

    private func time<T>(_ name: String, _ body: () throws -> T) rethrows -> T {
        let start = ContinuousClock.now
        let result = try body()
        let ms = Double((ContinuousClock.now - start) / .microseconds(1)) / 1000
        lines.append(String(format: "%-46@ %8.1f ms%@", name as NSString, ms, ms > 16 ? "  > 16 ms" : ""))
        return result
    }

    func testMainThreadWorkOfTheMicrophoneStep() throws {
        guard let path = ProcessInfo.processInfo.environment["VYPO_MIC_TIMING"] else { throw XCTSkip("opt-in") }
        let prefs = AppState().prefs
        for round in 1...2 {
            lines.append("-- round \(round) (\(round == 1 ? "first calls in this process" : "second calls"))")
            time("Onboarding stage image (NSImage + bitmap)") {
                _ = NSImage(named: "Onboarding/woodcut-stage")?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            }
            _ = time("Permissions.micGranted") { Permissions.micGranted }
            _ = time("Permissions.accessibilityTrusted (poll, 1/s)") { Permissions.accessibilityTrusted }
            _ = time("Permissions.globeKeyUsage (poll, 1/s)") { Permissions.globeKeyUsage }
            let devices = time("AudioDevices.inputDevices() (onAppear)") { AudioDevices.inputDevices() }
            let device = time("resolveInputDevice (startMetering, body)") {
                AudioDevices.resolveInputDevice(selectedUID: prefs.inputDeviceUID, preferBuiltIn: prefs.preferBuiltInMic)
            }
            _ = time("AudioDevices.name (deviceName, every body)") { device.flatMap(AudioDevices.name(of:)) }
            let uid = device.flatMap(AudioDevices.uid(of:))
            let capture = time("AVCaptureDevice(uniqueID:)") { uid.flatMap { AVCaptureDevice(uniqueID: $0) } }
            guard let capture else { lines.append("no capture device"); break }
            let input = try time("AVCaptureDeviceInput(device:)") { try AVCaptureDeviceInput(device: capture) }
            let output = AVCaptureAudioDataOutput()
            let session = AVCaptureSession()
            time("session configuration (add input/output, commit)") {
                session.beginConfiguration()
                if session.canAddInput(input) { session.addInput(input) }
                if session.canAddOutput(output) { session.addOutput(output) }
                session.commitConfiguration()
            }
            // As in the step: the session starts on its own queue while the view keeps asking for the device's name.
            let queue = DispatchQueue(label: "vypo.timing.session")
            let started = expectation(description: "started")
            let startedAt = ContinuousClock.now
            var startMs = 0.0
            queue.async {
                session.startRunning()
                startMs = Double((ContinuousClock.now - startedAt) / .microseconds(1)) / 1000
                started.fulfill()
            }
            var worst = 0.0, calls = 0
            let end = Date().addingTimeInterval(1.5)
            while Date() < end {
                let t = ContinuousClock.now
                _ = AudioDevices.resolveInputDevice(selectedUID: prefs.inputDeviceUID, preferBuiltIn: prefs.preferBuiltInMic).flatMap(AudioDevices.name(of:))
                _ = AudioDevices.inputDevices()
                worst = max(worst, Double((ContinuousClock.now - t) / .microseconds(1)) / 1000)
                calls += 1
                RunLoop.main.run(until: Date().addingTimeInterval(1 / 60))
            }
            wait(for: [started], timeout: 10)
            lines.append(String(format: "%-46@ %8.1f ms  (own queue, not the main thread)", "session.startRunning()" as NSString, startMs))
            lines.append(String(format: "%-46@ %8.1f ms%@  (%d calls while it started)", "worst CoreAudio query meanwhile (main)" as NSString,
                                worst, worst > 16 ? "  > 16 ms" : "", calls))
            time("session.stopRunning() (app: own queue)") { session.stopRunning() }
            lines.append("devices: \(devices.count), default input Bluetooth: \(device.map(AudioDevices.isBluetooth) ?? false)")
        }
        try write(to: path)
    }

    /// The step's way since the fix, in a fresh process (run it alone): the device list and the meter's session are
    /// set up off the main thread. Measures the longest the main run loop went without a turn meanwhile.
    func testMainThreadGapsWithTheStepsWay() throws {
        guard let path = ProcessInfo.processInfo.environment["VYPO_MIC_TIMING"] else { throw XCTSkip("opt-in") }
        let prefs = AppState().prefs
        let uid = prefs.inputDeviceUID, preferBuiltIn = prefs.preferBuiltInMic
        let recorder = AudioRecorder(meter: LevelMeter())
        var done = false
        let began = ContinuousClock.now
        Task {
            _ = await Task.detached { AudioDevices.inputDevices() }.value
            _ = await Task.detached {
                try? recorder.start(device: AudioDevices.resolveInputDevice(selectedUID: uid, preferBuiltIn: preferBuiltIn), keepSamples: false)
            }.value
            done = true
        }
        var worst = 0.0, last = ContinuousClock.now
        while !done || ContinuousClock.now - began < .milliseconds(500) {
            RunLoop.main.run(until: Date().addingTimeInterval(1 / 120))
            let now = ContinuousClock.now
            worst = max(worst, Double((now - last) / .microseconds(1)) / 1000)
            last = now
        }
        let total = Double((ContinuousClock.now - began) / .microseconds(1)) / 1000
        recorder.stop()
        lines.append(String(format: "-- the step's way (off the main thread): longest main run loop gap %.1f ms%@, set up within %.0f ms",
                            worst, worst > 16 ? "  > 16 ms" : "", total))
        try write(to: path)
    }

    private func write(to path: String) throws {
        let text = lines.joined(separator: "\n") + "\n"
        let url = URL(fileURLWithPath: path)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile(); handle.write(Data(text.utf8)); try handle.close()
        } else {
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
