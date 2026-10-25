import KeyboardShortcuts
import SwiftUI

/// Step 5: the dictation key and gestures.
struct DictationKeyStep: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var prefs = app.prefs
        let key = prefs.dictationKey.spoken
        StepHeader(title: "Your dictation key", text: "Hold \(key) and talk. Double-tap \(key) to dictate hands-free.")
        OnboardingGroup {
            OnboardingRow(symbol: "keyboard", title: "Dictation key") {
                KeyCaps(keys: prefs.dictationKey.keyCaps)
                Picker("Dictation key", selection: $prefs.dictationKey) {
                    // A custom shortcut is recorded in Settings; it shows here only once chosen there.
                    ForEach(DictationKey.singleKeys + (prefs.dictationKey == .custom ? [.custom] : [])) { Text($0.name).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }
            OnboardingRow(title: "Hold to talk") {
                Toggle("Hold to talk", isOn: $prefs.holdToTalk)
                    .toggleStyle(.switch).labelsHidden()
                    .disabled(!prefs.doubleTapHandsFree)
            }
            OnboardingRow(title: "Double-tap for hands-free") {
                Toggle("Double-tap for hands-free", isOn: $prefs.doubleTapHandsFree)
                    .toggleStyle(.switch).labelsHidden()
                    .disabled(!prefs.holdToTalk)
            }
        }
    }
}
