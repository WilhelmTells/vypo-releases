import AppKit
import SwiftUI

/// Opens the Settings and Onboarding windows. They are AppKit windows hosting SwiftUI, so the
/// pill, the menu and shortcuts can open them from anywhere.
@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    private let app: AppState
    private var settings: NSWindow?
    private var settingsHost: NSView?
    private(set) var onboarding: NSWindow?
    /// Builds the onboarding view (set by the coordinator).
    var makeOnboarding: (Int) -> AnyView = { _ in AnyView(EmptyView()) }
    var onOnboardingClosed: () -> Void = {}

    static let settingsMinSize = NSSize(width: 720, height: 520)

    init(app: AppState) {
        self.app = app
    }

    func showSettings(_ pane: SettingsPane? = nil) {
        if let pane { app.settingsPane = pane }
        MenuDismiss.close()
        if settings == nil {
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.settingsMinSize),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = String(localized: "vypo Settings")
            window.toolbarStyle = .unified
            let host = NSHostingView(rootView: SettingsView().environment(app).tint(.vyAccent))
            host.sizingOptions = []
            host.autoresizingMask = [.width, .height]
            settingsHost = host
            window.minSize = Self.settingsMinSize
            window.isReleasedWhenClosed = false
            window.delegate = self
            // A new name, so the larger size saved before the redesign isn't restored.
            // (Not under XCTest: AppKit saves the frame in the app's real preferences, whatever `AppDefaults` says.)
            if !RunEnvironment.isTesting { window.setFrameAutosaveName("vypoSettingsCompact") }
            window.center()
            settings = window
            observeWindowStyle()
        } else if settingsHost?.window == nil {
            applyWindowStyle(app.prefs.windowStyle)
        }
        updatePresence(opening: true)
        NSApp.activate()
        settings?.makeKeyAndOrderFront(nil)
    }

    /// Applies the style now and again whenever it changes.
    private func observeWindowStyle() {
        let style = withObservationTracking { app.prefs.windowStyle } onChange: { [weak self] in
            Task { @MainActor in self?.observeWindowStyle() }
        }
        applyWindowStyle(style)
    }

    /// Glass: the whole window sits on a behind-window material, like the menu bar panel.
    /// Otherwise the window is solid, in the chosen appearance, and the sidebar keeps the system's own.
    private func applyWindowStyle(_ style: WindowStyle) {
        guard let window = settings, let host = settingsHost else { return }
        host.removeFromSuperview()
        switch style {
        case .glass:
            window.isOpaque = false
            window.backgroundColor = .clear
            let glass = NSVisualEffectView()
            glass.material = .menu
            glass.blendingMode = .behindWindow
            glass.state = .active
            glass.addSubview(host)
            window.contentView = glass
            host.frame = glass.bounds
        case .automatic, .light, .dark:
            window.isOpaque = true
            window.backgroundColor = NSColor(named: "bg-content")
            window.contentView = host
        }
        window.appearance = switch style {
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        case .automatic, .glass: nil
        }
    }

    /// Onboarding window: 680 wide, auto height (min 460), not resizable, title hidden (§16).
    func showOnboarding(step: Int) {
        MenuDismiss.close()
        if onboarding == nil {
            let host = NSHostingController(rootView: makeOnboarding(step))
            host.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentViewController: host)
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            onboarding = window
        }
        updatePresence(opening: true)
        NSApp.activate()
        onboarding?.makeKeyAndOrderFront(nil)
    }

    func closeOnboarding() {
        onboarding?.delegate = nil
        onboarding?.close()
        onboarding = nil
        updatePresence()
        onOnboardingClosed()
    }

    /// Settings or Onboarding is on screen (minimized counts).
    var isWindowOpen: Bool { openWindow(besides: nil) }

    private func openWindow(besides closing: NSWindow?) -> Bool {
        [settings, onboarding].contains { window in
            guard let window, window !== closing else { return false }
            return window.isVisible || window.isMiniaturized
        }
    }

    /// vypo is a regular app with its own menu bar while one of its windows is open.
    private func updatePresence(opening: Bool = false, closing: NSWindow? = nil) {
        AppPresence.apply(showInDock: app.prefs.showInDock, windowOpen: opening || openWindow(besides: closing), activate: false)
    }

    func windowWillClose(_ notification: Notification) {
        // Back to a menu bar app once the last window closes; showing a window again undoes both this
        // and the detached content below.
        updatePresence(closing: notification.object as? NSWindow)
        if (notification.object as? NSWindow) === settings {
            // The window is only hidden; without its content the panes disappear, so the Level row
            // stops metering and the microphone closes.
            settingsHost?.removeFromSuperview()
            settings?.contentView = nil
            return
        }
        guard (notification.object as? NSWindow) === onboarding else { return }
        onboarding = nil
        onOnboardingClosed()
    }
}

/// Closes the menu bar dropdown window.
@MainActor
enum MenuDismiss {
    static func close() {
        for w in NSApp.windows where w.isVisible && w is MenuPanel {
            w.close()
        }
    }
}

/// `NavigationSplitView` with the panes (§15).
struct SettingsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        NavigationSplitView {
            List(SettingsPane.visible, selection: $app.settingsPane) { pane in
                Label(pane.title, systemImage: pane.symbol)
                    .tag(pane)
            }
            .navigationSplitViewColumnWidth(170)
            .scrollContentBackground(.hidden)
        } detail: {
            pane(app.settingsPane)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // The window's glass or solid colour shows through; grouped sections keep their own fill.
                .scrollContentBackground(.hidden)
                .background(app.prefs.windowStyle == .glass ? Color.clear : Color.vyBgContent)
        }
        .frame(minWidth: WindowManager.settingsMinSize.width, minHeight: WindowManager.settingsMinSize.height)
    }

    @ViewBuilder private func pane(_ pane: SettingsPane) -> some View {
        switch pane {
        case .general: GeneralPane()
        case .recording: RecordingPane()
        case .appearance: AppearancePane()
        case .words: WordsPane()
        case .apps: AppsPane()
        case .history: HistoryPane()
        case .stats: StatsPane()
        case .about: AboutPane()
        }
    }
}
