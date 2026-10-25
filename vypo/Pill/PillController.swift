import AppKit
import Observation
import SwiftUI

/// What the floating panel renders.
@MainActor
@Observable
final class PillViewModel {
    var mode: PillMode = .ready
    var color: PillColor = .white
    var customColor: Color = .vyAccent
    var surface: PillBackground = .dark
    var size = PillMetrics.size(for: .ready)
    /// The pill's rect inside the panel, top-left origin. Animated by SwiftUI.
    var frame: CGRect = .zero
    /// Appear/disappear: the pill scales toward its anchor and fades.
    var scale: CGFloat = 1
    var opacity: Double = 1
    var scaleAnchor: UnitPoint = .center
}

/// Owns the floating pill panel: picks the visible state, animates its size around the anchor,
/// handles drag, snap and the context menu (§6).
///
/// Size changes are animated by SwiftUI inside the panel, not by resizing the window every frame:
/// for the length of an animation the panel covers both the old and the new frame, then it shrinks
/// back to the pill.
@MainActor
final class PillController {
    private let app: AppState
    private let panel = PillPanel()
    private let model = PillViewModel()
    private let positioner: PillPositioner
    private var hosting: PillHostingView<AnyView>!

    private var screen: NSScreen
    private var anchor: CGPoint
    private var edges: SnapEdges
    /// Where the pill is or is animating to, in screen coordinates.
    private var pillFrame: CGRect = .zero
    /// The area the panel covers (without its shadow margin), in screen coordinates.
    private var canvas: CGRect = .zero
    /// Bumped by every animation and immediate placement; a finished animation only cleans up if it's still the latest.
    private var animationID = 0
    private var shownVisible = false

    private var dragStartMouse: CGPoint?
    private var dragStartOrigin: CGPoint = .zero

