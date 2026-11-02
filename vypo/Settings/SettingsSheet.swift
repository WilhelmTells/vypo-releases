import SwiftUI

enum SheetWidth {
    /// Lists and confirmations.
    static let list: CGFloat = 540
    /// Forms that edit one entry.
    static let form: CGFloat = 440
}

/// The one pattern for every Settings sheet.
/// A title, at most one sentence under it, the content, a footer, and `Space.s5` around everything.
struct SettingsSheet<Content: View, Footer: View>: View {
    var title: LocalizedStringKey
    var explanation: LocalizedStringKey?
    var width: CGFloat
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let explanation {
                    Text(explanation)
                        .font(.callout)
                        .foregroundStyle(Color.vyLabelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content
            footer
        }
        .padding(Space.s5)
        .frame(width: width)
    }
}

/// A list saves as you change it, so it only closes: “Done” with Return, and Esc as well.
struct SheetListFooter<Leading: View>: View {
    @Environment(\.dismiss) private var dismiss
    @ViewBuilder var leading: Leading

    var body: some View {
        HStack(spacing: Space.s2) {
            leading
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        // Esc has no button of its own here. Not `.hidden()`: a hidden button loses its shortcut.
        .background {
            Button("Close", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }
}

extension SheetListFooter where Leading == EmptyView {
    init() { leading = EmptyView() }
}

/// A form saves on Save. “Delete” only when editing; pass “Delete…” if it asks first.
struct SheetFormFooter: View {
    @Environment(\.dismiss) private var dismiss
    var deleteTitle: LocalizedStringKey = "Delete"
    var onDelete: (() -> Void)?
    var canSave: Bool
    var onSave: () -> Void

    var body: some View {
        HStack(spacing: Space.s2) {
            if let onDelete {
                Button(deleteTitle, role: .destructive, action: onDelete)
                    .foregroundStyle(Color.vyDanger)
            }
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Save", action: onSave)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
        }
    }
}

/// A confirmation does one thing, named by its verb.
struct SheetConfirmFooter: View {
    @Environment(\.dismiss) private var dismiss
    var action: LocalizedStringKey
    var enabled = true
    var perform: () -> Void

    var body: some View {
        HStack(spacing: Space.s2) {
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(action, action: perform)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!enabled)
        }
    }
}

/// One word per line. `hint` shows inside the field while it is empty.
struct SheetWordEditor: View {
    var label: LocalizedStringKey
    @Binding var text: String
    var height: CGFloat
    var hint: LocalizedStringKey?

    var body: some View {
        TextEditor(text: $text)
            .font(.body)
            .frame(height: height)
            .scrollContentBackground(.hidden)
            .padding(4)
            .background(RoundedRectangle(cornerRadius: Radius.sm).fill(Color.vyBgGroup))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Color.vyBorderControl, lineWidth: 1))
            .overlay(alignment: .topLeading) {
                if let hint, text.isEmpty {
                    Text(hint)
                        .font(.body)
                        .foregroundStyle(Color.vyLabelSecondary)
                        .padding(.horizontal, 9) // The editor's padding plus its text view's line padding.
                        .padding(.vertical, 4)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel(Text(label))
    }
}

extension View {
    /// A grouped Form inside a sheet: its groups start at the title's left edge and end at the footer's right edge.
    /// A grouped Form keeps a margin of 20 pt on every side, and `contentMargins` doesn't reach it (tried in 0.5.0), so
    /// the Form grows past it. Sideways it fills the sheet's padding. Up and down it takes part of the gap next to it.
    /// A list that `scrolls` keeps the gaps to what is above and below, so its rows stay clear of them.
    func sheetForm(scrolls: Bool = false) -> some View {
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, -20)
            .padding(.top, scrolls ? -Space.s3 : -Space.s4)
            .padding(.bottom, scrolls ? 0 : -Space.s4)
    }
}
