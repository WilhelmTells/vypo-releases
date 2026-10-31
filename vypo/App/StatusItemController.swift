import AppKit
import SwiftUI

/// The menu bar icon; left and right click open the same panel (§14). An AppKit status item with
/// a panel instead of `MenuBarExtra`, so the app being dictated into stays frontmost.
@MainActor
final class StatusItemController: NSObject {
    private let app: AppState
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var panel: MenuPanel?
    private var animator: MenuBarIconAnimator?
    private var lastMode: PillMode = .ready
    private var lastInsertions = 0

    init(app: AppState) {
        self.app = app
        super.init()
        guard let button = item.button else { return }
        animator = MenuBarIconAnimator(button: button) { [meter = app.levelMeter] in meter.level }
        button.target = self
        button.action = #selector(clicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityLabel("vypo")
        lastInsertions = app.insertions
        observeChanges { [weak self] in
            guard let self else { return }
            self.update(mode: self.app.pillBase, insertions: self.app.insertions,
                        tint: self.app.prefs.menuBarTintWhileDictating)
        }
    }

    /// Turns the dictation's pill states into the mark's animations (§14).
    private func update(mode: PillMode, insertions: Int, tint: Bool) {
        guard let animator else { return }
        animator.tintOption = tint
        // Text arrives before the pill goes back to ready; both can show up in one change.
        if insertions != lastInsertions {
            lastInsertions = insertions
            animator.inserted()
        }
        let wasBusy = lastMode.isRecording || lastMode.isProcessing
        let isBusy = mode.isRecording || mode.isProcessing
        if mode.isRecording && !lastMode.isRecording {
            animator.beginRecording()
        } else if mode.isProcessing && !lastMode.isProcessing {
            animator.beginProcessing()
        } else if case .error = mode, mode != lastMode {
            animator.failed()
        } else if wasBusy && !isBusy {
            animator.ended()
        }
        lastMode = mode
    }

    @objc private func clicked() {
        if panel != nil {
            closePanel()
        } else {
            show()
        }
    }

    private func show() {
        guard let button = item.button, let buttonWindow = button.window else { return }
        let panel = MenuPanel(content: AnyView(MenuBarContent().environment(app).tint(.vyAccent)))
        panel.onClose = { [weak self, weak panel] in
            guard let self, self.panel === panel else { return }
            self.panel = nil
            self.item.button?.highlight(false)
        }
        self.panel = panel
        button.highlight(true)
        panel.show(below: buttonWindow.convertToScreen(button.convert(button.bounds, to: nil)))
    }

    func closePanel() {
        panel?.close()
    }
}

/// A menu-like panel: translucent, rounded, and it closes on Esc, an outside click or losing focus.
/// It never activates vypo, so the app being dictated into stays frontmost.
final class MenuPanel: NSPanel {
    var onClose: () -> Void = {}
    private let host: MenuHostingView
    private var outsideClickMonitor: Any?

    init(content: AnyView) {
        host = MenuHostingView(rootView: content)
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false

        let effect = NSVisualEffectView()
        effect.material = .menu
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = Self.roundedMask(radius: 10)
        // The panel follows the content's size itself; SwiftUI must not drive the window's size limits.
        host.sizingOptions = [.intrinsicContentSize]
        host.autoresizingMask = [.width, .height]
        host.onSizeChange = { [weak self] in self?.fitContent() }
        effect.addSubview(host)
        contentView = effect
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Opens under `anchor` (the status button, in screen coordinates), kept on its screen.
    func show(below anchor: CGRect) {
        let size = host.fittingSize
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: anchor.midX, y: anchor.midY)) } ?? NSScreen.main
        var origin = CGPoint(x: anchor.minX, y: anchor.minY - 4 - size.height)
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - 8 - size.width)
        }
        setFrame(CGRect(origin: origin, size: size), display: true)
        host.frame = contentView?.bounds ?? .zero
        makeKeyAndOrderFront(nil)
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    /// Keeps the top edge in place when the content grows or shrinks.
    private func fitContent() {
        guard isVisible else { return }
        let size = host.fittingSize
        guard size != frame.size else { return }
        setFrame(CGRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height), display: true)
    }

    override func resignKey() {
        super.resignKey()
        close()
    }

    override func cancelOperation(_ sender: Any?) { close() }

    override func close() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        let wasVisible = isVisible
        super.close()
        if wasVisible { onClose() }
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// Reports content size changes after the current layout pass, so resizing the panel never
/// happens inside one.
private final class MenuHostingView: NSHostingView<AnyView> {
    var onSizeChange: () -> Void = {}

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        DispatchQueue.main.async { [weak self] in self?.onSizeChange() }
    }
}
