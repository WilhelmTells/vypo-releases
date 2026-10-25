import SwiftUI
import XCTest
@testable import vypo

/// Renders views to PNGs for visual review. Runs only when `VYPO_SNAPSHOT_DIR` is set
/// (pass `TEST_RUNNER_VYPO_SNAPSHOT_DIR=…` to xcodebuild).
@MainActor
final class SnapshotRenderTests: XCTestCase {
    private var dir: URL? {
        ProcessInfo.processInfo.environment["VYPO_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    }

    private func render<V: View>(_ name: String, width: CGFloat, @ViewBuilder _ view: () -> V) throws {
        guard let dir else { throw XCTSkip("No snapshot dir") }
        for scheme in [ColorScheme.light, .dark] {
            let content = view()
                .padding(20)
                .frame(width: width)
                .background(scheme == .dark ? Color(white: 0.12) : Color(white: 0.95))
                .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                XCTFail("render failed"); return
            }
            try png.write(to: dir.appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png"))
        }
    }

    /// Renders AppKit-backed SwiftUI (Forms) through an offscreen window.
    private func renderWindow<V: View>(_ name: String, size: CGSize, @ViewBuilder _ view: () -> V) throws {
        guard let dir else { throw XCTSkip("No snapshot dir") }
        for dark in [false, true] {
            let host = NSHostingView(rootView: view().frame(width: size.width, height: size.height))
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            // Closing would release it a second time under ARC, crashing the test host.
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.contentView = host
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { XCTFail("no rep"); return }
            host.cacheDisplay(in: host.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
            window.close()
        }
    }

    /// An AppState on a scratch store, seeded with sample data.
    private func sampleApp() -> AppState {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vypo-snap-\(UUID().uuidString)")
        let prefs = Preferences(defaults: UserDefaults(suiteName: "vypo.snap.\(UUID().uuidString)")!)
        let app = AppState(prefs: prefs, store: Store(directory: dir))
        let now = Date()
        app.history.add(HistoryItem(date: now.addingTimeInterval(-86_400 * 1.2), text: "Sounds good, let’s do it that way.", rawText: "", appBundleID: nil, appName: "Slack", language: .en, modelID: "parakeet-ultra"))
        app.history.add(HistoryItem(date: now.addingTimeInterval(-18 * 60), text: "Die Containerisierung mit Kubernetes erlaubt eine flexible Skalierung der Dienste.", rawText: "", appBundleID: nil, appName: "Pages", language: .de, modelID: "parakeet-ultra"))
        app.history.add(HistoryItem(date: now.addingTimeInterval(-120), text: "Hi Lena, I’ll look at the release first thing tomorrow and get back to you right after.", rawText: "", appBundleID: nil, appName: "Mail", language: .en, modelID: "parakeet-ultra"))
        app.glossary.add(term: "TikTok", soundsLike: ["tick tock", "tik tok"])
        app.glossary.add(term: "SwiftUI", soundsLike: ["swift you eye"], scope: .only(.en))
        app.glossary.suggest(heard: "jam f", term: "Jamf", scope: .only(.en))
        let apps = ["com.apple.mail", "com.apple.Notes", "com.apple.Safari", "com.apple.TextEdit", "com.apple.mail"]
        for d in 0..<150 where d % 3 != 1 && d % 11 != 5 {
            app.stats.record(words: 40 + d * 37 % 300, seconds: 20 + Double(d * 37 % 300) / 2, language: d % 4 == 0 ? .de : .en,
                             app: apps[d % apps.count], at: now.addingTimeInterval(-Double(d) * 86_400))
        }
        app.level.add(words: 36_800)
        app.level.markSeen()
        app.models = ModelService(manager: ModelManager(store: Store(directory: dir)))
        return app
    }

    /// The mascot in a few poses: rest, legs swung, shouting with eyes shut, the raven, the fanfare, ruffled.
    func testMascotPoses() throws {
        var swung = MascotPose(); swung.legL = 12; swung.legR = -12
        var shout = MascotPose(); shout.mouthOpen = true; shout.cap = -6; shout.eyesClosed = true
        var raven = MascotPose(); raven.ravenHead = -22; raven.ravenPuffed = true
        var blowing = MascotPose(); blowing.blowing = true; blowing.hop = 6
        blowing.ravenLift = CGSize(width: 0, height: -8); blowing.wingUp = true; blowing.wingAngle = -28
        var landed = MascotPose(); landed.ruffled = true
        let poses = [MascotPose.rest, swung, shout, raven, blowing, landed]
        try render("mascot-poses", width: 6 * 110) {
            HStack(spacing: 24) {
                ForEach(Array(poses.enumerated()), id: \.offset) { _, pose in MascotFigure(pose: pose).sticker() }
            }
            .padding(.top, 40)
        }
    }

    /// The level-up at a few moments: sliding, fanfare with stars and the raven up, landed ruffled;
    /// then the Reduce Motion stars.
    func testLevelUpFrames() throws {
        var frames = [0.3, 1.0, 1.3, 1.6, 1.85, 2.3, 3.0].map { LevelUpMotion.frame(at: $0, from: 0.4) }
        frames.append(LevelUpFrame(progress: 0.1, pose: .rest, stars: LevelUpMotion.reducedStars(at: 0)))
        try render("level-up", width: 2 * 580) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(560)), count: 2)) {
                ForEach(Array(frames.enumerated()), id: \.offset) { _, frame in
                    LevelScene(frame: frame).frame(height: LevelSceneGeometry.height)
                }
            }
        }
    }

    /// The scene at the widths and moments of the design stills of the scene, at 2×,
    /// card only: 0 %, 60 % and the level-up (the middle star at its still position).
    func testLevelCardScene() throws {
        guard let dir else { throw XCTSkip("No snapshot dir") }
        let rank = Rank.messenger, span = Rank.page.threshold - rank.threshold
        var levelUp = LevelUpMotion.frame(at: LevelUpMotion.slide + 0.96, from: 0.6)
        levelUp.progress = 1
        for width: CGFloat in [560, 685, 760] {
            for (name, frame) in [("0", LevelUpFrame(progress: 0, pose: .rest)), ("60", LevelUpFrame(progress: 0.6, pose: .rest)),
                                  ("levelup", levelUp)] {
                let words = rank.threshold + Int(Double(span) * frame.progress)
                let card = LevelCardLayout(rank: rank, words: words) { LevelScene(frame: frame) }
                    .frame(width: width, height: LevelSceneGeometry.height)
                let renderer = ImageRenderer(content: card)
                renderer.scale = 2
                guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                    return XCTFail("render failed")
                }
                try png.write(to: dir.appendingPathComponent("scene-\(Int(width))-\(name).png"))
            }
        }
    }

    /// The level card on its own: the first rank empty, a rank under way, the highest.
    func testLevelCard() throws {
        for (name, words) in [("start", 0), ("scribe", 36_800), ("top", 1_020_000)] {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vypo-snap-\(UUID().uuidString)")
            let level = LevelStore(store: Store(directory: dir), seedWords: words)
            try renderWindow("level-\(name)", size: CGSize(width: 640, height: 300)) {
                LevelCard(level: level, preview: LevelPreview()).padding(Space.s5).frame(maxHeight: .infinity, alignment: .top)
                    .background(Color.vyBgContent)
            }
        }
        // Debug → Mascot: Show level 10 over a real Scribe, and 75 % of Messenger.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vypo-snap-\(UUID().uuidString)")
        let level = LevelStore(store: Store(directory: dir), seedWords: 36_800)
        for (name, rank, progress) in [("preview-top", Rank.poetLaureate, nil), ("preview-75", .messenger, 0.75)] as [(String, Rank, Double?)] {
            let preview = LevelPreview()
            preview.rank = rank
            preview.progress = progress
            try renderWindow("level-\(name)", size: CGSize(width: 640, height: 300)) {
                LevelCard(level: level, preview: preview).padding(Space.s5).frame(maxHeight: .infinity, alignment: .top)
                    .background(Color.vyBgContent)
            }
        }
        XCTAssertEqual(level.xpWords, 36_800)
        XCTAssertEqual(level.lastSeenLevel, 4)
    }

    func testSettingsPanes() throws {
        let app = sampleApp()
        for pane in SettingsPane.visible {
            app.settingsPane = pane
            try renderWindow("settings-\(pane.rawValue)", size: WindowManager.settingsMinSize) {
                ZStack {
                    // Stands in for the window's glass: a colourful desktop, softened. Wherever the
                    // colours show, the content is transparent as it should be.
                    LinearGradient(colors: [.blue, .purple, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Rectangle().fill(.regularMaterial)
                    SettingsView().environment(app)
                }
            }
            // The whole pane, to check what lies below the fold.
            try renderWindow("settings-\(pane.rawValue)-full", size: CGSize(width: WindowManager.settingsMinSize.width, height: 1100)) {
                ZStack {
                    // Stands in for the window's glass: a colourful desktop, softened. Wherever the
                    // colours show, the content is transparent as it should be.
                    LinearGradient(colors: [.blue, .purple, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Rectangle().fill(.regularMaterial)
                    SettingsView().environment(app)
                }
            }
        }
    }

    /// The menu bar mark through each animation, 8× on a light and a dark bar: plain ink, then in `accent`.
    func testMenuBarMarkFrames() throws {
        guard let dir else { throw XCTSkip("No snapshot dir") }
        let frames: [MenuBarMarkFrame] = [
            .rest,
            MenuBarMarkFrame(rotation: MenuBarMotion.startRotation(0.11)),
            MenuBarMarkFrame(rotation: MenuBarMotion.startRotation(0.25)),
            MenuBarMarkFrame(bell: MenuBarMotion.bellScale(level: 0)),
            MenuBarMarkFrame(bell: MenuBarMotion.bellScale(level: 1)),
            MenuBarMarkFrame(coaster: 0.15), MenuBarMarkFrame(coaster: 0.4), MenuBarMarkFrame(coaster: 0.7), MenuBarMarkFrame(coaster: 0.9),
            MenuBarMarkFrame(star: 0.2), MenuBarMarkFrame(star: 0.5), MenuBarMarkFrame(star: 0.8),
            MenuBarMarkFrame(shake: MenuBarMotion.shake(1.0 / 12)),
        ]
        let scale: CGFloat = 8, cell = MenuBarMarkRenderer.canvas
        let bars: [(NSColor, [NSColor])] = [
            (NSColor(white: 0.93, alpha: 1), [.black, NSColor(srgbRed: 0xD4 / 255, green: 0x42 / 255, blue: 0x1F / 255, alpha: 1)]),
            (NSColor(white: 0.15, alpha: 1), [.white, NSColor(srgbRed: 0xF2 / 255, green: 0x58 / 255, blue: 0x3A / 255, alpha: 1)]),
        ]
        let width = Int(cell.width * scale) * frames.count, height = Int(cell.height * scale) * 4
        let ctx = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // Top-left origin, like the flipped image the renderer draws into.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: scale, y: -scale)
        var row = 0
        for (bar, inks) in bars {
            for ink in inks {
                for (i, frame) in frames.enumerated() {
                    let origin = CGPoint(x: CGFloat(i) * cell.width, y: CGFloat(row) * cell.height)
                    ctx.setFillColor(bar.cgColor)
                    ctx.fill(CGRect(origin: origin, size: cell))
                    ctx.saveGState()
                    ctx.translateBy(x: origin.x, y: origin.y)
                    ctx.clip(to: CGRect(origin: .zero, size: cell))
                    MenuBarMarkRenderer.draw(frame, in: ctx, color: ink.cgColor)
                    ctx.restoreGState()
                }
                row += 1
            }
        }
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: try XCTUnwrap(ctx.makeImage())).representation(using: .png, properties: [:]))
        try png.write(to: dir.appendingPathComponent("menubar-mark-frames.png"))
    }

    func testOnboarding() throws {
        let app = sampleApp()
        for step in 0..<OnboardingModel.stepCount {
            try renderWindow("onboarding-\(step + 1)", size: CGSize(width: 680, height: 520)) {
                OnboardingView(model: OnboardingModel(step: step), finish: {}).environment(app)
            }
        }
    }

    func testLanguagesSheet() throws {
        let app = sampleApp()
        app.prefs.languages = [.en, .de]
        try renderWindow("languages-sheet", size: CGSize(width: 460, height: 420)) {
            LanguagesSheet().environment(app)
        }
        // Onboarding step 4 with “More languages” open, to check it still fits.
        try renderWindow("onboarding-languages-open", size: CGSize(width: 680, height: 520)) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    LanguagesStep(model: OnboardingModel(step: 3), showMore: true)
                }
                .padding(.top, 36)
                .padding(.horizontal, Space.s6)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                Spacer(minLength: Space.s4)
                // Where Back/Continue sit.
                Rectangle().fill(.red.opacity(0.3)).frame(height: 72)
            }
            .environment(app)
        }
    }

    /// Words → Replacements with the default entries, and the Edit sheet for “Slash” and for a new entry.
    func testReplacementsPaneAndSheet() throws {
        let app = sampleApp()
        let size = WindowManager.settingsMinSize
        try renderWindow("replacements-words-pane", size: CGSize(width: size.width, height: 1700)) {
            WordsPane().environment(app).background(Color.vyBgWindow)
        }
        let slash = app.replacements.items.first { $0.output == "/" }!
        try renderWindow("replacements-edit-sheet", size: CGSize(width: 420, height: 400)) {
            ReplacementSheet(replacement: slash).environment(app)
        }
        try renderWindow("replacements-new-sheet", size: CGSize(width: 420, height: 400)) {
            ReplacementSheet(replacement: Replacement(spoken: [], output: "")).environment(app)
        }
    }

    /// The Stats pane near the owner's state (about 35,000 words, eight apps) and the History cards with the
    /// middle one hovered.
    func testStatsPaneAndHistoryHover() throws {
        let app = sampleApp()
        app.stats.reset()
        let now = Date()
        let apps = ["dev.warp.Warp-Stable", "dev.warp.Warp-Stable", "com.googlecode.iterm2", "com.apple.mail",
                    "com.apple.Notes", "com.apple.Safari", "com.apple.TextEdit", "com.apple.dt.Xcode", "com.apple.Terminal",
                    "dev.warp.Warp-Stable"]
        for d in 0..<120 where d % 4 != 3 {
            app.stats.record(words: 250 + d * 71 % 400, seconds: 100 + Double(d * 37 % 250), language: d % 5 == 0 ? .de : .en,
                             app: apps[d % apps.count], at: now.addingTimeInterval(-Double(d) * 86_400))
        }
        try renderWindow("stats-pane", size: CGSize(width: WindowManager.settingsMinSize.width, height: 1300)) {
            StatsPane().environment(app).background(Color.vyBgWindow)
        }
        let items = [("Sounds good, let’s do it that way.", "Slack"), ("Die Containerisierung mit Kubernetes erlaubt eine flexible Skalierung der Dienste.", "Pages"),
                     ("Hi Lena, I’ll look at the release first thing tomorrow.", "Mail")]
        try renderWindow("history-hover", size: CGSize(width: 560, height: 300)) {
            VStack(spacing: Space.s2) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HistoryRow(item: HistoryItem(date: now.addingTimeInterval(-Double(i) * 300), text: item.0, rawText: "", appBundleID: nil, appName: item.1, language: .en, modelID: "parakeet-ultra"),
                               previewHovered: i == 1, isEditing: false, draft: .constant(""), onEdit: {}, onCancel: {}, onSave: {}, onDelete: {})
                }
            }
            .padding(20)
            .background(Color.vyBgWindow)
        }
    }

    func testMenu() throws {
        let app = sampleApp()
        // 2×, like a Retina menu bar panel; `renderWindow` draws at 1×.
        guard let dir else { throw XCTSkip("No snapshot dir") }
        let size = CGSize(width: 250, height: 170)
        for dark in [false, true] {
            let host = NSHostingView(rootView: MenuBarContent().environment(app).background(Color.vyBgMenu).frame(width: size.width, height: size.height))
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.contentView = host
            host.frame = NSRect(origin: .zero, size: size)
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * 2, pixelsHigh: Int(size.height) * 2,
                                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            rep.size = size
            host.cacheDisplay(in: host.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent("menu-\(dark ? "dark" : "light").png"))
            window.close()
        }
    }

    func testHistoryPane() throws {
        let app = sampleApp()
        try renderWindow("history", size: CGSize(width: 640, height: 580)) {
            // The pane is a scroll view without a background of its own; the window gives it one.
            HistoryPane().environment(app).background(Color.vyBgWindow)
        }
    }

    func testHistorySearchHighlight() throws {
        let item = HistoryItem(date: Date(), text: "Die Containerisierung mit Kubernetes erlaubt eine flexible Skalierung, und Kubernetes bleibt dabei schnell.", rawText: "", appBundleID: nil, appName: "Pages", language: .de, modelID: "parakeet-ultra")
        try renderWindow("history-highlight", size: CGSize(width: 560, height: 120)) {
            HistoryRow(item: item, highlight: "kubernetes", isEditing: false, draft: .constant(""), onEdit: {}, onCancel: {}, onSave: {}, onDelete: {})
                .padding(20)
                .background(Color.vyBgWindow)
        }
    }

    func testRecordingPaneCustomKey() throws {
        let app = sampleApp()
        app.prefs.dictationKey = .custom
        try renderWindow("recording-custom", size: CGSize(width: 640, height: 520)) {
            RecordingPane().environment(app)
        }
    }

    func testHistoryPaneShowMore() throws {
        let app = sampleApp()
        for i in 0..<20 {
            app.history.add(HistoryItem(date: Date().addingTimeInterval(-Double(i + 3) * 3_600), text: "Entry \(i + 1) for the Show more row.", rawText: "", appBundleID: nil, appName: "Notes", language: .en, modelID: "parakeet-ultra"))
        }
        try renderWindow("history-more", size: CGSize(width: 640, height: 1400)) {
            // The pane is a scroll view without a background of its own; the window gives it one.
            HistoryPane().environment(app).background(Color.vyBgWindow)
        }
    }

    func testPillStates() throws {
        let modes: [PillMode] = [
            .listening, .processing, .handsfree,
            .error(.modelMissing), .add, .added(.termAdded("TikTok")), .added(.copied), .added(.onClipboard), .added(.collectingDiagnostics),
        ]
        try render("pill", width: 300) {
            VStack(spacing: 14) {
                ForEach(Array(modes.enumerated()), id: \.offset) { _, m in
                    StaticPill(mode: m, level: { 0.7 })
                }
            }
        }
    }

    /// Each background over a plain window, a busy one and a photo-like gradient, in a real window so glass renders.
    func testPillBackgrounds() throws {
        let backdrops: [AnyView] = [
            AnyView(Color(nsColor: .windowBackgroundColor)),
            AnyView(Text(String(repeating: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ", count: 4))
                .font(.system(size: 13)).foregroundStyle(.primary).padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(nsColor: .textBackgroundColor))),
            AnyView(LinearGradient(colors: [.blue, .purple, .orange], startPoint: .leading, endPoint: .trailing)),
        ]
        try renderWindow("pill-backgrounds", size: CGSize(width: 560, height: 4 * 72)) {
            VStack(spacing: 0) {
                ForEach(PillBackground.allCases, id: \.self) { bg in
                    HStack(spacing: 0) {
                        ForEach(backdrops.indices, id: \.self) { i in
                            ZStack {
                                backdrops[i]
                                StaticPill(mode: .listening, color: i == 2 ? .white : .orange, surface: bg, level: { 0.7 })
                            }
                            .frame(width: 186, height: 72)
                            .clipped()
                        }
                    }
                }
            }
        }
    }
}

