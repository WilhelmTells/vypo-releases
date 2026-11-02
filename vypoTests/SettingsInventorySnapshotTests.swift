import AppKit
import SwiftUI
import XCTest
@testable import vypo

/// Every Settings pane and sheet as a PNG, for the UI inventory.
/// Runs only when `VYPO_SNAPSHOT_DIR` is set. One run renders one language, light and dark:
///
///     TEST_RUNNER_VYPO_SNAPSHOT_DIR="$PWD/build.noindex/ui-inventory" scripts/test.sh \
///       -only-testing:vypoTests/SettingsInventorySnapshotTests
///     … the same with -testLanguage de -testRegion DE
///
/// Sheets are really presented with `.sheet` on a window, so they have the size they have in the app, and
/// `sizes-<lang>.txt` lists it. Panes are grown until nothing scrolls any more.
@MainActor
final class SettingsInventorySnapshotTests: XCTestCase {
    private var dir: URL? {
        ProcessInfo.processInfo.environment["VYPO_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    }

    private var lang: String { Bundle.main.preferredLocalizations.first?.hasPrefix("de") == true ? "de" : "en" }

    private func directory() throws -> URL {
        guard let dir else { throw XCTSkip("No snapshot dir") }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: Sample data

    /// Like `SnapshotRenderTests.sampleApp` (private there), plus the data of the brief: terms in two sets, two own
    /// replacements, two apps. A scratch store and a scratch preferences suite: nothing real is read or written.
    private func sampleApp(_ layout: WordsLayout) -> AppState {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vypo-inventory-\(UUID().uuidString)")
        let prefs = Preferences(defaults: UserDefaults(suiteName: "vypo.inventory.\(UUID().uuidString)")!)
        prefs.defaults.set(layout.rawValue, forKey: DefaultsKey.wordsLayout)
        prefs.languages = [.en, .de]
        let app = AppState(prefs: prefs, store: Store(directory: dir))
        let now = Date()
        app.history.add(HistoryItem(date: now.addingTimeInterval(-86_400 * 1.2), text: "Sounds good, let’s do it that way.", rawText: "", appBundleID: nil, appName: "Slack", language: .en, modelID: "parakeet-ultra"))
        app.history.add(HistoryItem(date: now.addingTimeInterval(-18 * 60), text: "Die Containerisierung mit Kubernetes erlaubt eine flexible Skalierung der Dienste.", rawText: "", appBundleID: nil, appName: "Pages", language: .de, modelID: "parakeet-ultra"))
        app.history.add(HistoryItem(date: now.addingTimeInterval(-120), text: "Hi Lena, I’ll look at the release first thing tomorrow and get back to you right after.", rawText: "", appBundleID: nil, appName: "Mail", language: .en, modelID: "parakeet-ultra"))
        let project = app.glossary.addSet(named: "Project")
        app.glossary.add(term: "TikTok", soundsLike: ["tick tock", "tik tok"])
        app.glossary.add(term: "SwiftUI", soundsLike: ["swift you eye"], scope: .only(.en))
        app.glossary.add(term: "Kubernetes", soundsLike: ["cooper netties"], setID: project.id)
        app.glossary.add(term: "Parakeet", scope: .only(.de), setID: project.id)
        app.glossary.suggest(heard: "jam f", term: "Jamf", scope: .only(.en))
        // Corrected twice in an app: the dot in the sidebar. The Words pane's own shot marks it seen.
        for _ in 0..<2 { app.glossary.suggest(heard: "cooper netties", term: "Kubernetes CLI", scope: .all, source: .app) }
        // Four corrections, each heard differently.
        for heard in ["Zwiebels", "Zwiebelics", "Zwiebeliks", "Zwiebelicks"] {
            app.glossary.suggest(heard: heard, term: "Zwiebelix", scope: .only(.de), source: .app)
        }
        app.replacements.upsert(Replacement(spoken: ["my email", "meine Mail"], output: "name@example.com"))
        app.replacements.upsert(Replacement(spoken: ["Unterstrich", "underscore"], output: "_", inSentence: .promptOnly))
        app.profiles.update(AppProfile(bundleID: "com.apple.Terminal", appName: "Terminal", mode: .prompt, autoEnter: true))
        app.profiles.update(AppProfile(bundleID: "com.apple.TextEdit", appName: "TextEdit", mode: .writing))
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

    // MARK: Drawing

    /// `view` at 2×, on the appearance's window colour, with a 1 px outline.
    private func png(of view: NSView, background: NSColor?) throws -> Data {
        let size = view.bounds.size
        let scale: CGFloat = 2
        let w = Int(size.width * scale), h = Int(size.height * scale)
        func rep() -> NSBitmapImageRep {
            let r = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            r.size = size
            return r
        }
        let content = rep()
        view.cacheDisplay(in: view.bounds, to: content)
        let out = rep()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
        let rect = NSRect(origin: .zero, size: size)
        (NSApp.appearance ?? NSAppearance.currentDrawing()).performAsCurrentDrawingAppearance {
            if let background {
                background.setFill()
                rect.fill()
            }
            content.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            NSColor.systemGray.setStroke()
            let line = NSBezierPath(rect: rect.insetBy(dx: 0.25, dy: 0.25))
            line.lineWidth = 0.5
            line.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        return try XCTUnwrap(out.representation(using: .png, properties: [:]))
    }

    private func write(_ data: Data, _ name: String, dark: Bool, in dir: URL) throws {
        try data.write(to: dir.appendingPathComponent("\(name)-\(lang)-\(dark ? "dark" : "light").png"))
    }

    private func note(_ line: String, in dir: URL) throws {
        let url = dir.appendingPathComponent("sizes-\(lang).txt")
        let old = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try (old + line + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func spin(_ seconds: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

    /// Presents `view` with `.sheet` on a window, as the panes do, and draws the sheet at the size it takes.
    private func sheet<V: View>(_ name: String, @ViewBuilder _ view: @escaping () -> V) throws {
        let dir = try directory()
        defer { NSApp.appearance = nil }
        for dark in [false, true] {
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let parent = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 900, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
            parent.isReleasedWhenClosed = false
            parent.contentView = NSHostingView(rootView: Color.clear.sheet(isPresented: .constant(true)) { view() })
            parent.orderFrontRegardless()
            let deadline = Date().addingTimeInterval(4)
            while parent.attachedSheet == nil, Date() < deadline { spin(0.05) }
            let attached = try XCTUnwrap(parent.attachedSheet, "\(name): no sheet appeared")
            spin(0.6)
            let content = try XCTUnwrap(attached.contentView)
            content.layoutSubtreeIfNeeded()
            try write(try png(of: content, background: .windowBackgroundColor), name, dark: dark, in: dir)
            if !dark { try note("\(name) \(Int(content.bounds.width)) x \(Int(content.bounds.height))", in: dir) }
            parent.contentView = nil
            if parent.attachedSheet != nil { parent.endSheet(attached) }
            spin(0.1)
            parent.close()
        }
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        view.subviews.flatMap { sub in ((sub as? NSScrollView).map { [$0] } ?? []) + scrollViews(in: sub) }
    }

    /// The whole pane in the Settings window: the width of the window, as tall as the longest scrolling content.
    private func pane(_ name: String, _ app: AppState, _ pane: SettingsPane) throws {
        let dir = try directory()
        defer { NSApp.appearance = nil }
        app.settingsPane = pane
        var height: CGFloat = 1100
        for dark in [false, true] {
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let size = CGSize(width: WindowManager.settingsMinSize.width, height: height)
            let host = NSHostingView(rootView: SettingsView().environment(app).frame(width: size.width, height: size.height))
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            spin(0.5)
            host.layoutSubtreeIfNeeded()
            var needed = scrollViews(in: host).compactMap { $0.documentView?.frame.height }.max() ?? 0
            needed = ceil(needed)
            if needed > height {
                // Once more at full height, for this and the other appearance.
                height = needed
                let full = CGSize(width: size.width, height: height)
                host.rootView = SettingsView().environment(app).frame(width: full.width, height: full.height)
                window.setContentSize(full)
                host.frame = NSRect(origin: .zero, size: full)
                host.layoutSubtreeIfNeeded()
                spin(0.5)
                host.layoutSubtreeIfNeeded()
            }
            try write(try png(of: host, background: .windowBackgroundColor), name, dark: dark, in: dir)
            if !dark { try note("\(name) \(Int(host.bounds.width)) x \(Int(host.bounds.height))", in: dir) }
            // Takes the pane away, so the Level row of Recording stops metering.
            window.contentView = nil
            spin(0.1)
            window.close()
        }
    }

    // MARK: Tests

    func test1Panes() throws {
        _ = try directory()
        let app = sampleApp(.spokenCharacters)
        for p in SettingsPane.visible where p != .words {
            try pane("pane-\(p.rawValue)", app, p)
        }
        try pane("pane-words-spokencharacters", app, .words)
        try pane("pane-words-legacy", sampleApp(.legacy), .words)
    }

    func test2GeneralSheets() throws {
        let app = sampleApp(.spokenCharacters)
        try sheet("sheet-languages") { LanguagesSheet().environment(app) }
    }

    func test3GlossarySheets() throws {
        let app = sampleApp(.spokenCharacters)
        let term = try XCTUnwrap(app.glossary.entries.first)
        let project = try XCTUnwrap(app.glossary.sets.first { !$0.isGeneral })
        let general = try XCTUnwrap(app.glossary.sets.first { $0.isGeneral })
        try sheet("sheet-term-new") { TermSheet(mode: .add).environment(app) }
        try sheet("sheet-term-edit") { TermSheet(mode: .edit(term)).environment(app) }
        try sheet("sheet-sets") { SetsSheet().environment(app) }
        try sheet("sheet-set-new") { SetSheet(mode: .new).environment(app) }
        try sheet("sheet-set-edit") { SetSheet(mode: .edit(project)).environment(app) }
        try sheet("sheet-set-edit-general") { SetSheet(mode: .edit(general)).environment(app) }
        let found = [("Kubernetes", 7), ("Containerisierung", 4), ("Skalierung", 3), ("Parakeet", 2), ("FluidAudio", 1)]
            .map { TermExtractor.Found(term: $0.0, count: $0.1) }
        try sheet("sheet-import-terms") {
            ImportTermsSheet(result: .init(fileName: "Projektplan.pdf", found: found)).environment(app)
        }
    }

    func test4ReplacementSheets() throws {
        let app = sampleApp(.spokenCharacters)
        let own = try XCTUnwrap(app.replacements.items.last)
        try sheet("sheet-replacement-new") { ReplacementSheet(replacement: Replacement(spoken: [], output: "")).environment(app) }
        try sheet("sheet-replacement-edit") { ReplacementSheet(replacement: own).environment(app) }
        let legacy = sampleApp(.legacy)
        try sheet("sheet-replacement-new-legacy") { ReplacementSheet(replacement: Replacement(spoken: [], output: "")).environment(legacy) }
        try sheet("sheet-move-to-spoken-characters") { MoveToSpokenCharactersSheet().environment(legacy) }
    }

    func test5SpokenCharacterSheets() throws {
        let app = sampleApp(.spokenCharacters)
        let comma = try XCTUnwrap(app.spokenCharacters?.items.first { $0.output == "," })
        try sheet("sheet-spoken-characters") { SpokenCharactersSheet().environment(app) }
        try sheet("sheet-spoken-character-new") {
            SpokenCharacterSheet(character: SpokenCharacter(spoken: [], output: "", alsoInSentence: true)).environment(app)
        }
        try sheet("sheet-spoken-character-edit") { SpokenCharacterSheet(character: comma).environment(app) }
    }

    func test6WordListSheets() throws {
        let app = sampleApp(.spokenCharacters)
        try sheet("sheet-spellings") { SpellingsSheet().environment(app) }
        try sheet("sheet-filler-words") { FillerWordsSheet().environment(app) }
        let one = sampleApp(.spokenCharacters)
        one.prefs.languages = [.fr]
        try sheet("sheet-filler-words-one-language") { FillerWordsSheet().environment(one) }
        let three = sampleApp(.spokenCharacters)
        three.prefs.languages = [.en, .de, .fr]
        try sheet("sheet-filler-words-three-languages") { FillerWordsSheet(language: .fr).environment(three) }
        let empty = sampleApp(.spokenCharacters)
        empty.prefs.languages = [.en, .de, .hr]
        try sheet("sheet-filler-words-empty-list") { FillerWordsSheet(language: .hr).environment(empty) }
    }

    /// The one popover of Settings: drawn inside the achievements card, not an NSPopover.
    func test7AchievementPopover() throws {
        let dir = try directory()
        defer { NSApp.appearance = nil }
        typealias T = AchievementsCardTests
        let content = AchievementCardContent(AchievementID.allCases.map {
            $0 == .timeBack ? T.status(.timeBack, level: 2, stamped: 2, on: "2026-10-14", value: 671) : T.status($0, level: 1, stamped: 1)
        })
        for dark in [false, true] {
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let size = CGSize(width: 720, height: 420)
            let host = NSHostingView(rootView: AchievementsCardLayout(content: content, popover: .timeBack)
                .padding(.horizontal, 30).padding(.top, 24)
                .frame(width: size.width, height: size.height, alignment: .top))
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            host.frame = NSRect(origin: .zero, size: size)
            spin(0.4)
            try write(try png(of: host, background: .windowBackgroundColor), "popover-achievement", dark: dark, in: dir)
            window.contentView = nil
            window.close()
        }
    }
}
