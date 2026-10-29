import SwiftUI

/// The first-run window: Welcome, five steps with a path bar, and Done (0.3.0, layout B).
struct OnboardingView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State var model: OnboardingModel
    var finish: () -> Void

    var body: some View {
        ZStack {
            Color.vyBgWindow
            if model.step == 0 {
                WelcomeStep(download: startDownload)
                    .transition(welcomeTransition)
            } else if model.step == OnboardingModel.stepCount - 1 {
                DoneStep(start: finish)
                    .transition(.opacity)
            } else {
                stepsShell
                    .transition(shellTransition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onChange(of: model.step, initial: true) { _, step in
            // Before Try it the dictation key only shows that it was pressed.
            app.dictationBlocked = step != OnboardingStep.tryIt.rawValue
            model.onStepChanged(step)
        }
        .onDisappear { app.dictationBlocked = false }
    }

    /// “Download speech model” starts the download; the window grows into the step window.
    private func startDownload() {
        app.models?.download()
        go(to: 1)
    }

    private func go(to step: Int) {
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .easeInOut(duration: 0.25)) { model.step = step }
    }

    // MARK: Transitions

    /// Welcome scales up to 118 % and fades (0.25 s ease in); with Reduce motion it only fades.
    private var welcomeTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(insertion: .opacity,
                                              removal: AnyTransition.scale(scale: 1.18).combined(with: .opacity).animation(.easeIn(duration: 0.25)))
    }

    /// The path bar and step zoom in from 86 % and fade in (0.32 s ease out, from 0.14 s).
    private var shellTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(insertion: AnyTransition.scale(scale: 0.86).combined(with: .opacity)
                                                .animation(.easeOut(duration: 0.32).delay(0.14)), removal: .opacity)
    }

    // MARK: Steps 2 to 6

    private var stepsShell: some View {
        let step = model.step
        return ZStack(alignment: .top) {
            VStack(spacing: 0) {
                OnboardingPathBar(model: model)
                    .frame(height: 28)
                    .padding(.top, 32)
                Spacer(minLength: 0)
                footer
            }
            content
                .id(step)
                .padding(.top, step == OnboardingStep.tryIt.rawValue ? 92 : 80)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(stepTransition)
        }
    }

    @ViewBuilder private var content: some View {
        switch OnboardingStep(rawValue: model.step) {
        case .permissions: PermissionsStep(asked: model.preview.permissionsAsked, details: model.preview.permissionsDetails)
        case .microphone:
            MicrophoneStep(model: model, previewLine: model.preview.micLine, previewSilent: model.preview.micSilent,
                           previewLevel: model.preview.micLevel)
        case .languages: LanguagesStep(showList: model.preview.languagesListOpen)
        case .key: DictationKeyStep(pressed: model.preview.keyPressed, detected: model.preview.keyDetected)
        case .tryIt:
            TryItStep(model: model, previewOutcome: model.preview.tryOutcome, previewText: model.preview.tryText,
                      previewFocused: model.preview.tryFocused)
        default: EmptyView()
        }
    }

    /// Content cross-fades and slides 12 pt in the direction of travel (only a cross-fade with Reduce motion).
    private var stepTransition: AnyTransition {
        reduceMotion ? .opacity.animation(.easeOut(duration: 0.15))
            : .asymmetric(insertion: .modifier(active: SlideFade(dx: 12 * CGFloat(model.direction), opacity: 0), identity: SlideFade(dx: 0, opacity: 1)),
                          removal: .modifier(active: SlideFade(dx: -12 * CGFloat(model.direction), opacity: 0), identity: SlideFade(dx: 0, opacity: 1)))
    }

    // MARK: Footer

    private var footer: some View {
        let step = model.step
        return ZStack {
            HStack(spacing: 8) {
                if step >= OnboardingStep.microphone.rawValue {
                    Button("Back") { go(to: step - 1) }.buttonStyle(.ob(.bordered))
                }
                Spacer()
                if step == OnboardingStep.microphone.rawValue && model.micShowsSkip && !model.micHeard {
                    Button("Skip") { model.micSkipped = true; go(to: step + 1) }
                        .buttonStyle(.ob(.bordered))
                        .transition(reduceMotion ? .identity : .opacity.animation(.easeOut(duration: 0.3)))
                }
                Button("Continue") { go(to: step + 1) }
                    .buttonStyle(.ob(.primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canContinue)
            }
            if step == OnboardingStep.key.rawValue {
                Text("If macOS Dictation is on, turn it off in Keyboard Settings. Otherwise macOS and vypo listen at the same time.")
                    .font(OBFont.caption).foregroundStyle(Color.vyLabelTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 60)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: model.micShowsSkip)
    }

    private var canContinue: Bool {
        OnboardingRules.canContinue(step: model.step, micGranted: app.permissions.micGranted,
                                    accessibilityTrusted: app.permissions.accessibilityTrusted,
                                    soundHeard: model.micHeard, skipped: model.micSkipped,
                                    languageCount: app.prefs.languages.count, key: app.prefs.dictationKey,
                                    globeKeyUsage: app.permissions.globeKeyUsage)
    }
}

private struct SlideFade: ViewModifier {
    var dx: CGFloat
    var opacity: Double

    func body(content: Content) -> some View {
        content.offset(x: dx).opacity(opacity)
    }
}