/// Shows glass pills on screen for 8 s (glass only renders on screen), at 100,300 (dark) and 100,400 (light) on the main display, for `screencapture -R`. Opt-in: `TEST_RUNNER_VYPO_GLASS_WINDOW=1`.
@MainActor
final class GlassWindowTrialTests: XCTestCase {
    func testShowBackgrounds() throws {
        guard ProcessInfo.processInfo.environment["VYPO_GLASS_WINDOW"] != nil else { throw XCTSkip("opt-in") }
        var windows: [(Bool, NSWindow)] = []
        for dark in [false, true] {
            let view = HStack(spacing: 0) {
                ForEach(0..<3) { i in
                    ZStack {
                        if i == 0 { Color(nsColor: .windowBackgroundColor) }
                        if i == 1 { Text(String(repeating: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ", count: 4)).font(.system(size: 13)).padding(6).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(nsColor: .textBackgroundColor)) }
                        if i == 2 { LinearGradient(colors: [.blue, .purple, .orange], startPoint: .leading, endPoint: .trailing) }
                        StaticPill(mode: .listening, color: i == 2 ? .white : .orange, surface: .glass, level: { 0.7 })
                    }
                    .frame(width: 186, height: 72)
                }
            }
            let window = NSWindow(contentRect: NSRect(x: 100, y: dark ? 300 : 400, width: 558, height: 72), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.level = .statusBar
            window.contentView = NSHostingView(rootView: view)
            window.orderFrontRegardless()
            windows.append((dark, window))
        }
        RunLoop.main.run(until: Date().addingTimeInterval(8))
        for (_, window) in windows { window.close() }
    }
}

/// Settings → About as the window shows it, folded and with the license texts open, in Light and Dark.
@MainActor
final class AboutSnapshotTests: XCTestCase {
    func testAboutPane() throws {
        guard let dir = ProcessInfo.processInfo.environment["VYPO_SNAPSHOT_DIR"].map({ URL(fileURLWithPath: $0) }) else {
            throw XCTSkip("No snapshot dir")
        }
        let store = Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent("vypo-snap-\(UUID().uuidString)"))
        let app = AppState(prefs: Preferences(defaults: UserDefaults(suiteName: "vypo.snap.\(UUID().uuidString)")!), store: store)
        app.settingsPane = .about
        defer { AboutPane.startWithTextsOpen = false }
        for dark in [false, true] {
            for open in [false, true] {
                AboutPane.startWithTextsOpen = open
                let host = NSHostingView(rootView: SettingsView().environment(app).tint(.vyAccent))
                // The texts are below the fold of the real window; this one is tall enough to show the start of them.
                let size = open ? NSSize(width: WindowManager.settingsMinSize.width, height: 2400) : WindowManager.settingsMinSize
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                                      backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.title = "vypo Settings"
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                window.contentView = host
                window.makeKeyAndOrderFront(nil)
                RunLoop.main.run(until: Date().addingTimeInterval(0.8))
                let view = try XCTUnwrap(window.contentView?.superview)
                let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width) * 2,
                                                          pixelsHigh: Int(view.bounds.height) * 2, bitsPerSample: 8, samplesPerPixel: 4,
                                                          hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                          bytesPerRow: 0, bitsPerPixel: 0))
                rep.size = view.bounds.size
                view.cacheDisplay(in: view.bounds, to: rep)
                try rep.representation(using: .png, properties: [:])!
                    .write(to: dir.appendingPathComponent("about-\(dark ? "dark" : "light")-\(open ? "texts" : "top").png"))
                window.orderOut(nil)
            }
        }
    }
}
