import SwiftUI

/// Onboarding state shared by the steps.
@MainActor
@Observable
final class OnboardingModel {
    static let stepCount = 6

    var step: Int
    /// Step 3 is done once the Globe key is free or the user chose Right Option.
    var usedRightOption = false
    /// Step 4 choices.

    init(step: Int) {
        self.step = min(max(step, 0), Self.stepCount - 1)
    }
}

/// The first-run window: six steps, dots and Back/Continue (§16).
struct OnboardingView: View {
    @Environment(AppState.self) private var app
    @State var model: OnboardingModel
    var finish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Space.s4) {
                switch model.step {
                case 0: WelcomeStep()
                case 1: PermissionsStep()
                case 2: GlobeKeyStep(model: model)
                case 3: LanguagesStep(model: model)
                case 4: DictationKeyStep()
                default: TryItStep()
                }
            }
            .padding(.top, 36)
            .padding(.horizontal, Space.s6)
            .frame(maxWidth: .infinity, alignment: .topLeading)

            Spacer(minLength: Space.s4)

            HStack {
                StepDots(current: model.step, count: OnboardingModel.stepCount)
                Spacer()
                if model.step > 0 {
                    Button("Back") { model.step -= 1 }
                        .controlSize(.large)
                }
                Button(primaryTitle) { next() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canContinue)
            }
            .padding(.horizontal, Space.s6)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s5)
        }
        .frame(width: 680)
        .frame(minHeight: 460)
        .background(Color.vyBgWindow)
        .animation(.easeInOut(duration: 0.2), value: model.step)
    }

    private var primaryTitle: LocalizedStringKey {
        switch model.step {
        case 0: "Get started"
        case OnboardingModel.stepCount - 1: "Done"
        default: "Continue"
        }
    }

    private var canContinue: Bool {
        switch model.step {
        case 1: app.permissions.micGranted && app.permissions.accessibilityTrusted
        case 2: app.permissions.globeKeyFree || model.usedRightOption || app.prefs.dictationKey != .fn
        default: true
        }
    }

    private func next() {
        switch model.step {
        case 3:
            LanguagesStep.startDownloads(app: app)
            model.step += 1
        case OnboardingModel.stepCount - 1:
            finish()
        default:
            model.step += 1
        }
    }
}

/// 6 px dots; the current step is an 18×6 capsule.
struct StepDots: View {
    var current: Int
    var count: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == current ? Color.vyLabel : Color.vyFillTrack)
                    .frame(width: i == current ? 18 : 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}

/// Title and body of a step.
struct StepHeader: View {
    var title: LocalizedStringKey
    var text: LocalizedStringKey
    var centered = false

    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: Space.s2) {
            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(Color.vyLabel)
                .accessibilityAddTraits(.isHeader)
            Text(text)
                .font(.body)
                .foregroundStyle(Color.vyLabelSecondary)
                .multilineTextAlignment(centered ? .center : .leading)
                .frame(maxWidth: centered ? 400 : .infinity, alignment: centered ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
    }
}

/// A rounded group of rows on bg-group, like a grouped Form section.
struct OnboardingGroup<Content: View>: View {
    var title: LocalizedStringKey?
    var footer: LocalizedStringKey?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title).font(.headline).foregroundStyle(Color.vyLabel).padding(.horizontal, Space.s3)
            }
            VStack(spacing: 0) {
                Group(subviews: content) { subviews in
                    ForEach(Array(subviews.enumerated()), id: \.offset) { i, v in
                        if i > 0 { Divider().overlay(Color.vySeparator).padding(.horizontal, Space.s3) }
                        v.padding(.horizontal, Space.s3).padding(.vertical, Space.s2).frame(minHeight: 40)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: Radius.md).fill(Color.vyBgGroup))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Color.vySeparator, lineWidth: 0.5))
            if let footer {
                Text(footer).font(.callout).foregroundStyle(Color.vyLabelSecondary).padding(.horizontal, Space.s3)
            }
        }
    }
}

/// Icon tile, label and description on the left; trailing content on the right.
struct OnboardingRow<Trailing: View>: View {
    var symbol: String?
    var title: LocalizedStringKey
    var description: LocalizedStringKey?
    /// A model's credit line under the description.
    var attribution = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Space.s3) {
            if let symbol { IconTile(symbol: symbol) }
            VStack(alignment: .leading, spacing: 2) {
                RowLabel(title: title, description: description)
                if attribution { ModelAttribution() }
            }
            Spacer(minLength: Space.s2)
            trailing
        }
    }
}