    init(app: AppState, positioner: PillPositioner) {
        self.app = app
        self.positioner = positioner
        screen = positioner.activeScreen()
        (anchor, edges) = positioner.placement(on: screen)

        let actions = PillActions(
            stop: { [weak app] in app?.pillStopTapped() },
            tap: { [weak self] in self?.tapped() },
            confirmAdd: { [weak app] in app?.confirmAdd() },
            cancelAdd: { [weak app] in app?.cancelAdd() },
            dragChanged: { [weak self] in self?.dragChanged() },
            dragEnded: { [weak self] in self?.dragEnded() }
        )
        let root = PillRoot(model: model, app: app, actions: actions)
        hosting = PillHostingView(rootView: AnyView(root))
        // The controller sizes the panel, so SwiftUI must not. As the window's content view, a hosting view
        // keeps syncing the window's size limits and re-invalidates whenever the window moves; in a window
        // this small, AppKit throws after a few such layout passes (crashes on 2026-10-21). Inside a plain
        // container it leaves the window alone.
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        hosting.contextMenu = { [weak self] in self?.buildContextMenu() }
        let container = NSView()
        hosting.frame = container.bounds
        container.addSubview(hosting)
        panel.contentView = container

        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.app.pillBase == .add else { return }
                self.app.cancelAdd()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reevaluateScreen() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reevaluateScreen(force: true) }
        }

        observe()
    }

    // MARK: State

    private struct Inputs {
        var base: PillMode
        var pillVisible: Bool
        var showPill: Bool
        var hideFromCapture: Bool
        var color: PillColor
        var customColor: String
        var surface: PillBackground
    }

    private var shownMode: PillMode?
    private var shownSize: CGSize = .zero

    private func observe() {
        let inputs = withObservationTracking {
            readInputs()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        apply(inputs)
    }

    private func readInputs() -> Inputs {
        let prefs = app.prefs
        var base = app.pillBase
        if base == .ready, let e = app.persistentError { base = .error(e) }
        return Inputs(base: base, pillVisible: app.pillVisible, showPill: prefs.showPill, hideFromCapture: prefs.hideFromCapture,
                      color: prefs.pillColor, customColor: prefs.pillCustomColor, surface: prefs.pillBackground)
    }

    private func apply(_ inputs: Inputs) {
        let mode = inputs.base
        let size = PillMetrics.size(for: mode)
        // No idle pill: it shows only while something happens.
        let visible = inputs.pillVisible && PillVisibility.isVisible(mode, showPill: inputs.showPill)

        let modeChanged = shownMode != mode
        shownMode = mode
        let sizeChanged = shownSize != size
        shownSize = size
        panel.sharingType = inputs.hideFromCapture ? .none : .readOnly
        model.color = inputs.color
        model.customColor = Color(hex: inputs.customColor) ?? .vyAccent
        model.surface = inputs.surface

        let target = targetFrame(for: size)
        if visible && !shownVisible {
            show(mode: mode, size: size, at: target)
        } else if !visible && shownVisible {
            hide()
        } else if visible && (sizeChanged || modeChanged) {
            animate(to: target) {
                self.model.mode = mode
                self.model.size = size
            }
        } else {
            model.mode = mode
            model.size = size
            if sizeChanged { setPillFrame(target) }
        }

        if mode == .add {
            if modeChanged {
                panel.allowsKey = true
                panel.makeKeyAndOrderFront(nil)
                app.pillAdd.focusRequest += 1
            }
        } else if panel.allowsKey {
            panel.allowsKey = false
            if panel.isKeyWindow { panel.resignKey() }
        }
    }

    // MARK: Geometry

    private func targetFrame(for size: CGSize) -> CGRect {
        let f = PillGeometry.frame(size: size, anchor: anchor, edges: edges)
        return PillGeometry.clamp(f, in: screen.visibleFrame)
    }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private var spring: Animation {
        .spring(Motion.pillSpring(reduceMotion: reduceMotion))
    }

    /// Places the pill at `frame` immediately, cancelling any animation.
    private func setPillFrame(_ frame: CGRect) {
        animationID += 1
        pillFrame = frame
        setCanvas(frame)
        // A hide that was cut short never reached its orderOut.
        if !shownVisible && panel.isVisible { panel.orderOut(nil) }
    }

    /// Moves the panel to cover `rect` and repositions the pill inside it, without animating, so the
    /// pill stays put on screen.
    private func setCanvas(_ rect: CGRect) {
        canvas = rect
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { model.frame = local(pillFrame) }
        panel.setFrame(rect.insetBy(dx: -PillMetrics.margin, dy: -PillMetrics.margin), display: true)
    }

    /// The pill's rect in the panel's SwiftUI coordinates (top-left origin).
    private func local(_ frame: CGRect) -> CGRect {
        CGRect(x: frame.minX - canvas.minX + PillMetrics.margin, y: canvas.maxY - frame.maxY + PillMetrics.margin,
               width: frame.width, height: frame.height)
    }

    /// Springs the pill to `target`; `changes` (mode, size, fade) animate along.
    private func animate(to target: CGRect, changes: @escaping () -> Void = {}, completion: @escaping () -> Void = {}) {
        // Grow the panel first so the old and the new frame both fit; nothing moves on screen.
        let cover = canvas.union(target)
        if cover != canvas { setCanvas(cover) }
        pillFrame = target
        animationID += 1
        let id = animationID
        withAnimation(spring, completionCriteria: .removed) {
            changes()
            model.frame = local(target)
        } completion: { [weak self] in
            guard let self, self.animationID == id else { return }
            completion()
            // Back to a panel the size of the pill, so it doesn't block clicks around it.
            self.setCanvas(self.pillFrame)
        }
    }

    /// Scales the pill up slightly from its anchor edge and fades it in.
    private func show(mode: PillMode, size: CGSize, at target: CGRect) {
        shownVisible = true
        model.mode = mode
        model.size = size
        model.scaleAnchor = scaleAnchor
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            model.scale = 0.85
            model.opacity = 0
        }
        setPillFrame(target)
        panel.orderFrontRegardless()
        animate(to: target) {
            self.model.scale = 1
            self.model.opacity = 1
        }
    }

    /// The reverse of `show`; the panel goes away once the pill has faded.
    private func hide() {
        shownVisible = false
        model.scaleAnchor = scaleAnchor
        animate(to: pillFrame) {
            self.model.scale = 0.85
            self.model.opacity = 0
        } completion: { [weak self] in
            guard let self, !self.shownVisible else { return }
            self.panel.orderOut(nil)
        }
    }

    /// The point of the pill that stays fixed, as a SwiftUI unit point.
    private var scaleAnchor: UnitPoint {
        let x: CGFloat = edges.contains(.left) ? 0 : edges.contains(.right) ? 1 : 0.5
        let y: CGFloat = edges.contains(.top) ? 0 : edges.contains(.bottom) ? 1 : 0.5
        return UnitPoint(x: x, y: y)
    }

    /// Moves the pill to the active screen (on app activation and when recording starts).
    func reevaluateScreen(force: Bool = false) {
        guard dragStartMouse == nil else { return }
        let s = positioner.activeScreen()
        guard force || s != screen else { return }
        screen = s
        (anchor, edges) = positioner.placement(on: s)
        setPillFrame(targetFrame(for: shownSize))
    }

    /// "Reset position".
    func resetPosition() {
        positioner.reset()
        reevaluateScreen(force: true)
    }

    // MARK: Drag

    private func dragChanged() {
        guard shownMode != .add else { return }
        let mouse = NSEvent.mouseLocation
        if dragStartMouse == nil {
            dragStartMouse = mouse
            setPillFrame(pillFrame)
            dragStartOrigin = pillFrame.origin
        }
        guard let start = dragStartMouse else { return }
        var f = pillFrame
        f.origin = CGPoint(x: dragStartOrigin.x + mouse.x - start.x, y: dragStartOrigin.y + mouse.y - start.y)
        pillFrame = f
        canvas = f
        panel.setFrameOrigin(CGPoint(x: f.minX - PillMetrics.margin, y: f.minY - PillMetrics.margin))
    }

    private func dragEnded() {
        guard dragStartMouse != nil else { return }
        dragStartMouse = nil
        let center = CGPoint(x: pillFrame.midX, y: pillFrame.midY)
        screen = NSScreen.screens.first { $0.frame.contains(center) } ?? screen
        let (snapped, newEdges) = PillGeometry.snap(pillFrame, in: screen.visibleFrame)
        edges = newEdges
        anchor = PillGeometry.anchor(of: snapped, edges: newEdges)
        positioner.remember(anchor: anchor, edges: edges, on: screen)
        animate(to: snapped)
    }

    // MARK: Interaction

    private func tapped() {
        if case .error(let e) = shownMode { app.openErrorTarget(e) }
    }

    private func buildContextMenu() -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem(String(localized: "Settings…")) { [weak app] in app?.openSettings() })
        menu.addItem(ClosureMenuItem(String(localized: "Quit vypo")) { NSApp.terminate(nil) })
        return menu
    }
}

/// The panel's SwiftUI root.
private struct PillRoot: View {
    let model: PillViewModel
    let app: AppState
    let actions: PillActions

    var body: some View {
        PillView(mode: model.mode, color: model.color, customColor: model.customColor, surface: model.surface,
                 level: { [meter = app.levelMeter] in meter.level },
                 size: model.size, addModel: app.pillAdd, actions: actions)
            .frame(width: model.frame.width, height: model.frame.height)
            .scaleEffect(model.scale, anchor: model.scaleAnchor)
            .opacity(model.opacity)
            .position(x: model.frame.midX, y: model.frame.midY)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// An NSMenuItem that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, keyEquivalent: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: keyEquivalent)
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func run() { handler() }
}
