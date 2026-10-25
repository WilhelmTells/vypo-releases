import AppKit
import SwiftUI

/// Borderless, non-activating floating panel that hosts the pill (§6.1).
final class PillPanel: NSPanel {
    /// Only the `add` state may take keyboard focus.
    var allowsKey = false

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 80, height: 50),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isFloatingPanel = true
        // Set after isFloatingPanel, which would reset it to .floating.
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}

/// Hosting view that takes the first click and builds the context menu.
final class PillHostingView<Content: View>: NSHostingView<Content> {
    var contextMenu: () -> NSMenu? = { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func menu(for event: NSEvent) -> NSMenu? { contextMenu() }

    override func rightMouseDown(with event: NSEvent) {
        if let menu = contextMenu() {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }
}
