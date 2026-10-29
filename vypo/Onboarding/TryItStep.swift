import AppKit
import NaturalLanguage
import SwiftUI

/// Step 6: a real text area on the dawn scene. Nothing is written into it directly: the dictation runs the real
/// paste path, and every outcome gets a result line.
struct TryItStep: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState
    let model: OnboardingModel
    @State private var text: String
    @State private var outcome: TryItOutcome?
    @FocusState private var fieldFocused: Bool
    @State private var wasReady = false
    @State private var handled = 0
    private let previewFocused: Bool?

    /// The `preview…` values show a state in snapshots, where nothing can be dictated or focused.
    init(model: OnboardingModel, previewOutcome: TryItOutcome? = nil, previewText: String = "", previewFocused: Bool? = nil) {
        self.model = model
        _outcome = State(initialValue: previewOutcome)
        _text = State(initialValue: previewText)
        self.previewFocused = previewFocused
    }

    var body: some View {
        let state = current
        VStack(spacing: 0) {
            OBTitle(title: "Try it",
                    text: "Hold \(Text(keyName).fontWeight(.semibold)), speak, let go. vypo writes the text where your cursor is.")
            VStack(spacing: 2) {
                Text("Try saying").font(OBFont.caption).foregroundStyle(Color.vyLabelSecondary)
                Text("“vypo turns my voice into text on my own Mac.”")
                    .font(.system(size: 19, weight: .semibold)).lineSpacing(2)
                    .foregroundStyle(Color.vyLabel)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
            .padding(.top, 14)
            ZStack {
                WoodcutStage(dawn: true, cropHeight: 104)
                GlassStagePill(size: CGSize(width: 150, height: 60), content: pillContent(state.area),
                               level: { [meter = app.levelMeter] in meter.level },
                               barWidth: 5, gap: 5, minHeight: 5, maxHeight: 40)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9)))
            }
            .opacity(isLocked(state.area) ? 0.5 : 1)
            .padding(.top, 12)
            field(state)
                .padding(.top, 10)
            resultLine(state)
                .frame(minHeight: 36)
                .padding(.top, 4)
        }
        .frame(width: 460)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.25), value: isLocked(state.area))
        .onAppear {
            wasReady = state.model == .ready
            if wasReady { bringForward() }
        }
        .onChange(of: state.model == .ready) { _, ready in
            if ready && !wasReady { bringForward() }
            wasReady = ready
        }
        .onChange(of: app.pillBase) { _, mode in
            if mode == .listening || mode == .handsfree { outcome = nil }
        }
        .onChange(of: app.lastOutcome?.id) { _, id in
            guard let id, id != handled, let result = app.lastOutcome?.outcome else { return }
            handled = id
            receive(result)
        }
    }

    // MARK: State

    private var keyName: String { app.prefs.dictationKey.spoken }

    private var current: TryItState {
        let badge = ModelBadge.make(state: app.models?.state ?? .notInstalled, loadFailed: app.models?.loadFailed ?? false,
                                    failure: app.models?.manager.lastFailure)
        let modelStatus: TryItState.ModelStatus = switch badge {
        case .ready: .ready
        case .failed: .failed
        case .downloading(let p): .loading(percent: p)
        case .preparing: .loading(percent: 100)
        case .notStarted: .loading(percent: 0)
        }
        let activity: TryItState.Activity = switch app.pillBase {
        case .listening, .handsfree: .recording
        case .processing: .processing
        default: .idle
        }
        return TryItState(model: modelStatus, focused: previewFocused ?? (fieldFocused && activeState != .inactive), activity: activity, outcome: outcome,
                          accessibilityTrusted: app.permissions.accessibilityTrusted)
    }

    private func isLocked(_ area: TryItState.Area) -> Bool {
        if case .locked = area { return true }
        return false
    }

    private func pillContent(_ area: TryItState.Area) -> GlassStagePill.Content {
        switch area {
        case .recording: .bars(flat: false)
        case .processing: .dots
        default: .bars(flat: true)
        }
    }

    /// The model just became ready: window to the front, cursor in the field.
    private func bringForward() {
        NSApp.activate()
        if let window = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) && $0.styleMask.contains(.titled) }) {
            window.makeKeyAndOrderFront(nil)
        }
        fieldFocused = true
    }

    /// Maps what the dictation reported. A paste into vypo's own window counts only once the text is there.
    private func receive(_ result: DictationOutcome) {
        if case .pasted(let pasted) = result {
            let wanted = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                outcome = TryItState.outcome(for: result) { _ in text.contains(wanted) }
            }
        } else {
            outcome = TryItState.outcome(for: result) { _ in false }
        }
    }

    // MARK: Field

    private func field(_ state: TryItState) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return ZStack {
            TextEditor(text: $text)
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
                .writingToolsBehavior(.disabled)
                .focused($fieldFocused)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .disabled(isLocked(state.area))
                .accessibilityLabel("Try it")
            if text.isEmpty {
                overlay(state.area).allowsHitTesting(false)
            }
        }
        .frame(width: 460, height: 60)
        .background(shape.fill(Color.vyBgControl))
        .overlay(shape.strokeBorder(Color.vySeparator, lineWidth: 0.5))
        .overlay(shape.stroke(Color.vyAccent.opacity(state.focused ? 0.2 : 0), lineWidth: 3).padding(-1.5))
        .opacity(isLocked(state.area) ? 0.5 : 1)
        .overlay {
            if case .locked(let percent) = state.area, let percent {
                waiting(percent).allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder private func overlay(_ area: TryItState.Area) -> some View {
        switch area {
        case .notFocused:
            HStack(spacing: 6) {
                Image(systemName: "cursorarrow.click").foregroundStyle(Color.vyAccent)
                Text("Click here, then hold \(Text(keyName).fontWeight(.semibold))")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.vyLabel)
            }
        case .ready, .recording, .processing:
            Text("Your text appears here.").font(.system(size: 15)).foregroundStyle(Color.vyLabelSecondary)
        case .locked:
            EmptyView()
        }
    }

    private func waiting(_ percent: Int) -> some View {
        HStack(spacing: 10) {
            ModelRing(fraction: Double(min(percent, 100)) / 100, size: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text("Waiting for the speech model").font(OBFont.bodySemibold).foregroundStyle(Color.vyLabel)
                Text("\(percent) %").font(OBFont.secondary).monospacedDigit().foregroundStyle(Color.vyLabelSecondary)
            }
        }
        .padding(.horizontal, 10)
    }

    // MARK: Result line

    @ViewBuilder private func resultLine(_ state: TryItState) -> some View {
        Group {
            if let line = state.resultLine {
                HStack(spacing: 8) {
                    resultContent(line)
                    Spacer(minLength: 0)
                    resultAction(line)
                }
                .transition(.statusLine(reduceMotion: reduceMotion))
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.2), value: state.resultLine)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func resultContent(_ line: TryItOutcome) -> some View {
        switch line {
        case .inserted:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.vySuccess).font(.system(size: 16))
            Text("Inserted").font(OBFont.bodySemibold).foregroundStyle(Color.vySuccess)
        case .notInYourLanguages(let heard):
            icon("exclamationmark.triangle.fill", .vyWarning)
            Text("Heard: “\(Self.shorten(heard))” \(Self.languageSentence(heard))")
                .font(OBFont.body).foregroundStyle(Color.vyLabel).lineLimit(3)
        case .nothingHeard:
            icon("exclamationmark.triangle.fill", .vyWarning)
            Text("Didn’t hear anything. Check your microphone.").font(OBFont.body).foregroundStyle(Color.vyLabel)
        case .couldntPaste(let heard):
            icon("xmark.circle.fill", .vyDanger)
            if let heard {
                Text("Heard: “\(Self.shorten(heard))” But vypo couldn’t paste it. Is Accessibility still on?")
                    .font(OBFont.body).foregroundStyle(Color.vyLabel).lineLimit(3)
            } else {
                Text("vypo can’t paste without Accessibility. Is it still on?").font(OBFont.body).foregroundStyle(Color.vyLabel)
            }
        case .modelFailed:
            icon("xmark.circle.fill", .vyDanger)
            Text("The speech model couldn’t be loaded.").font(OBFont.body).foregroundStyle(Color.vyLabel)
        }
    }

    @ViewBuilder private func resultAction(_ line: TryItOutcome) -> some View {
        switch line {
        case .inserted: EmptyView()
        case .notInYourLanguages:
            Button("Choose languages") { model.step = OnboardingStep.languages.rawValue }.buttonStyle(.ob(.small))
        case .nothingHeard:
            Button("Microphone settings") { app.openSettings(.recording) }.buttonStyle(.ob(.small))
        case .couldntPaste:
            Button("Open System Settings") {
                Permissions.openAccessibilitySettings()
            }
            .buttonStyle(.ob(.small))
        case .modelFailed:
            Button("Try again") { app.models?.retry() }.buttonStyle(.ob(.small))
        }
    }

    private func icon(_ name: String, _ color: Color) -> some View {
        Image(systemName: name).foregroundStyle(color).font(.system(size: 16)).accessibilityHidden(true)
    }

    // MARK: Text helpers

    static func shorten(_ text: String, limit: Int = 48) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count > limit ? String(t.prefix(limit)) + "…" : t
    }

    /// “This looks like English, which isn't in your languages.” (or the neutral sentence if the language is unclear).
    static func languageSentence(_ heard: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = Lang.allCases.map(\.nlLanguage)
        recognizer.processString(heard)
        if let top = recognizer.languageHypotheses(withMaximum: 1).first, top.value > 0.6,
           let lang = Lang.allCases.first(where: { $0.nlLanguage == top.key }) {
            return String(localized: "This looks like \(lang.name), which isn’t in your languages.")
        }
        return String(localized: "This doesn’t look like one of your languages.")
    }
}
