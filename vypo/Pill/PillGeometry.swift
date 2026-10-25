import CoreGraphics

/// Edges the pill is snapped to. Two edges at once mean a corner.
struct SnapEdges: OptionSet, Codable, Hashable, Sendable {
    let rawValue: Int
    static let left = SnapEdges(rawValue: 1 << 0)
    static let right = SnapEdges(rawValue: 1 << 1)
    static let top = SnapEdges(rawValue: 1 << 2)
    static let bottom = SnapEdges(rawValue: 1 << 3)
}

/// Pure geometry for the pill: anchors, growth direction, snapping and clamping (§6.4).
/// All rects are in Cocoa screen coordinates (origin bottom-left) and describe the pill itself,
/// not the panel with its shadow margin.
enum PillGeometry {
    static let inset: CGFloat = 12
    static let snapDistance: CGFloat = 24

    /// The point that stays fixed while the pill changes size.
    static func anchor(of frame: CGRect, edges: SnapEdges) -> CGPoint {
        let x: CGFloat = edges.contains(.left) ? frame.minX : edges.contains(.right) ? frame.maxX : frame.midX
        let y: CGFloat = edges.contains(.bottom) ? frame.minY : edges.contains(.top) ? frame.maxY : frame.midY
        return CGPoint(x: x, y: y)
    }

    /// The frame of a pill of `size` placed at `anchor`, growing away from the snapped edges.
    static func frame(size: CGSize, anchor: CGPoint, edges: SnapEdges) -> CGRect {
        let x: CGFloat = edges.contains(.left) ? anchor.x : edges.contains(.right) ? anchor.x - size.width : anchor.x - size.width / 2
        let y: CGFloat = edges.contains(.bottom) ? anchor.y : edges.contains(.top) ? anchor.y - size.height : anchor.y - size.height / 2
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    /// Keeps the frame inside `visible` with a 12 px inset.
    static func clamp(_ frame: CGRect, in visible: CGRect) -> CGRect {
        let area = visible.insetBy(dx: inset, dy: inset)
        var f = frame
        if f.width > area.width { f.origin.x = area.midX - f.width / 2 } else {
            f.origin.x = min(max(f.minX, area.minX), area.maxX - f.width)
        }
        if f.height > area.height { f.origin.y = area.midY - f.height / 2 } else {
            f.origin.y = min(max(f.minY, area.minY), area.maxY - f.height)
        }
        return f
    }

    /// Snaps a dropped frame: within 24 px of an edge, it moves to 12 px from that edge.
    static func snap(_ frame: CGRect, in visible: CGRect) -> (frame: CGRect, edges: SnapEdges) {
        var f = frame
        var edges: SnapEdges = []
        if f.minX - visible.minX <= snapDistance {
            f.origin.x = visible.minX + inset; edges.insert(.left)
        } else if visible.maxX - f.maxX <= snapDistance {
            f.origin.x = visible.maxX - inset - f.width; edges.insert(.right)
        }
        if f.minY - visible.minY <= snapDistance {
            f.origin.y = visible.minY + inset; edges.insert(.bottom)
        } else if visible.maxY - f.maxY <= snapDistance {
            f.origin.y = visible.maxY - inset - f.height; edges.insert(.top)
        }
        return (clamp(f, in: visible), edges)
    }

    /// Bottom center, 12 px above the bottom of the visible frame.
    static func defaultPlacement(in visible: CGRect) -> (anchor: CGPoint, edges: SnapEdges) {
        (CGPoint(x: visible.midX, y: visible.minY + inset), [.bottom])
    }

    /// Anchor as normalized (0–1) coordinates within `visible`, for storage per screen.
    static func normalize(_ point: CGPoint, in visible: CGRect) -> CGPoint {
        CGPoint(x: (point.x - visible.minX) / max(visible.width, 1), y: (point.y - visible.minY) / max(visible.height, 1))
    }

    static func denormalize(_ point: CGPoint, in visible: CGRect) -> CGPoint {
        CGPoint(x: visible.minX + point.x * visible.width, y: visible.minY + point.y * visible.height)
    }
}
