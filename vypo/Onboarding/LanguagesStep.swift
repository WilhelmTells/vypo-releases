import SwiftUI

/// Step 4: the languages you dictate in, and the model that will download.
struct LanguagesStep: View {
    @Environment(AppState.self) private var app
    @Bindable var model: OnboardingModel
    var showMore = false

    var body: some View {
        let info = ModelCatalog.speech.info
        StepHeader(title: "Your languages",
                   text: "vypo recognizes which of your languages you’re speaking.")
        LanguageChecklist(showMore: showMore)
            .padding(.horizontal, Space.s3)
        OnboardingGroup(title: "Will download") {
            OnboardingRow(symbol: "cpu", title: "\(info.name)", description: "\(info.note)", attribution: true) {
                Text(info.approxSizeText)
                    .font(.callout)
                    .foregroundStyle(Color.vyLabelSecondary)
                    .fixedSize()
            }
        }
    }

    /// Starts the download in the background.
    @MainActor
    static func startDownloads(app: AppState) {
        app.models?.download()
    }
}
