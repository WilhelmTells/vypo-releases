import AppKit
import ApplicationServices
import Carbon.HIToolbox
import KeyboardShortcuts

/// Watches the dictation key with a CGEvent tap and drives `HotkeyStateMachine` (§7.1).
/// The tap never modifies events; it only swallows Esc while a recording runs (§23.3).
@MainActor
final class HotkeyMonitor {
    var onEffect: (HotkeyStateMachine.Effect) -> Void = { _ in }
    /// Return true to consume an Esc key-down (only while recording or processing).
    var onEscape: () -> Bool = { false }
    /// The dictation key went down (used to close the pill's glossary field first).
    var onKeyPress: () -> Void = {}
    /// The dictation key went down (true) or up (false), also while `enabled` is off.
    var onKeyChange: (Bool) -> Void = { _ in }
    /// You pressed ⌘V (vypo's own ⌘V doesn't count); `ClipboardKeeper` restores the clipboard after it.
    var onPaste: () -> Void = {}

    var key: DictationKey = .fn
    /// The recorded shortcut, used when `key` is `.custom`.
    var customShortcut: KeyboardShortcuts.Shortcut?
    var enabled = true
    var holdToTalk: Bool {
        get { machine.holdToTalk }
        set { machine.holdToTalk = newValue }
    }
    var doubleTapHandsFree: Bool {
        get { machine.doubleTapHandsFree }
        set { machine.doubleTapHandsFree = newValue }
    }

    private var machine = HotkeyStateMachine(preRoll: true)
    private(set) var keyIsDown = false
    /// The custom shortcut's key-down was swallowed, so its repeats and key-up are swallowed too.
    private var swallowingCustom = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var pollTimer: Timer?
    private var deadlineTimer: Timer?

    /// Device-dependent modifier bits (IOKit `NX_DEVICER*KEYMASK`).
    private static let rightOptionMask: UInt64 = 0x40
    private static let rightCommandMask: UInt64 = 0x10
    private static let rightControlMask: UInt64 = 0x2000

    var isInstalled: Bool { tap != nil }

    /// Creates the tap once Accessibility is granted, polling every second until then.
    func start() {
        // A test host, also one left running, never takes fn or other keys from the user.
        guard tap == nil, !AppDelegate.isRunningTests else { return }
        if AXIsProcessTrusted() {
            install()
        } else if pollTimer == nil {
            pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, AXIsProcessTrusted() else { return }
                    self.pollTimer?.invalidate()
                    self.pollTimer = nil
                    self.install()
                }
            }
        }
    }

    /// Ends a recording that was stopped from outside the key (stop button, Esc, limits, errors).
    func resetGesture() {
        machine.reset(keyIsDown: keyIsDown)
        scheduleDeadline()
    }

    private func install() {
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask), callback: hotkeyTapCallback, userInfo: refcon) else {
            Log.input.error("Could not create the event tap")
            return
        }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Log.input.info("Event tap installed")
    }

    func handle(type: CGEventType, flags: CGEventFlags, keyCode: Int64, isRepeat: Bool, synthetic: Bool = false) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        case .flagsChanged:
            guard let down = isDictationKeyDown(flags: flags, keyCode: keyCode) else { return false }
            guard down != keyIsDown else { return false }
            keyIsDown = down
            onKeyChange(down)
            guard enabled else { return false }
            if down { onKeyPress() }
            let now = ProcessInfo.processInfo.systemUptime
            run(down ? machine.keyDown(at: now) : machine.keyUp(at: now))
            return false
        case .keyDown:
            if keyCode == Int64(kVK_Escape), onEscape() {
                return true
            }
            if keyCode == Int64(kVK_ANSI_V), !isRepeat, !synthetic,
               flags.intersection([.maskCommand, .maskControl, .maskAlternate]) == .maskCommand {
                onPaste()
            }
            if isCustomShortcut(flags: flags, keyCode: keyCode) || (swallowingCustom && keyCode == customKeyCode) {
                if isRepeat || keyIsDown { return swallowingCustom }
                keyIsDown = true
                onKeyChange(true)
                guard enabled else { return false }
                swallowingCustom = true
                onKeyPress()
                run(machine.keyDown(at: ProcessInfo.processInfo.systemUptime))
                return true
            }
            if keyIsDown && enabled {
                run(machine.otherKey(at: ProcessInfo.processInfo.systemUptime))
            }
            return false
        case .keyUp:
            guard key == .custom, keyIsDown, keyCode == customKeyCode else { return false }
            keyIsDown = false
            onKeyChange(false)
            let swallowed = swallowingCustom
            swallowingCustom = false
            if swallowed { run(machine.keyUp(at: ProcessInfo.processInfo.systemUptime)) }
            return swallowed
        default:
            return false
        }
    }

    private var customKeyCode: Int64? { customShortcut.map { Int64($0.carbonKeyCode) } }

    /// Whether this key-down is the custom shortcut: its key with exactly its modifiers.
    /// Never while a shortcut recorder has focus, so the shortcut can be recorded again.
    func isCustomShortcut(flags: CGEventFlags, keyCode: Int64) -> Bool {
        guard key == .custom, let shortcut = customShortcut, keyCode == Int64(shortcut.carbonKeyCode) else { return false }
        let relevant: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
        var wanted: CGEventFlags = []
        if shortcut.modifiers.contains(.control) { wanted.insert(.maskControl) }
        if shortcut.modifiers.contains(.option) { wanted.insert(.maskAlternate) }
        if shortcut.modifiers.contains(.shift) { wanted.insert(.maskShift) }
        if shortcut.modifiers.contains(.command) { wanted.insert(.maskCommand) }
        return flags.intersection(relevant) == wanted && !Self.isRecordingShortcut
    }

    private static var isRecordingShortcut: Bool {
        guard let editor = NSApp?.keyWindow?.firstResponder as? NSText else { return false }
        return editor.delegate is KeyboardShortcuts.RecorderCocoa
    }

    /// Whether this flagsChanged event says the dictation key is down; nil if it's about another key.
    func isDictationKeyDown(flags: CGEventFlags, keyCode code: Int64) -> Bool? {
        switch key {
        case .custom:
            return nil
        case .fn:
            return flags.contains(.maskSecondaryFn)
        case .rightOption:
            guard code == 61 else { return nil }
            return flags.rawValue & Self.rightOptionMask != 0
        case .rightCommand:
            guard code == 54 else { return nil }
            return flags.rawValue & Self.rightCommandMask != 0
        case .rightControl:
            guard code == 62 else { return nil }
            return flags.rawValue & Self.rightControlMask != 0
        }
    }

    private func run(_ effects: [HotkeyStateMachine.Effect]) {
        scheduleDeadline()
        for e in effects { onEffect(e) }
    }

    private func scheduleDeadline() {
        deadlineTimer?.invalidate()
        deadlineTimer = nil
        guard let deadline = machine.deadline else { return }
        let delay = max(0, deadline - ProcessInfo.processInfo.systemUptime) + 0.001
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.run(self.machine.tick(at: ProcessInfo.processInfo.systemUptime))
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        deadlineTimer = timer
    }
}

private func hotkeyTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
    let flags = event.flags
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    let synthetic = event.getIntegerValueField(.eventSourceUserData) == Paster.syntheticMarker
    let consume = MainActor.assumeIsolated {
        monitor.handle(type: type, flags: flags, keyCode: keyCode, isRepeat: isRepeat, synthetic: synthetic)
    }
    return consume ? nil : Unmanaged.passUnretained(event)
}
