import AppKit
import ApplicationServices

/// A pill position stored per screen (§6.4).
struct StoredPlacement: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var edges: SnapEdges
}

/// Finds the active screen and remembers the pill's position per screen.
@MainActor
final class PillPositioner {
    private let store: Store
    private var positions: [String: StoredPlacement]
    private static let file = "pillPositions.json"

    init(store: Store = .shared) {
        self.store = store
        positions = store.load([String: StoredPlacement].self, from: Self.file) ?? [:]
    }

    /// The screen of the frontmost app's focused window, else the screen under the mouse.
    func activeScreen() -> NSScreen {
        if let frame = Self.focusedWindowFrame(),
           let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) }) {
            return screen
        }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    func placement(on screen: NSScreen) -> (anchor: CGPoint, edges: SnapEdges) {
        let visible = screen.visibleFrame
        guard let key = Self.key(for: screen), let stored = positions[key] else {
            return PillGeometry.defaultPlacement(in: visible)
        }
        var anchor = PillGeometry.denormalize(CGPoint(x: stored.x, y: stored.y), in: visible)
        // Keep snapped edges exactly 12 px from the edge, even if the visible frame changed.
        let inset = PillGeometry.inset
        if stored.edges.contains(.left) { anchor.x = visible.minX + inset }
        if stored.edges.contains(.right) { anchor.x = visible.maxX - inset }
        if stored.edges.contains(.bottom) { anchor.y = visible.minY + inset }
        if stored.edges.contains(.top) { anchor.y = visible.maxY - inset }
        return (anchor, stored.edges)
    }

    func remember(anchor: CGPoint, edges: SnapEdges, on screen: NSScreen) {
        guard let key = Self.key(for: screen) else { return }
        let n = PillGeometry.normalize(anchor, in: screen.visibleFrame)
        positions[key] = StoredPlacement(x: n.x, y: n.y, edges: edges)
        store.save(positions, to: Self.file)
    }

    /// "Reset position": deletes all stored positions.
    func reset() {
        positions = [:]
        try? FileManager.default.removeItem(at: store.url(Self.file))
    }

    /// Display UUID string of a screen.
    static func key(for screen: NSScreen) -> String? {
        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    /// Frame of the frontmost app's focused window in Cocoa coordinates, via Accessibility.
    static func focusedWindowFrame() -> CGRect? {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let windowRef, CFGetTypeID(windowRef) == AXUIElementGetTypeID() else { return nil }
        let window = windowRef as! AXUIElement
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef else { return nil }
        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        // AX uses top-left origin relative to the primary screen.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: pos.x, y: primaryHeight - pos.y - size.height, width: size.width, height: size.height)
    }
}
