import AppKit
import SwiftUI

/// Step 2: Microphone and Accessibility, polled every second.
struct PermissionsStep: View {
    @Environment(AppState.self) private var app

    var body: some View {
        StepHeader(title: "Two permissions",
                   text: "vypo needs the microphone to listen and Accessibility to read the dictation key and paste text where your cursor is.")
        OnboardingGroup {
            OnboardingRow(symbol: "mic", title: "Microphone", description: "Only while you dictate.") {
                if app.permissions.micGranted {
                    Badge(text: "Allowed", tone: .success, symbol: "checkmark")
                } else {
                    Button("Allow…") { requestMic() }
                }
            }
            OnboardingRow(symbol: "accessibility", title: "Accessibility", description: "To read the dictation key and paste text.") {
                if app.permissions.accessibilityTrusted {
                    Badge(text: "Allowed", tone: .success, symbol: "checkmark")
                } else {
                    Button("Open System Settings…") { Permissions.requestAccessibility() }
                }
            }
        }
    }

    private func requestMic() {
        if Permissions.micStatus == .notDetermined {
            Task {
                _ = await Permissions.requestMic()
                app.permissions.poll()
            }
        } else {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
        }
    }
}
