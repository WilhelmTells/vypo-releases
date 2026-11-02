import AppKit
import SwiftUI
import WidgetKit
import XCTest
@testable import vypo

/// Renders the widget, opt-in like the other snapshots:
///
///     TEST_RUNNER_VYPO_WIDGET_DIR="$PWD/build.noindex/widget" scripts/test.sh -only-testing:vypoTests/WidgetRenderTests
///
/// Every size x look x mode x language in the design's states, as `<state>-<size>-<look>-<mode>-<lang>.png` at 2x.
/// Only light and dark are what macOS draws. The rest are stand-ins on a flat desktop: dimmed is the widget without its
/// background, desaturated (what macOS does with a window in front); clear and tinted are the accented face on a
/// darkened pane; macOS adds the real glass and tint.
@MainActor
final class WidgetRenderTests: XCTestCase {
    private enum Mode: String, CaseIterable {
        case light, dark, dimmedLight, dimmedDark, clearLight, clearDark, tintedLight, tintedDark

        var isDark: Bool { self == .dark || self == .dimmedDark || self == .clearDark || self == .tintedDark }
        var isAccented: Bool { [.clearLight, .clearDark, .tintedLight, .tintedDark].contains(self) }
        var isDimmed: Bool { self == .dimmedLight || self == .dimmedDark }
        var desktop: Color { isDark ? Color(red: 0.13, green: 0.2, blue: 0.33) : Color(red: 0.82, green: 0.85, blue: 0.9) }
    }

