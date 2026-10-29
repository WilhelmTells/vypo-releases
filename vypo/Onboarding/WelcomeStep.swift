import SwiftUI

/// Step 1: the small Welcome window (400 x 370). “Download speech model” starts the download and the
/// window grows into the step window (see `OnboardingView`).
struct WelcomeStep: View {
    var download: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            boy
                .frame(width: 220, height: 161)
                .padding(.bottom, 12)
            OBBadge(text: "Early version").padding(.bottom, 10)
            Text("Welcome to vypo")
                .font(OBFont.heroTitle).tracking(-0.3)
                .foregroundStyle(Color.vyLabel)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 16)
            Button("Download speech model", action: download)
                .buttonStyle(.ob(.hero))
                .keyboardShortcut(.defaultAction)
            Text("About 600 MB, once, from Hugging Face, a public library for AI models.")
                .font(OBFont.caption)
                .foregroundStyle(Color.vyLabelSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
                .padding(.top, 10)
        }
        .padding(.top, 28).padding([.horizontal, .bottom], 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The boy on his hill, as a still (there is no idle loop).
    private var boy: some View {
        ZStack(alignment: .topLeading) {
            Image("Onboarding/woodcut-hill")
                .resizable().interpolation(.high)
                .frame(width: 116, height: 60.4)
                .paperShadow()
                .offset(x: 52, y: 100.7)
            Image("Onboarding/welcome-boy")
                .resizable().interpolation(.high)
                .frame(width: 74, height: 146)
                .paperShadow(x: 4, y: 5, opacity: 0.5)
                .offset(x: 73, y: 0)
        }
        .frame(width: 220, height: 161, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The vypo boy sitting on a hill and calling out")
    }
}
