import KeyboardShortcuts
import SwiftUI

/// The panel under the menu bar mark, on left and right click (§14): dictation on/off,
/// microphone, copy last, Settings, Quit. Only what dictating needs: models, history, glossary, updates,
/// help and About live in Settings.
struct MenuBarContent: View {
    @Environment(AppState.self) private var app
    @State private var showDebug = false
    @State private var devices: [AudioInputDevice] = []

    var body: some View {
        @Bindable var prefs = app.prefs
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Dictation").fontWeight(.semibold)
                Spacer()
                Toggle("Dictation", isOn: $prefs.dictationEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
            .padding(.horizontal, 9)
            .frame(height: 30)

            microphoneRow
            MenuSeparator()
            // Stops hands-free from here too; with the pill turned off there's no stop button.
            if app.pillBase == .handsfree {
                MenuRow(title: "Stop dictation", shortcut: nil) { app.pillStopTapped() }
                MenuSeparator()
            }
            MenuRow(title: "Copy last dictation", shortcut: shortcutText(.copyLastDictation)) {
                app.onCopyLast()
            }
            MenuSeparator()
            MenuRow(title: "Settings…", shortcut: "⌘,") { app.openSettings() }
                .keyboardShortcut(",", modifiers: .command)
            MenuRow(title: "Quit vypo", shortcut: "⌘Q") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
            if showDebug {
                MenuSeparator()
                DebugMenu()
            }
        }
        .padding(5)
        .frame(width: 250)
        .onAppear {
            showDebug = NSEvent.modifierFlags.contains(.option)
            devices = AudioDevices.inputDevices()
        }
    }

    @ViewBuilder private var microphoneRow: some View {
        @Bindable var prefs = app.prefs
        let name = prefs.inputDeviceUID.flatMap { uid in devices.first { $0.uid == uid }?.name } ?? String(localized: "System default")
        Menu {
            Picker("Microphone", selection: $prefs.inputDeviceUID) {
                Text("System default").tag(String?.none)
                ForEach(devices) { Text($0.name).tag(String?.some($0.uid)) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            MenuRowLabel(title: "Microphone", detail: name, chevron: true)
        }
        .menuStyle(.button)
        .buttonStyle(MenuRowButtonStyle())
        .menuIndicator(.hidden)
    }

    private func shortcutText(_ name: KeyboardShortcuts.Name) -> String? {
        KeyboardShortcuts.getShortcut(for: name)?.description
    }
}

/// A menu item: title, shortcut or chevron, hover highlight.
struct MenuRow: View {
    var title: LocalizedStringKey
    var shortcut: String?
    var disabled = false
    var action: () -> Void

    var body: some View {
        Button {
            MenuDismiss.close()
            action()
        } label: {
            MenuRowLabel(title: title, shortcut: shortcut)
        }
        .buttonStyle(MenuRowButtonStyle())
        .disabled(disabled)
    }
}

struct MenuRowLabel: View {
    var title: LocalizedStringKey
    var shortcut: String?
    /// Secondary text before the chevron, e.g. the selected microphone.
    var detail: String?
    var chevron = false

    var body: some View {
        HStack(spacing: 4) {
            Text(title).lineLimit(1)
            Spacer(minLength: 8)
            if let detail {
                Text(detail).lineLimit(1).truncationMode(.middle).foregroundStyle(Color.vyLabelSecondary)
            }
            if let shortcut {
                Text(shortcut).font(.system(size: 12)).foregroundStyle(Color.vyLabelSecondary)
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.vyLabelSecondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .contentShape(Rectangle())
    }
}

struct MenuRowButtonStyle: ButtonStyle {
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(enabled ? Color.vyLabel : Color.vyLabelTertiary)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(hovering && enabled ? Color.vyBgHover : .clear)
            )
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: Motion.fast), value: hovering)
    }
}

/// One device pixel high: a 0.5 pt line vanishes on a 1× display when it falls between pixels.
struct MenuSeparator: View {
    @Environment(\.displayScale) private var scale

