import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings → Apps (§23.5).
struct AppsPane: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var prefs = app.prefs
        Form {
            Section {
                if app.profiles.profiles.isEmpty {
                    Text("No apps yet. vypo works the same everywhere until you add one.")
                        .foregroundStyle(Color.vyLabelSecondary)
                }
                ForEach(app.profiles.sorted) { profile in
                    row(profile)
                }
                Button("Add app…") { addApp() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.vyAccent)
            } header: {
                PaneSectionHeader(pane: .apps, title: "Apps")
            }

            Section {
                ForEach(AppMode.allCases, id: \.self) { mode in
                    HStack(alignment: .top, spacing: Space.s3) {
                        IconTile(symbol: mode.symbol)
                        RowLabel(title: "\(mode.title)", description: "\(mode.explanation(app.wordsLayout))")
                    }
                }
            } header: {
                Text("Modes")
            }

            Section {
                // A new installation sets every spoken character in Words → Spoken characters, with its modes.
                if app.wordsLayout == .legacy {
                    Toggle(isOn: $prefs.spokenPunctuation) {
                        RowLabel(title: "Spoken punctuation", description: "English and German only.")
                    }
                }
                Toggle("Typographic quotes", isOn: $prefs.typographicQuotes)
            } header: {
                Text("In Writing apps")
            } footer: {
                if app.wordsLayout == .legacy {
                    Text("Say “comma” or “Komma” and get “,”; quotes become “curly”.")
                } else {
                    Text("Quotes become “curly”, spoken ones too. Which words become characters is set in Words → Spoken characters.")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ profile: AppProfile) -> some View {
        HStack(spacing: Space.s3) {
            Image(nsImage: AppProfileStore.icon(for: profile.bundleID))
                .resizable()
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
            Text(profile.appName)
            Spacer()
            Picker(profile.appName, selection: Binding(get: { profile.mode }, set: { mode in
                var p = profile
                p.mode = mode
                app.profiles.update(p)
            })) {
                ForEach(AppMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            if profile.mode == .prompt {
                HStack(spacing: 6) {
                    Text("Send automatically").font(.callout).foregroundStyle(Color.vyLabelSecondary)
                    Toggle("Send automatically", isOn: Binding(get: { profile.autoEnter }, set: { on in
                        var p = profile
                        p.autoEnter = on
                        app.profiles.update(p)
                    }))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                }
                .help("Presses Enter after pasting.")
                .fixedSize()
            }
            Button("Remove") { app.profiles.remove(profile.bundleID) }
                .buttonStyle(.plain)
                .fixedSize()
                .foregroundStyle(Color.vyAccent)
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        app.profiles.add(appAt: url)
    }
}
