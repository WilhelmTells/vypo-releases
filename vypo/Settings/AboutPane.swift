import AppKit
import SwiftUI

/// Settings → About: who made vypo and which version, updates, help, and what vypo is built on with the
/// license texts (folded), from `THIRD_PARTY_NOTICES.md`.
struct AboutPane: View {
    @Environment(AppState.self) private var app
    private let notices: Notices?
    @State private var showTexts = AboutPane.startWithTextsOpen

    /// For the snapshot tests (and, in debug builds, `-VYPOAboutTextsOpen YES`): the license texts start unfolded.
    nonisolated(unsafe) static var startWithTextsOpen: Bool = {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "VYPOAboutTextsOpen")
        #else
        return false
        #endif
    }()

    init(notices: Notices? = Notices.bundled()) {
        self.notices = notices
    }

    var body: some View {
        ScrollViewReader { proxy in
            form
                .onAppear {
                    // Screenshots with the texts open start at the texts.
                    guard Self.startWithTextsOpen else { return }
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(0.6))
                        proxy.scrollTo("licenseTexts", anchor: .top)
                    }
                }
        }
    }

    private var form: some View {
        Form {
            Section {
                header
            } header: {
                PaneSectionHeader(pane: .about)
            }

            Section {
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { app.updates?.automatic ?? false }, set: { app.updates?.automatic = $0 }))
                LabeledContent {
                    Button("Check Now") { app.updates?.checkNow() }
                        .disabled(!(app.updates?.canCheck ?? false))
                } label: {
                    Text(lastCheckedText).foregroundStyle(Color.vyLabelSecondary)
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("Once a day vypo asks wilhelmtells.com whether there’s a new version. It sends only vypo’s version number; like any web request, it shows your IP address to the server.")
            }

            Section {
                LabeledContent {
                    Button("Send Feedback…") { Feedback.send() }
                } label: {
                    RowLabel(title: "Send feedback", description: "Opens a new mail to Wilhelm Tells with the versions of vypo and macOS, and nothing else.")
                }
                LabeledContent {
                    Button("Copy Diagnostics…") { app.onCopyDiagnostics() }
                } label: {
                    RowLabel(title: "Diagnostics", description: "Copies a report for a bug mail to the clipboard. It contains no dictated text.")
                }
            } header: {
                Text("Help")
            }

            if let notices {
                Section {
                    ForEach(notices.components, id: \.name) { c in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: c.name)
                                Text(verbatim: c.author).font(.callout).foregroundStyle(Color.vyLabelSecondary)
                            }
                            Spacer(minLength: Space.s3)
                            if let url = c.licenseURL {
                                Link(destination: url) { Text(verbatim: c.licenseName) }
                            } else {
                                Text(verbatim: c.licenseName).foregroundStyle(Color.vyLabelSecondary)
                            }
                        }
                    }
                } header: {
                    Text("Acknowledgements")
                }
                Section {
                    DisclosureGroup(isExpanded: $showTexts) {
                        licenseTexts(notices)
                    } label: {
                        Text("License texts")
                    }
                }
                .id("licenseTexts")
            }
        }
        .formStyle(.grouped)
    }

    private var lastCheckedText: String {
        guard let date = app.updates?.lastChecked else { return String(localized: "Not checked yet") }
        let when = date.formatted(.dateTime.day().month().year().hour().minute().locale(Formatting.uiLocale))
        return String(localized: "Last checked: \(when)")
    }

    private var header: some View {
        VStack(spacing: Space.s1) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)
                .accessibilityHidden(true)
            Text(verbatim: "vypo").font(.vyWordmark).foregroundStyle(Color.vyLabel)
            Text("Version \(Updates.versionText)").font(.callout).foregroundStyle(Color.vyLabelSecondary)
            Text("Made by Wilhelm Tells").padding(.top, Space.s2)
            Link(destination: Notices.homepage) { Text(verbatim: "wilhelmtells.com/vypo") }
            Text("Your voice and your text never leave your Mac.")
                .font(.callout).foregroundStyle(Color.vyLabelSecondary)
        }
        .padding(.vertical, Space.s2)
        .frame(maxWidth: .infinity)
    }

    private func licenseTexts(_ notices: Notices) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            ForEach(Array(notices.licenseTexts.enumerated()), id: \.offset) { _, t in
                switch t.kind {
                case .heading:
                    Text(verbatim: t.text).font(.headline).padding(.top, Space.s2)
                case .paragraph:
                    Text(verbatim: t.text).font(.callout).foregroundStyle(Color.vyLabelSecondary)
                case .mono:
                    Text(verbatim: t.text)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(Color.vyLabelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.top, Space.s2)
    }
}
