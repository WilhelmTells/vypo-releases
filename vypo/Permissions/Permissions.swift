import AppKit
import ApplicationServices
import AVFoundation
import Observation

/// Microphone, Accessibility and the Globe key setting (§16, §18).
enum Permissions {
    static var micStatus: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .audio) }
    static var micGranted: Bool { micStatus == .authorized }
    static var micDenied: Bool { micStatus == .denied || micStatus == .restricted }

    static func requestMic() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    static var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt and opens the Accessibility pane.
    static func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    static func openKeyboardSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
    }

    /// `AppleFnUsageType`: 0 Do Nothing, 1 Change Input Source, 2 Show Emoji & Symbols, 3 Start Dictation.
    static var globeKeyUsage: Int? {
        CFPreferencesAppSynchronize("com.apple.HIToolbox" as CFString)
        let defaults = UserDefaults(suiteName: "com.apple.HIToolbox")
        return defaults?.object(forKey: "AppleFnUsageType") as? Int
    }

    static var globeKeyFree: Bool { globeKeyUsage == 0 }

    static func globeKeyDescription(_ value: Int?) -> String {
        switch value {
        case 0: String(localized: "Do Nothing")
        case 1: String(localized: "Change Input Source")
        case 2: String(localized: "Show Emoji & Symbols")
        case 3: String(localized: "Start Dictation")
        default: String(localized: "Show Emoji & Symbols")
        }
    }
}

/// Polls permissions every second and keeps the pill's persistent error up to date.
@MainActor
@Observable
final class PermissionMonitor {
    private(set) var micGranted = Permissions.micGranted
    private(set) var micDenied = Permissions.micDenied
    private(set) var accessibilityTrusted = Permissions.accessibilityTrusted
    private(set) var globeKeyUsage = Permissions.globeKeyUsage

    @ObservationIgnored private var timer: Timer?

    var globeKeyFree: Bool { globeKeyUsage == 0 }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    func poll() {
        let mic = Permissions.micGranted
        if mic != micGranted { micGranted = mic }
        let denied = Permissions.micDenied
        if denied != micDenied { micDenied = denied }
        let ax = Permissions.accessibilityTrusted
        if ax != accessibilityTrusted { accessibilityTrusted = ax }
        let globe = Permissions.globeKeyUsage
        if globe != globeKeyUsage { globeKeyUsage = globe }
    }

    /// The error that stays in the pill until fixed.
    func persistentError(dictationKey: DictationKey) -> PillError? {
        if !accessibilityTrusted { return .noAccessibility }
        if micDenied { return .micNotAllowed }
        if dictationKey == .fn && !globeKeyFree { return .globeKeyInUse }
        return nil
    }
}
