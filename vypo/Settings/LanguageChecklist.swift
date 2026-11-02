import SwiftUI

/// The dictation languages as checkboxes: the chosen ones first, the rest under “More languages”.
/// The order is fixed when the list appears, so a language doesn't jump when it's checked.
struct LanguageChecklist: View {
    @Environment(AppState.self) private var app
    @State var showMore = false
    @State private var top: [Lang] = []

    var body: some View {
        let others = Lang.allCases.filter { !top.contains($0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        VStack(alignment: .leading, spacing: Space.s2) {
            ForEach(top) { row($0) }
            DisclosureGroup("More languages", isExpanded: $showMore) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3),
                          alignment: .leading, spacing: Space.s2) {
                    ForEach(others) { row($0) }
                }
                .padding(.top, Space.s2)
            }
        }
        .onAppear { if top.isEmpty { top = app.prefs.languages } }
    }

    private func row(_ lang: Lang) -> some View {
        let chosen = app.prefs.languages
        return Toggle(lang.name, isOn: Binding(get: { chosen.contains(lang) }, set: { app.prefs.setChosen(lang, $0) }))
            .toggleStyle(.checkbox)
            // The last language stays.
            .disabled(chosen == [lang])
    }
}

/// Settings → General → Languages → Choose…
struct LanguagesSheet: View {
    var body: some View {
        SettingsSheet(title: "Languages", explanation: "vypo recognizes which of your languages you’re speaking.",
                      width: SheetWidth.list) {
            LanguageChecklist(showMore: true)
        } footer: {
            SheetListFooter()
        }
    }
}
