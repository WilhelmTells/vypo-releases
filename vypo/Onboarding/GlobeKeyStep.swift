import SwiftUI

/// Step 3: set “Press Globe key to” to “Do Nothing”, or use Right Option.
struct GlobeKeyStep: View {
    @Environment(AppState.self) private var app
    let model: OnboardingModel

    var body: some View {
        let usage = app.permissions.globeKeyUsage
        let done = usage == 0 || model.usedRightOption
        StepHeader(title: "Free up the Globe key",
                   text: "macOS uses the fn/Globe key for its own features. Set it to “Do Nothing” so vypo can use it.")
        OnboardingGroup {
            OnboardingRow(symbol: "globe", title: "Press Globe key to", description: "\(Permissions.globeKeyDescription(usage))") {
                if done {
                    Badge(text: "Done", tone: .success, symbol: "checkmark")
                } else {
                    Button("Open Keyboard Settings…") { Permissions.openKeyboardSettings() }
                }
            }
        }
        Button("Use Right Option instead") {
            app.prefs.dictationKey = .rightOption
            model.usedRightOption = true
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.vyAccent)
        .padding(.horizontal, Space.s3)
    }
}
