import SwiftUI

/// Step 1: “Welcome to vypo”.
struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: Space.s4) {
            Image("AppIconImage")
                .resizable()
                .frame(width: 96, height: 96)
                .padding(.top, 18)
                .padding(.bottom, 6)
                .accessibilityLabel("vypo")
            StepHeader(title: "Welcome to vypo",
                       text: "Talk instead of typing, in any app. Transcription runs entirely on your Mac. No cloud, no account.",
                       centered: true)
        }
        .frame(maxWidth: .infinity)
    }
}
