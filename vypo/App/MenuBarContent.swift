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
    /// The glossary helper's state when the menu bar panel opened.
    @State private var helper: GlossaryHelperStatus?

    var body: some View {
        @Bindable var app = app
        @Bindable var prefs = app.prefs
        Menu {
            Button("Collapsed") { app.setPill(.collapsed) }
            Button("Ready") { app.setPill(.ready) }
            Button("Listening") { app.setPill(.listening) }
            Button("Hands-free") { app.setPill(.handsfree) }
            Button("Processing") { app.setPill(.processing) }
            Button("Error") { app.setPill(.error(.noMicrophone)) }
            Button("Add") { MenuDismiss.close(); app.beginAdd(prefill: "TikTok") }
            Button("Added") { app.showNotice(.termAdded("TikTok")) }
            Divider()
            Button("Save last recording to Desktop") { MenuDismiss.close(); app.onSaveLastRecording() }
            Toggle("Keep recordings for benchmark", isOn: $app.keepBenchmarkRecordings)
            Section("Glossary helper") {
                // Off by default: neither downloaded nor loaded. On downloads it if needed, then loads it.
                Toggle("Glossary helper (CTC, slower)", isOn: $prefs.glossaryHelper)
                if let helper { Text("Status: \(helper.description)") }
            }
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
        } label: {
            MenuRowLabel(title: "Debug", chevron: true)
        }
        .task { helper = await app.models?.helperStatus() }
        .menuStyle(.button)
        .buttonStyle(MenuRowButtonStyle())
        .menuIndicator(.hidden)
    }
}
