import SwiftUI

/// Settings → Appearance (§15): the Settings window, the menu bar icon, the pill and the Dock.
struct AppearancePane: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var prefs = app.prefs
        Form {
            Section {
                Picker("Style", selection: $prefs.windowStyle) {
                    ForEach(WindowStyle.allCases, id: \.self) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            } header: {
                PaneSectionHeader(pane: .appearance, title: "Window")
            } footer: {
                Text("Automatic follows your Mac’s light or dark mode.")
            }

            Section {
                Toggle(isOn: $prefs.menuBarTintWhileDictating) {
                    RowLabel(title: "Color the menu bar icon while dictating", description: "The icon is animated either way.")
                }
            } header: {
                Text("Menu bar")
            }

            Section {
                Toggle(isOn: $prefs.showPill) {
                    RowLabel(title: "Show the pill while dictating", description: "Turn off if the menu bar icon is enough.")
                }
                Group {
                    Picker("Background", selection: $prefs.pillBackground) {
                        ForEach(PillBackground.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.menu)
                    LabeledContent("Color") {
                        PillColorPicker(selection: $prefs.pillColor, customHex: $prefs.pillCustomColor)
                    }
                    LabeledContent {
                        Button("Reset position") { app.pill?.resetPosition() }
                    } label: {
                        RowLabel(title: "Position", description: "Drag the pill anywhere. It snaps to screen edges.")
                    }
                }
                .disabled(!prefs.showPill)
                Toggle(isOn: $prefs.hideFromCapture) {
                    RowLabel(title: "Hide from screen sharing and screenshots",
                             description: "You still see the pill; others and recordings don’t.")
                }
            } header: {
                HStack {
                    Text("Pill")
                    Spacer()
                    StaticPill(mode: .listening, color: prefs.pillColor, customColor: Color(hex: prefs.pillCustomColor) ?? .vyAccent, surface: prefs.pillBackground, level: Self.previewLevel, showsShadow: false)
                        .accessibilityLabel("Pill preview")
                }
            } footer: {
                Text("The pill appears only while you dictate.")
            }

            Section {
                Toggle("Show vypo in the Dock", isOn: $prefs.showInDock)
            } header: {
                Text("Dock")
            } footer: {
                Text("Clicking the icon opens Settings.")
            }
        }
        .formStyle(.grouped)
    }

    /// A made-up voice level for the pill preview.
    private static let previewLevel: () -> Float = {
        let t = Date().timeIntervalSinceReferenceDate
        return Float(0.5 + 0.3 * sin(t * 2.1) * sin(t * 1.3 + 1))
    }
}
