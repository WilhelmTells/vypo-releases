import AppKit
import SwiftUI

/// A floating panel next to System Settings: “Waiting for the switch…” and a button back to vypo. It does not
/// take focus (a non-activating panel), appears when System Settings comes to the front during step 2, and
/// closes as soon as vypo is frontmost again.
@MainActor
final class BackToVypoPanel {
    private var panel: NSPanel?
    private var observers: [NSObjectProtocol] = []
    private let app: AppState
    /// Whether onboarding is on step 2, where the panel is wanted while Accessibility is off.
    var isOnPermissionsStep: () -> Bool = { false }
    private var wasTrusted = Permissions.accessibilityTrusted

    nonisolated static let systemSettingsID = "com.apple.systempreferences"

    init(app: AppState) { self.app = app }

    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated { self?.activated(bundleID: id) }
        })
        // Accessibility came on while the panel is up: say so, and try to bring vypo forward.
        observeChanges { [weak self] in
            guard let self else { return }
            let trusted = self.app.permissions.accessibilityTrusted
            Task { @MainActor in self.accessibilityChanged(trusted) }
        }
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach { center.removeObserver($0) }
        observers = []
        close()
    }

    /// Pure rule: show for System Settings, hide for vypo.
    nonisolated static func action(activatedBundleID: String?, ownBundleID: String?, wanted: Bool) -> Action {
        if activatedBundleID == systemSettingsID, wanted { return .show }
        if activatedBundleID == ownBundleID { return .hide }
        return .none
    }

    enum Action: Equatable { case show, hide, none }

    private func activated(bundleID: String?) {
        let wanted = isOnPermissionsStep() && !app.permissions.accessibilityTrusted
        switch Self.action(activatedBundleID: bundleID, ownBundleID: Bundle.main.bundleIdentifier, wanted: wanted) {
        case .show: show()
        case .hide: close()
        case .none: break
        }
    }

    private func accessibilityChanged(_ trusted: Bool) {
        defer { wasTrusted = trusted }
        guard trusted, !wasTrusted, isOnPermissionsStep() else { return }
        // Try to come back by ourselves; if macOS doesn't let vypo take the front, the panel's button does it.
        NSApp.activate()
    }

    private func show() {
        if panel == nil {
            let hosting = NSHostingView(rootView: BackToVypoView(app: app, back: { NSApp.activate() })
                .environment(app).tint(.vyAccent))
            let size = CGSize(width: 360, height: 76)
            let p = NonActivatingPanel(contentRect: NSRect(origin: .zero, size: size),
                                       styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = .floating
            p.isFloatingPanel = true
            p.hidesOnDeactivate = false
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.becomesKeyOnlyIfNeeded = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.isReleasedWhenClosed = false
            p.contentView = hosting
            if let screen = NSScreen.main {
                let frame = screen.visibleFrame
                p.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 40))
            }
            panel = p
        }
        panel?.orderFrontRegardless()
    }

    private func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct BackToVypoView: View {
    let app: AppState
    var back: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let on = app.permissions.accessibilityTrusted
        HStack(spacing: 12) {
            Image("AppIconImage").resizable().frame(width: 28, height: 28)
            if on {
                Label("Accessibility is on", systemImage: "checkmark.circle.fill")
                    .font(OBFont.bodySemibold).foregroundStyle(Color.vySuccess)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for the switch…").font(OBFont.body).foregroundStyle(Color.vyLabel)
                }
            }
            Spacer(minLength: 0)
            Button("Back to vypo", action: back)
                .buttonStyle(.ob(on ? .rowPrimary : .rowBordered))
        }
        .padding(.horizontal, 14)
        .frame(width: 360, height: 56)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.vyBgGroup))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.vySeparator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.2), value: on)
        .frame(width: 360, height: 76)
    }
}