    private static let sizes: [(String, WidgetFamily, CGSize)] = [("small", .systemSmall, CGSize(width: 170, height: 170)),
                                                                  ("medium", .systemMedium, CGSize(width: 364, height: 170)),
                                                                  ("large", .systemLarge, CGSize(width: 364, height: 382))]
    private static let margins = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)

    @ViewBuilder private static func widget(_ snapshot: WidgetSnapshot, _ family: WidgetFamily, _ size: CGSize, _ look: WidgetLook, _ mode: Mode) -> some View {
        ZStack {
            if mode.isAccented || mode.isDimmed {
                mode.desktop
                if mode.isAccented { Color.black.opacity(mode.isDark ? 0.15 : 0.3) }
            } else {
                WidgetBackground(snapshot: snapshot, family: family, look: look, forcedMargins: margins)
            }
            // Its own group: the real widget has no desktop to blend with, it is drawn on nothing.
            WidgetFace(snapshot: snapshot, family: family, look: look, forcedAccented: mode.isAccented)
                .padding(16)
                .saturation(mode.isDimmed ? 0 : 1)
                .colorMultiply(mode == .tintedLight || mode == .tintedDark ? Color(red: 0.72, green: 0.84, blue: 1) : .white)
                .modifier(Grouped(active: mode.isAccented || mode.isDimmed))
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        // Accented content is white on any desktop; only the dark scheme makes `.primary` say so here.
        .environment(\.colorScheme, mode.isDark || mode.isAccented ? .dark : .light)
    }

    private struct Grouped: ViewModifier {
        let active: Bool
        func body(content: Content) -> some View {
            if active { content.compositingGroup() } else { content }
        }
    }

    private func pixels(_ view: some View) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.isOpaque = false
        return NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
    }

    /// Largest difference from `a` to `b` in one channel, in a rect in points.
    private func difference(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, in rect: CGRect) throws -> CGFloat {
        var most: CGFloat = 0
        for x in Int(rect.minX * 2)..<Int(rect.maxX * 2) {
            for y in Int(rect.minY * 2)..<Int(rect.maxY * 2) {
                let p = try XCTUnwrap(a.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                let q = try XCTUnwrap(b.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                most = max(most, abs(p.redComponent - q.redComponent), abs(p.greenComponent - q.greenComponent), abs(p.blueComponent - q.blueComponent))
            }
        }
        return most
    }

    /// On paper the cut-outs on the face change nothing, or the widget would wear a white or black boy; without the
    /// paper they are all that is left of boy and stamp.
    func testCutOutsShowOnlyWithoutThePaper() throws {
        WidgetAssets.bundle = Bundle(for: Marker.self)
        var snapshot = WidgetSnapshot.sample
        snapshot.suggestion = nil
        let size = CGSize(width: 364, height: 382)
        let boy = CGRect(x: 289, y: 16, width: 59, height: 116), stamp = CGRect(x: 16, y: 316, width: 36, height: 36)
        for look in [WidgetLook.woodcut, .plain] {
            for scheme in [ColorScheme.light, .dark] {
                let background = WidgetBackground(snapshot: snapshot, family: .systemLarge, look: look, forcedMargins: Self.margins)
                let face = WidgetFace(snapshot: snapshot, family: .systemLarge, look: look, forcedAccented: false).padding(16)
                let bare = try pixels(background.frame(width: size.width, height: size.height).environment(\.colorScheme, scheme))
                let whole = try pixels(ZStack { background; face }.frame(width: size.width, height: size.height).environment(\.colorScheme, scheme))
                let plainGround = try pixels(Color.gray.frame(width: size.width, height: size.height))
                let alone = try pixels(ZStack { Color.gray; face.compositingGroup() }.frame(width: size.width, height: size.height).environment(\.colorScheme, scheme))
                XCTAssertLessThan(try difference(whole, bare, in: stamp), 0.02, "\(look) \(scheme): the cut-out shows on paper")
                XCTAssertGreaterThan(try difference(alone, plainGround, in: stamp), 0.3, "\(look) \(scheme): no stamp without the paper")
                if look == .woodcut {
                    XCTAssertLessThan(try difference(whole, bare, in: boy), 0.02, "\(look) \(scheme): the cut-out shows on paper")
                    XCTAssertGreaterThan(try difference(alone, plainGround, in: boy), 0.3, "\(look) \(scheme): no boy without the paper")
                }
            }
        }
    }

    func testSwitchPicksTheLook() {
        XCTAssertEqual(WidgetLook(woodcut: true), .woodcut)
        XCTAssertEqual(WidgetLook(woodcut: false), .plain)
    }
    private final class Marker {}

    private static func base(de: Bool) -> WidgetSnapshot {
        var s = WidgetSnapshot.sample
        s.today = Date()
        s.uiLanguage = de ? "de" : "en"
        s.numberLocale = de ? "de_DE" : "en_US"
        s.rankName = de ? "Schreiber" : "Scribe"
        s.nextRankName = de ? "Herold" : "Herald"
        s.suggestion = .init(id: "Kubernetes", term: "Kubernetes")
        s.latest = .init(id: "wordKeeper", name: "Word Keeper", day: Achievements.day(Date().addingTimeInterval(-86_400), calendar: .current))
        return s
    }

    private static func states(de: Bool) -> [(String, WidgetSnapshot)] {
        let mid = base(de: de)
        var none = mid
        none.suggestion = nil
        var ready = mid
        ready.ready = .init(id: "bookworm", name: "Bookworm")
        var long = mid
        long.suggestion = .init(id: "x", term: "Infrastructure-as-Code-Pipeline-Konfigurationsverwaltung")
        var new = mid
        (new.level, new.words, new.rankStart, new.nextStart, new.progress, new.wordsToday) = (1, 0, 0, 2_500, 0, 0)
        new.rankName = de ? "Laufbursche" : "Errand boy"
        new.nextRankName = de ? "Bote" : "Messenger"
        new.savedText = "0 min"
        new.suggestion = nil
        new.latest = nil
        new.activity = Array(repeating: Array(repeating: 0, count: 7), count: 27)
        var top = mid
        (top.level, top.words, top.rankStart, top.nextStart, top.progress, top.wordsToday) = (10, 1_084_300, 1_000_000, nil, 1, 2_310)
        top.rankName = de ? "Hofdichter" : "Poet Laureate"
        top.nextRankName = nil
        top.savedText = "301 h"
        top.suggestion = nil
        var off = WidgetSnapshot()
        off.collecting = false
        off.uiLanguage = mid.uiLanguage
        return [("mid", mid), ("nosuggestion", none), ("ready", ready), ("long", long), ("new", new), ("top", top), ("off", off)]
    }

    func testRender() throws {
        guard let dir = ProcessInfo.processInfo.environment["VYPO_WIDGET_DIR"] else {
            throw XCTSkip("Set TEST_RUNNER_VYPO_WIDGET_DIR to render the widget.")
        }
        WidgetAssets.bundle = Bundle(for: Marker.self)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for de in [false, true] {
            for (state, snapshot) in Self.states(de: de) {
                for (sizeName, family, size) in Self.sizes {
                    for look in [WidgetLook.woodcut, .plain] {
                        for mode in Mode.allCases {
                            let bitmap = try pixels(Self.widget(snapshot, family, size, look, mode))
                            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                            let name = "\(state)-\(sizeName)-\(look.rawValue)-\(mode.rawValue)-\(de ? "de" : "en").png"
                            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
                        }
                    }
                }
            }
        }
    }
}
