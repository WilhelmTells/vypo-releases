import AudioToolbox
import CoreAudio
import Foundation

/// The Core Audio output calls `AudioMuter` needs; mocked in tests.
protocol AudioOutputHardware {
    func defaultOutputDevice() -> AudioDeviceID?
    func uid(of device: AudioDeviceID) -> String?
    func device(withUID uid: String) -> AudioDeviceID?
    func isMuteSettable(_ device: AudioDeviceID) -> Bool
    func isMuted(_ device: AudioDeviceID) -> Bool?
    func setMuted(_ device: AudioDeviceID, _ muted: Bool) -> Bool
    func isVolumeSettable(_ device: AudioDeviceID) -> Bool
    func volume(_ device: AudioDeviceID) -> Float?
    func setVolume(_ device: AudioDeviceID, _ volume: Float) -> Bool
}

/// What vypo changed and must put back, persisted in case vypo crashes mid-recording.
struct PendingAudioRestore: Codable, Equatable {
    var deviceUID: String
    var unmute: Bool
    var volume: Float?
}

protocol PendingRestoreStore: AnyObject {
    var pending: PendingAudioRestore? { get set }
}

final class UserDefaultsRestoreStore: PendingRestoreStore {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = AppDefaults.standard) { self.defaults = defaults }

    var pending: PendingAudioRestore? {
        get { defaults.data(forKey: DefaultsKey.pendingAudioRestore).flatMap { try? JSONDecoder().decode(PendingAudioRestore.self, from: $0) } }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: DefaultsKey.pendingAudioRestore)
            } else {
                defaults.removeObject(forKey: DefaultsKey.pendingAudioRestore)
            }
        }
    }
}

/// Silences the system output while recording and restores exactly what it changed (§8.1).
final class AudioMuter {
    private let hardware: AudioOutputHardware
    private let store: PendingRestoreStore
    /// The device vypo changed, kept even if the default output changes meanwhile.
    private var device: AudioDeviceID?
    private var mutedByVypo = false
    private var volumeLoweredByVypo: Float?
    private var loggedUnsupported = false

    init(hardware: AudioOutputHardware = CoreAudioOutput(), store: PendingRestoreStore = UserDefaultsRestoreStore()) {
        self.hardware = hardware
        self.store = store
    }

    func mute() {
        guard device == nil, let dev = hardware.defaultOutputDevice() else { return }
        if hardware.isMuteSettable(dev) {
            if hardware.isMuted(dev) == true { return }
            if hardware.setMuted(dev, true) {
                device = dev
                mutedByVypo = true
            }
        } else if hardware.isVolumeSettable(dev), let v = hardware.volume(dev) {
            if v == 0 { return }
            if hardware.setVolume(dev, 0) {
                device = dev
                volumeLoweredByVypo = v
            }
        } else {
            if !loggedUnsupported { Log.audio.info("Output device can't be muted; leaving it alone") }
            loggedUnsupported = true
            return
        }
        if let device, let uid = hardware.uid(of: device) {
            store.pending = PendingAudioRestore(deviceUID: uid, unmute: mutedByVypo, volume: volumeLoweredByVypo)
        }
    }

    func restore() {
        if let dev = device {
            apply(device: dev, unmute: mutedByVypo, volume: volumeLoweredByVypo)
        }
        device = nil
        mutedByVypo = false
        volumeLoweredByVypo = nil
        store.pending = nil
    }

    /// At launch: restore what a previous run left muted.
    func restorePendingFromLastRun() {
        guard let pending = store.pending else { return }
        if let dev = hardware.device(withUID: pending.deviceUID) {
            apply(device: dev, unmute: pending.unmute, volume: pending.volume)
        }
        store.pending = nil
    }

    private func apply(device dev: AudioDeviceID, unmute: Bool, volume: Float?) {
        if unmute { _ = hardware.setMuted(dev, false) }
        // Keep a volume change the user made during the recording.
        if let volume, hardware.volume(dev) == 0 { _ = hardware.setVolume(dev, volume) }
    }
}

/// The real Core Audio implementation.
struct CoreAudioOutput: AudioOutputHardware {
    private func addr(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }

    private func settable(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> Bool {
        var a = addr(selector)
        guard AudioObjectHasProperty(device, &a) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &a, &settable) == noErr && settable.boolValue
    }

    private func get<T: BitwiseCopyable>(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector, _ initial: T) -> T? {
        var a = addr(selector)
        var v = initial
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(device, &a, 0, nil, &size, &v) == noErr ? v : nil
    }

    private func set<T: BitwiseCopyable>(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector, _ value: T) -> Bool {
        var a = addr(selector)
        var v = value
        return AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<T>.size), &v) == noErr
    }

    func defaultOutputDevice() -> AudioDeviceID? { AudioDevices.defaultOutputDevice() }
    func uid(of device: AudioDeviceID) -> String? { AudioDevices.uid(of: device) }
    func device(withUID uid: String) -> AudioDeviceID? { AudioDevices.device(withUID: uid) }
    func isMuteSettable(_ device: AudioDeviceID) -> Bool { settable(device, kAudioDevicePropertyMute) }
    func isMuted(_ device: AudioDeviceID) -> Bool? { get(device, kAudioDevicePropertyMute, UInt32(0)).map { $0 != 0 } }
    func setMuted(_ device: AudioDeviceID, _ muted: Bool) -> Bool { set(device, kAudioDevicePropertyMute, UInt32(muted ? 1 : 0)) }
    func isVolumeSettable(_ device: AudioDeviceID) -> Bool { settable(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume) }
    func volume(_ device: AudioDeviceID) -> Float? { get(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, Float32(0)) }
    func setVolume(_ device: AudioDeviceID, _ volume: Float) -> Bool { set(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, Float32(volume)) }
}
