import SwiftUI

/// The path bar of steps 2 to 6: the model's progress, then one item per step (SPEC: Path bar).
struct OnboardingPathBar: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: OnboardingModel
    @State private var showModel = false
    @Namespace private var capsule

    var body: some View {
        ViewThatFits(in: .horizontal) {
            bar(collapsed: false)
            bar(collapsed: true)
        }
        .frame(maxWidth: 740)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .easeInOut(duration: 0.25), value: model.step)
    }

    private var badge: ModelBadge {
        ModelBadge.make(state: app.models?.state ?? .notInstalled, loadFailed: app.models?.loadFailed ?? false,
                        failure: app.models?.manager.lastFailure)
    }

    private var permissionsOK: Bool { app.permissions.micGranted && app.permissions.accessibilityTrusted }

    private func bar(collapsed: Bool) -> some View {
        HStack(spacing: 6) {
            modelItem
            ForEach(PathItem.allCases.dropFirst()) { item in
                chevron
                stepItem(item, collapsed: collapsed)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .contain)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Color.vyLabelTertiary)
            .frame(width: 6, height: 10)
            .accessibilityHidden(true)
    }

    // MARK: Model

    private var modelItem: some View {
        Button { showModel.toggle() } label: {
            HStack(spacing: 6) {
                switch badge {
                case .notStarted, .downloading:
                    ModelRing(fraction: ringFraction)
                case .preparing:
                    ModelRing(fraction: 0.9, pulsing: true)
                case .ready:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.vySuccess).font(.system(size: 14))
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                case .failed:
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.vyWarning).font(.system(size: 13))
                }
                Text("Model").font(OBFont.secondary).foregroundStyle(Color.vyLabel)
                if case .downloading(let percent) = badge {
                    Text("\(percent) %").font(OBFont.secondarySemibold).monospacedDigit().foregroundStyle(Color.vyLabel)
                } else if badge == .preparing {
                    Text("Preparing…").font(OBFont.secondarySemibold).foregroundStyle(Color.vyLabel)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).inset(by: 0.5).stroke(Color.vySeparator, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityLabel(modelAccessibility)
        .popover(isPresented: $showModel, arrowEdge: .bottom) { ModelPopover(badge: badge) }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: badge.isReady)
    }

    private var ringFraction: Double {
        if case .downloading(let percent) = badge { return Double(percent) / 100 * 0.9 }
        return 0
    }

    private var modelAccessibility: String {
        switch badge {
        case .notStarted: String(localized: "Model")
        case .downloading(let p): String(localized: "Model, \(p) percent")
        case .preparing: String(localized: "Model, preparing")
        case .ready: String(localized: "Model, ready")
        case .failed: String(localized: "Model, needs attention")
        }
    }

    // MARK: Steps

    @ViewBuilder private func stepItem(_ item: PathItem, collapsed: Bool) -> some View {
        let status = OnboardingRules.status(of: item, step: model.step, permissionsOK: permissionsOK)
        if collapsed && status == .done {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14)).foregroundStyle(Color.vySuccess)
                .frame(height: 26)
                .accessibilityLabel(Text("\(item.title), done"))
        } else {
            HStack(spacing: 6) {
                icon(status)
                Text(item.title)
                    .font(status == .current ? OBFont.secondarySemibold : OBFont.secondary)
                    .foregroundStyle(status == .current ? Color.vyLabel : Color.vyLabelSecondary)
            }
            .padding(.horizontal, status == .current ? 10 : 4)
            .frame(height: 26)
            .background {
                if status == .current {
                    Capsule().fill(Color.vyBgGroup)
                        .shadow(color: .black.opacity(0.1), radius: 1.5, y: 1)
                        .matchedGeometryEffect(id: "capsule", in: capsule)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(accessibilityText(item, status)))
        }
    }

    private func accessibilityText(_ item: PathItem, _ status: PathItemStatus) -> String {
        switch status {
        case .current: String(localized: "\(item.title), current step")
        case .done: String(localized: "\(item.title), done")
        case .attention: String(localized: "\(item.title), needs attention")
        case .todo: item.title
        }
    }

    @ViewBuilder private func icon(_ status: PathItemStatus) -> some View {
        switch status {
        case .todo:
            Circle().strokeBorder(Color.vyLabelSecondary, lineWidth: 1).frame(width: 14, height: 14)
        case .current:
            ZStack {
                Circle().strokeBorder(Color.vyAccent, lineWidth: 1.5)
                Circle().fill(Color.vyAccent).frame(width: 6, height: 6)
            }
            .frame(width: 14, height: 14)
        case .done:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundStyle(Color.vySuccess)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.8).combined(with: .opacity))
        case .attention:
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 13)).foregroundStyle(Color.vyWarning)
        }
    }
}

/// The popover of the Model item: bar and size while downloading, or the problem and “Try again”.
struct ModelPopover: View {
    @Environment(AppState.self) private var app
    let badge: ModelBadge

    /// The size the spec shows, in MiB (the 613 MB measured for the folder).
    static let totalMB = 613

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Speech model").font(OBFont.bodySemibold).foregroundStyle(Color.vyLabel)
            switch badge {
            case .notStarted:
                Text("Not downloaded yet.").font(OBFont.secondary).foregroundStyle(Color.vyLabelSecondary)
            case .downloading(let percent):
                ProgressBarThick(value: Double(percent) / 100)
                Text(Self.progressText(percent: percent))
                    .font(OBFont.secondary).monospacedDigit().foregroundStyle(Color.vyLabelSecondary)
            case .preparing:
                ProgressBarThick(value: 0.9)
                Text("Preparing…").font(OBFont.secondary).foregroundStyle(Color.vyLabelSecondary)
            case .ready:
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .font(OBFont.secondary).foregroundStyle(Color.vySuccess)
            case .failed(let problem):
                Text(Self.problemText(problem)).font(OBFont.secondary).foregroundStyle(Color.vyLabelSecondary)
                Button("Try again") { app.models?.retry() }
                    .buttonStyle(.ob(.rowPrimary))
            }
        }
        .padding(14)
        .frame(width: 240, alignment: .leading)
    }

    static func progressText(percent: Int) -> String {
        let done = Int((Double(totalMB) * Double(percent) / 100).rounded())
        return String(localized: "\(done) of \(totalMB) MB (\(percent) %)")
    }

    static func problemText(_ problem: ModelProblem) -> String {
        switch problem {
        case .downloadFailed: String(localized: "Download failed.")
        case .offline: String(localized: "You’re offline.")
        case .couldntLoad: String(localized: "Couldn’t be loaded.")
        }
    }
}

/// The 10 pt bar of the popover.
struct ProgressBarThick: View {
    var value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.vyFillTrack)
                Capsule().fill(Color.vyAccent).frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 10)
        .accessibilityElement()
        .accessibilityValue("\(Int(value * 100)) percent")
    }
}