    var body: some View {
        Rectangle().fill(Color.vySeparator).frame(height: 1 / scale).padding(.vertical, 5).padding(.horizontal, 9)
    }
}

/// Debug submenu, shown when the menu is opened with ⌥ held (M1).
struct DebugMenu: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        Menu {
            Button("Collapsed") { app.setPill(.collapsed) }
            Button("Ready") { app.setPill(.ready) }
            Button("Listening") { app.setPill(.listening) }
            Button("Hands-free") { app.setPill(.handsfree) }
            Button("Processing") { app.setPill(.processing) }
            Button("Error") { app.setPill(.error(.noMicrophone)) }
            #if DEBUG
            Button("Add") { MenuDismiss.close(); app.beginAdd(prefill: "TikTok") }
            Button("Added") { app.showNotice(.termAdded("TikTok")) }
            // The only two places that write audio to disk. Not in a Release build: vypo never stores audio.
            Divider()
            Button("Save last recording to Desktop") { MenuDismiss.close(); app.onSaveLastRecording() }
            Toggle("Keep recordings for benchmark", isOn: $app.keepBenchmarkRecordings)
            Section("Mascot") {
                Button("Play level-up") {
                    MenuDismiss.close()
                    app.levelPreview.playRequested = true
                    app.openSettings(.stats)
                }
                Menu("Show level") {
                    ForEach(Rank.allCases, id: \.self) { rank in
                        Button("Level \(rank.level): \(rank.name)") { app.levelPreview.rank = rank }
                    }
                }
                Menu("Progress") {
                    ForEach([0, 25, 50, 60, 75, 99, 100], id: \.self) { percent in
                        Button("\(percent) %") { app.levelPreview.progress = Double(percent) / 100 }
                    }
                }
                Button("Reset preview") { app.levelPreview.reset() }
            }
            // See, stamp and reach achievements by hand, for trying the card on the Stats pane. Debug builds only.
            Section("Achievements") {
                Menu("Status") {
                    ForEach(app.achievements.all, id: \.id) { a in
                        Button {} label: { Text(verbatim: Self.line(a)) }.disabled(true)
                    }
                    Divider()
                    Text(verbatim: "stamped \(app.achievements.stampedCount)/\(AchievementID.allCases.count), ready \(app.achievements.readyCount), secrets left \(app.achievements.hiddenCuriousLeft)")
                }
                Menu("Stamp") {
                    let ready = app.achievements.all.filter(\.isReady)
                    if ready.isEmpty { Text("Nothing ready") }
                    ForEach(ready, id: \.id) { a in
                        Button { app.achievements.stamp(a.id) } label: { Text(verbatim: "\(a.id.rawValue) \(a.level)/\(a.tiers)") }
                    }
                }
                Menu("Reach next tier") {
                    ForEach(app.achievements.all.filter { $0.level < $0.tiers }, id: \.id) { a in
                        Button { app.achievements.debugReach(a.id) } label: { Text(verbatim: "\(a.id.rawValue) → \(a.level + 1)/\(a.tiers)") }
                    }
                }
                Button("Clear all stamps") { app.achievements.debugClearStamps() }
            }
            #endif
        } label: {
            MenuRowLabel(title: "Debug", chevron: true)
        }
        .menuStyle(.button)
        .buttonStyle(MenuRowButtonStyle())
        .menuIndicator(.hidden)
    }

    #if DEBUG
    /// “tales: ready 2/4 (1 stamped 2026-10-30), 143 of 1000”, for the Status menu.
    private static func line(_ a: AchievementStatus) -> String {
        let state = a.isLocked ? "locked" : a.isReady ? "ready" : "stamped"
        let stamped = a.isStamped ? " (\(a.stampedLevel) stamped \(a.stampedOn ?? ""))" : ""
        let next = a.next.map { ", \(Int(a.value)) of \(Int($0))" } ?? ""
        return "\(a.id.rawValue): \(state) \(a.level)/\(a.tiers)\(stamped)\(next)\(a.isHidden ? " [hidden]" : "")"
    }
    #endif
}
