import AppKit
import KeyboardShortcuts
import SwiftUI
import UniformTypeIdentifiers

/// Settings → Words (§11.2, §23.2, §23.9, §23.10): the glossary, replacements and filler words.
struct WordsPane: View {
    @Environment(AppState.self) private var app
    @State private var search = ""
    @State private var editing: TermSheet.Mode?
    @State private var managingSets = false
    @State private var editingFillers = false
    @State private var editingSpellings = false
    @State private var editingCharacters = false
    /// nil = All.
    @State private var setFilter: UUID?
    @State private var importResult: ImportTermsSheet.Result?
    @State private var nothingFound: String?

    private var filtered: [GlossaryEntry] {
        let q = search.trimmingCharacters(in: .whitespaces)
        var all = app.glossary.entries
        if let setFilter { all = all.filter { ($0.setID ?? GlossarySet.generalID) == setFilter } }
        guard !q.isEmpty else { return all }
        return all.filter { e in
            e.term.localizedCaseInsensitiveContains(q) || e.soundsLike.contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            form
                .onAppear { scrollToTarget(proxy) }
                .onChange(of: app.scrollTarget) { scrollToTarget(proxy) }
        }
    }

    /// A widget link: the suggestion rows, at the top of the pane.
    private func scrollToTarget(_ proxy: ScrollViewProxy) {
        guard app.scrollTarget == .suggestions else { return }
        app.scrollTarget = nil
        Task { @MainActor in proxy.scrollTo(Self.suggestionsAnchor, anchor: .top) }
    }

    private static let suggestionsAnchor = "suggestions"

    private var form: some View {
        @Bindable var prefs = app.prefs
        let suggestions = app.glossary.visibleSuggestions
        let terms = filtered
        return Form {
            Section {
                if terms.isEmpty {
                    Text(search.isEmpty ? "No terms yet. Add names, products or jargon that vypo should always spell right."
                                        : "No terms match “\(search)”.")
                        .foregroundStyle(Color.vyLabelSecondary)
                }
                ForEach(terms) { entry in
                    HStack(spacing: Space.s3) {
                        RowLabel(title: "\(entry.term)", description: soundsLikeText(entry), strong: true)
                        Spacer()
                        Badge(text: entry.scope.label)
                        if app.glossary.sets.count > 1 {
                            Badge(text: "\(app.glossary.set(for: entry).displayName)")
                        }
                        Button("Edit…") { editing = .edit(entry) }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.vyAccent)
                    }
                }
            } header: {
                PaneSectionHeader(pane: .words, title: "Glossary") {
                    toolbar
                    Color.clear.frame(height: 0).id(Self.suggestionsAnchor)
                    ForEach(suggestions) { s in
                        SuggestionRow(suggestion: s, onAdd: { app.glossary.accept(s) }, onIgnore: { app.glossary.ignore(s) })
                    }
                }
                .textCase(nil)
            } footer: {
                Text("vypo always writes a term exactly like this. Tip: select a word in any app and press \(shortcutText) to add it.")
            }

            Section {
                LabeledContent {
                    Picker("Replace similar-sounding words", selection: $prefs.correctionStrength) {
                        Text("Careful").tag(CorrectionStrength.careful)
                        Text("Normal").tag(CorrectionStrength.normal)
                        Text("Strong").tag(CorrectionStrength.strong)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                } label: {
                    RowLabel(title: "Replace similar-sounding words",
                             description: "Fixes near misses afterwards, e.g. “tick tock” becomes “TikTok”.")
                }
                LabeledContent {
                    Toggle("Learn from my corrections", isOn: $prefs.learnFromCorrections)
                        .toggleStyle(.switch)
                        .labelsHidden()
                } label: {
                    RowLabel(title: "Learn from my corrections",
                             description: "When you correct a word vypo wrote, right where it wrote it, vypo suggests it for the glossary. It only looks at its own text.")
                }
            } header: {
                Text("How the glossary helps")
            } footer: {
                Text("If a term keeps coming out wrong, edit it and add what vypo wrote instead under “Sounds like”.")
            }

            // New layout: the own list first, then the three built-in lists with a switch and “Edit…” together.
            ReplacementsSection()

            if app.wordsLayout == .spokenCharacters {
                Section {
                    LabeledContent {
                        HStack(spacing: Space.s2) {
                            Toggle("Write spoken characters", isOn: $prefs.spokenCharacters)
                                .toggleStyle(.switch)
                                .labelsHidden()
                            Button("Edit…") { editingCharacters = true }
                                .buttonStyle(.plain)
                                .foregroundStyle(Color.vyAccent)
                        }
                    } label: {
                        RowLabel(title: "Write spoken characters", description: "comma, period, slash, new line …")
                    }
                } header: {
                    Text("Spoken characters")
                } footer: {
                    Text("Say “comma” or “slash” and vypo writes “,” or “/”, the same in every app. Under Edit… you set which ones also work in a sentence.")
                }
            }

            Section {
                LabeledContent {
                    HStack(spacing: Space.s2) {
                        Toggle("Remove filler words", isOn: $prefs.removeFillers)
                            .toggleStyle(.switch)
                            .labelsHidden()
                        Button("Edit…") { editingFillers = true }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.vyAccent)
                    }
                } label: {
                    RowLabel(title: "Remove filler words", description: prefs.fillerPreview.map { "\($0)" })
                }
            } header: {
                Text("Filler words")
            }

            Section {
                LabeledContent {
                    HStack(spacing: Space.s2) {
                        Toggle("Fix spellings", isOn: $prefs.spellingsEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                        Button("Edit…") { editingSpellings = true }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.vyAccent)
                    }
                } label: {
                    RowLabel(title: "Fix spellings", description: "PDF, ZIP, macOS …")
                }
            } header: {
                Text("Spellings")
            }
        }
        .formStyle(.grouped)
        // The dot in the sidebar means “something new here”, so it goes as soon as this pane has shown it.
        .onAppear { app.glossary.markSuggestionsSeen() }
        .onChange(of: app.glossary.hasUnseenSuggestions) { app.glossary.markSuggestionsSeen() }
        .sheet(item: $editing) { mode in
            TermSheet(mode: mode).environment(app)
        }
        .sheet(isPresented: $editingFillers) {
            FillerWordsSheet().environment(app)
        }
        .sheet(isPresented: $editingSpellings) {
            SpellingsSheet().environment(app)
        }
        .sheet(isPresented: $editingCharacters) {
            SpokenCharactersSheet().environment(app)
        }
        .sheet(isPresented: $managingSets) {
            SetsSheet().environment(app)
        }
        .sheet(item: $importResult) { result in
            ImportTermsSheet(result: result).environment(app)
        }
        .alert(nothingFound.map { String(localized: "No new terms found in \($0).") } ?? "", isPresented: Binding(get: { nothingFound != nil }, set: { if !$0 { nothingFound = nil } })) {
            Button("OK") { nothingFound = nil }
        }
    }

    /// Search, set filter, add, and everything else in the ⋯ menu.
    private var toolbar: some View {
        HStack(spacing: Space.s2) {
            SearchField(prompt: "Search terms", text: $search)
            if app.glossary.sets.count > 1 {
                Picker("Set", selection: $setFilter) {
                    Text("All sets").tag(UUID?.none)
                    ForEach(app.glossary.sets) { Text($0.displayName).tag(UUID?.some($0.id)) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            Button { editing = .add } label: { Label("Add Term…", systemImage: "plus") }
            Menu {
                Button("Import from Document…") { importDocument() }
                Divider()
                Button("Import Glossary…") { importFile() }
                Button("Export Glossary…") { exportFile() }
                Divider()
                Button("Manage Sets…") { managingSets = true }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More")
        }
    }

    private var shortcutText: String {
        KeyboardShortcuts.getShortcut(for: .addToGlossary)?.description ?? "⌃⌥G"
    }

    private func importDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, UTType(filenameExtension: "docx") ?? .data, .plainText,
                                     UTType(filenameExtension: "md") ?? .plainText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let name = url.lastPathComponent
        let existing = Set(app.glossary.entries.map(\.term))
        let found = TermExtractor().extract(from: TermExtractor.text(from: url) ?? "", existing: existing)
        if found.isEmpty {
            nothingFound = name
        } else {
            importResult = ImportTermsSheet.Result(fileName: name, found: found)
        }
    }

    private func soundsLikeText(_ e: GlossaryEntry) -> LocalizedStringKey? {
        guard !e.soundsLike.isEmpty else { return nil }
        let list = e.soundsLike.map(Formatting.quoted).joined(separator: ", ")
        return "sounds like \(list)"
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try app.glossary.importData(try Data(contentsOf: url))
        } catch {
            Log.store.error("Glossary import failed: \(error.localizedDescription, privacy: .public)")
            NSSound.beep()
        }
    }

    private func exportFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "vypo Glossary.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try app.glossary.exportData().write(to: url, options: .atomic)
        } catch {
            Log.store.error("Glossary export failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Add/Edit term sheet (§11.2).
struct TermSheet: View {
    enum Mode: Identifiable {
        case add
        case edit(GlossaryEntry)

        var id: String {
            switch self {
            case .add: "add"
            case .edit(let e): e.id.uuidString
            }
        }
    }

    let mode: Mode
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var term = ""
    @State private var soundsLike = ""
    @State private var scope: GlossaryScope = .all
    @State private var setID: UUID = GlossarySet.generalID

    var body: some View {
        SettingsSheet(title: isNew ? "New Term" : "Edit Term", width: SheetWidth.form) {
            Form {
                TextField("Term", text: $term)
                TextField("Sounds like", text: $soundsLike, prompt: Text("e.g. tick tock, tik tok"))
                Picker("Applies to", selection: $scope) {
                    ForEach(GlossaryScope.pickerScopes(chosen: app.prefs.languages, current: scope), id: \.self) {
                        Text($0.title).tag($0)
                    }
                }
                .pickerStyle(.menu)
                Picker("Set", selection: $setID) {
                    ForEach(app.glossary.sets) { Text($0.displayName).tag($0.id) }
                }
                .pickerStyle(.menu)
            }
            .sheetForm()
        } footer: {
            SheetFormFooter(onDelete: entry.map { e in { app.glossary.delete(e.id); dismiss() } },
                            canSave: !term.trimmingCharacters(in: .whitespaces).isEmpty,
                            onSave: save)
        }
        .onAppear {
            if let e = entry {
                term = e.term
                soundsLike = e.soundsLike.joined(separator: ", ")
                scope = e.scope
                setID = e.setID ?? GlossarySet.generalID
            }
        }
    }

    private var entry: GlossaryEntry? { if case .edit(let e) = mode { e } else { nil } }
    private var isNew: Bool { entry == nil }

    private func save() {
        let variants = soundsLike.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let t = term.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .add:
            app.glossary.add(term: t, soundsLike: variants, scope: scope, setID: setID)
        case .edit(var e):
            e.term = t
            e.soundsLike = variants
            e.scope = scope
            e.setID = setID
            app.glossary.update(e)
        }
        dismiss()
    }
}

/// The Replacements group (§11.5), in the Words pane.
struct ReplacementsSection: View {
    @Environment(AppState.self) private var app
    @State private var editing: Replacement?
    @State private var moving = false

    var body: some View {
        Section {
            // A Mac from before 0.4.0: the move to Spoken characters, only on a click. “Not now” leaves the link below.
            if app.wordsLayout == .legacy && !app.prefs.spokenCharactersHintDismissed {
                HStack(alignment: .top, spacing: Space.s3) {
                    IconTile(symbol: "sparkles", tint: .vyAccent)
                    RowLabel(title: "New: Spoken characters.",
                             description: "Words like “comma” or “new line” get their own list, with more characters, and work the same in every app.")
                    Spacer()
                    Button("Switch…") { moving = true }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.vyAccent)
                        .fixedSize()
                    Button("Not Now") { app.prefs.spokenCharactersHintDismissed = true }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.vyLabelSecondary)
                        .fixedSize()
                }
            }
            if app.wordsLayout == .spokenCharacters && app.replacements.items.isEmpty {
                // A plain String: as a LocalizedStringKey the address would become a link.
                Text(String(localized: "Your own words and what vypo writes for them, e.g. “my email” becomes name@example.com."))
                    .foregroundStyle(Color.vyLabelSecondary)
            }
            ForEach(app.replacements.items) { r in
                HStack(spacing: Space.s3) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(r.summary)").foregroundStyle(Color.vyLabel)
                        Text("becomes \(Replacements.display(r.output))")
                            .font(.callout).foregroundStyle(Color.vyLabelSecondary)
                        if let note = app.wordsLayout == .legacy ? r.inSentence.listNote : SpokenCharacters.listNote(r.inSentence.alsoInSentence) {
                            Text(note).font(.caption).foregroundStyle(Color.vyLabelSecondary)
                        }
                    }
                    Spacer()
                    Toggle("\(r.summary)", isOn: Binding(get: { r.enabled }, set: { app.replacements.setEnabled(r.id, $0) }))
                        .labelsHidden()
                    Button("Edit…") { editing = r }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.vyAccent)
                }
            }
            HStack {
                Button("Add Replacement…") { editing = Replacement(spoken: [], output: "") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.vyAccent)
                Spacer()
                // A new installation has no default replacements: its characters are under Spoken characters.
                if app.wordsLayout == .legacy {
                    Button("Restore Defaults") { app.replacements.restoreDefaults() }
                        .buttonStyle(.plain)
                        .font(.callout)
                        .foregroundStyle(Color.vyLabelSecondary)
                }
            }
            if app.wordsLayout == .legacy && app.prefs.spokenCharactersHintDismissed {
                Button("Switch to Spoken Characters…") { moving = true }
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(Color.vyAccent)
            }
        } header: {
            Text("Replacements")
        } footer: {
            if app.wordsLayout == .legacy {
                Text("Say the phrase on the left and vypo writes the right side. Said on its own, an entry works in every app; in a sentence, as set for the entry.")
            } else {
                Text("Say the phrase on the left and vypo writes the right side, the same in every app. Said on its own, an entry always works; in a sentence, if you set it to.")
            }
        }
        .sheet(item: $editing) { r in
            ReplacementSheet(replacement: r).environment(app)
        }
        .sheet(isPresented: $moving) {
            MoveToSpokenCharactersSheet().environment(app)
        }
    }
}

/// Words → Replacements → Switch…: what the move to Spoken characters will do, before it does it.
struct MoveToSpokenCharactersSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var failed: SpokenCharactersMoveError?

    var body: some View {
        // Computed from the lists as they are now; `moveToSpokenCharacters` computes the same again. The new defaults get
        // new ids each time, so the rows go by output (unique in Spoken characters).
        let move = SpokenCharacters.migration(from: app.replacements.items, spokenPunctuation: app.prefs.spokenPunctuation)
        SettingsSheet(title: "Switch to Spoken Characters", explanation: "A backup of your Replacements is saved first.",
                      width: SheetWidth.list) {
            Form {
                if !move.moved.isEmpty {
                    Section("Moves to Spoken characters") {
                        ForEach(move.moved, id: \.output) { characterRow($0) }
                    }
                }
                if !move.added.isEmpty {
                    Section("New in Spoken characters") {
                        ForEach(move.added, id: \.output) { characterRow($0) }
                    }
                }
                if !move.ownReplacements.isEmpty {
                    Section("Stays in Replacements") {
                        ForEach(move.ownReplacements) { r in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: r.summary).foregroundStyle(Color.vyLabel)
                                Text("becomes \(Replacements.display(r.output))")
                                    .font(.callout).foregroundStyle(Color.vyLabelSecondary)
                            }
                        }
                    }
                }
            }
            .sheetForm(scrolls: true)
            .frame(height: 380)
            if let failed {
                Text(failed == .backup ? String(localized: "The backup couldn’t be saved, so nothing was changed.")
                                       : String(localized: "Spoken characters couldn’t be saved, so nothing was changed."))
                    .font(.callout)
                    .foregroundStyle(Color.vyDanger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } footer: {
            SheetConfirmFooter(action: "Switch") {
                do {
                    try app.moveToSpokenCharacters()
                    dismiss()
                } catch {
                    failed = error as? SpokenCharactersMoveError ?? .write
                }
            }
        }
    }

    private func characterRow(_ c: SpokenCharacter) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: c.summary).foregroundStyle(Color.vyLabel)
            Text("becomes \(Replacements.display(c.output))")
                .font(.callout).foregroundStyle(Color.vyLabelSecondary)
            Text(SpokenCharacters.listNote(c.alsoInSentence)).font(.caption).foregroundStyle(Color.vyLabelSecondary)
            if !c.enabled {
                Text("Switched off").font(.caption).foregroundStyle(Color.vyLabelSecondary)
            }
        }
    }
}

extension SentenceScope {
    /// The small line under an entry in the list; nothing for “everywhere”.
    var listNote: String? {
        switch self {
        case .everywhere: nil
        case .promptOnly: String(localized: "In sentences: Prompt apps")
        case .never: String(localized: "Only on its own")
        }
    }

    var title: String {
        switch self {
        case .everywhere: String(localized: "Everywhere")
        case .promptOnly: String(localized: "Prompt apps only")
        case .never: String(localized: "Never (only on its own)")
        }
    }

    var explanation: String {
        switch self {
        case .everywhere: String(localized: "Replaced anywhere in a sentence, in every app.")
        case .promptOnly: String(localized: "Replaced in a sentence only in apps set to Prompt.")
        case .never: String(localized: "Replaced only when it is all you say.")
        }
    }
}

/// “Spoken” / “Output” / “In a sentence” sheet.
struct ReplacementSheet: View {
    let replacement: Replacement
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var spoken = ""
    @State private var output = ""
    @State private var inSentence = SentenceScope.everywhere
    /// Fixed when the sheet opens, so the title doesn't change while it closes.
    @State private var isNew = true

    var body: some View {
        SettingsSheet(title: isNew ? "New Replacement" : "Edit Replacement", width: SheetWidth.form) {
            Form {
                Section {
                    if app.wordsLayout == .legacy {
                        TextField("Spoken", text: $spoken, prompt: Text("e.g. slash, Schrägstrich"))
                    } else {
                        TextField("Spoken", text: $spoken, prompt: Text("e.g. my email, meine Mail"))
                    }
                    TextField("Output", text: $output)
                } footer: {
                    Text("Separate spellings with commas.")
                }
                if app.wordsLayout == .legacy {
                    Section {
                        Picker("In a sentence", selection: $inSentence) {
                            ForEach(SentenceScope.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                    } footer: {
                        Text("\(inSentence.explanation)")
                    }
                } else {
                    Section {
                        Toggle("Also in a sentence", isOn: Binding(get: { inSentence.alsoInSentence },
                                                                   set: { inSentence = $0 ? .everywhere : .never }))
                    } footer: {
                        Text("Said on its own, it always works. In a sentence only if this is on.")
                    }
                }
            }
            .sheetForm()
        } footer: {
            SheetFormFooter(onDelete: isNew ? nil : { app.replacements.delete(replacement.id); dismiss() },
                            canSave: !Replacements.variants(spoken).isEmpty) {
                var r = replacement
                r.spoken = Replacements.variants(spoken)
                r.output = output.replacingOccurrences(of: "↵", with: "\n")
                r.inSentence = inSentence
                app.replacements.upsert(r)
                dismiss()
            }
        }
        .onAppear {
            isNew = !app.replacements.items.contains { $0.id == replacement.id }
            spoken = replacement.spokenText
            output = Replacements.display(replacement.output)
            inSentence = app.wordsLayout == .legacy ? replacement.inSentence : replacement.inEveryApp.inSentence
        }
    }
}

/// Words → Spoken characters → Edit…: every entry, with on/off, Edit, Add and Restore Defaults.
struct SpokenCharactersSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var editing: SpokenCharacter?

    var body: some View {
        SettingsSheet(title: "Spoken Characters",
                      explanation: "Say the word and vypo writes the character, the same in every app.",
                      width: SheetWidth.list) {
            Form {
                ForEach(app.spokenCharacters?.items ?? []) { c in
                    HStack(spacing: Space.s3) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(c.summary)").foregroundStyle(Color.vyLabel)
                            Text("becomes \(Replacements.display(c.output))")
                                .font(.callout).foregroundStyle(Color.vyLabelSecondary)
                            Text(SpokenCharacters.listNote(c.alsoInSentence)).font(.caption).foregroundStyle(Color.vyLabelSecondary)
                        }
                        Spacer()
                        Toggle("\(c.summary)", isOn: Binding(get: { c.enabled }, set: { app.spokenCharacters?.setEnabled(c.id, $0) }))
                            .labelsHidden()
                        Button("Edit…") { editing = c }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.vyAccent)
                    }
                }
            }
            .sheetForm(scrolls: true)
            .frame(height: 380)
        } footer: {
            SheetListFooter {
                Button("Add Character…") { editing = SpokenCharacter(spoken: [], output: "", alsoInSentence: true) }
                Button("Restore Defaults") { app.spokenCharacters?.restoreDefaults() }
            }
        }
        .sheet(item: $editing) { c in
            SpokenCharacterSheet(character: c).environment(app)
        }
    }
}

extension SpokenCharacters {
    /// The small line under an entry.
    static func listNote(_ alsoInSentence: Bool) -> String {
        alsoInSentence ? String(localized: "Also in a sentence") : String(localized: "Only on its own")
    }
}

/// “Spoken” / “Output” / “Also in a sentence” for one spoken character.
struct SpokenCharacterSheet: View {
    let character: SpokenCharacter
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var spoken = ""
    @State private var output = ""
    @State private var alsoInSentence = true
    /// Fixed when the sheet opens, so the title doesn't change while it closes.
    @State private var isNew = true

    var body: some View {
        SettingsSheet(title: isNew ? "New Spoken Character" : "Edit Spoken Character", width: SheetWidth.form) {
            Form {
                Section {
                    TextField("Spoken", text: $spoken, prompt: Text("e.g. comma, Komma"))
                    TextField("Output", text: $output)
                } footer: {
                    Text("Separate spellings with commas.")
                }
                Section {
                    Toggle("Also in a sentence", isOn: $alsoInSentence)
                } footer: {
                    Text("Said on its own, it always works. In a sentence only if this is on.")
                }
            }
            .sheetForm()
        } footer: {
            SheetFormFooter(onDelete: isNew ? nil : { app.spokenCharacters?.delete(character.id); dismiss() },
                            canSave: !Replacements.variants(spoken).isEmpty && !output.isEmpty) {
                var c = character
                c.spoken = Replacements.variants(spoken)
                c.output = output.replacingOccurrences(of: "↵", with: "\n")
                c.alsoInSentence = alsoInSentence
                app.spokenCharacters?.upsert(c)
                dismiss()
            }
        }
        .onAppear {
            isNew = !(app.spokenCharacters?.items.contains { $0.id == character.id } ?? false)
            spoken = character.spokenText
            output = Replacements.display(character.output)
            alsoInSentence = character.alsoInSentence
        }
    }
}

/// A suggestion above the term list: a word you corrected in History or in an app.
private struct SuggestionRow: View {
    var suggestion: GlossarySuggestion
    var onAdd: () -> Void
    var onIgnore: () -> Void

    var body: some View {
        HStack(spacing: Space.s3) {
            IconTile(symbol: "sparkles", tint: .vyAccent)
            RowLabel(title: "\(suggestion.term)", description: "Suggested: you corrected “\(suggestion.spellingsLine)” \(suggestion.count)×")
                .help(suggestion.spellings.joined(separator: " / "))
            Spacer()
            Button("Ignore", action: onIgnore)
                .buttonStyle(.plain)
                .foregroundStyle(Color.vyAccent)
            Button("Add", action: onAdd)
        }
        .padding(Space.s3)
        .background(RoundedRectangle(cornerRadius: Radius.md).fill(Color.vyAccent.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Color.vyAccent.opacity(0.25), lineWidth: 0.5))
    }
}

/// Glossary → ⋯ → Manage Sets…: turn sets on and off, rename, delete, add.
struct SetsSheet: View {
    @Environment(AppState.self) private var app
    @State private var editingSet: SetSheet.Mode?

    var body: some View {
        SettingsSheet(title: "Sets", explanation: "Group terms, e.g. per project, and turn a group off when you don’t need it.",
                      width: SheetWidth.list) {
            Form {
                ForEach(app.glossary.sets) { set in
                    HStack(spacing: Space.s3) {
                        RowLabel(title: "\(set.displayName)", description: "\(app.glossary.count(in: set)) terms")
                        Spacer()
                        Toggle(set.displayName, isOn: Binding(get: { set.isActive }, set: { app.glossary.setActive(set.id, $0) }))
                            .labelsHidden()
                        Button("Edit…") { editingSet = .edit(set) }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.vyAccent)
                    }
                }
            }
            .sheetForm(scrolls: true)
            .frame(minHeight: 160)
        } footer: {
            SheetListFooter {
                Button("New Set…") { editingSet = .new }
            }
        }
        .sheet(item: $editingSet) { mode in
            SetSheet(mode: mode).environment(app)
        }
    }
}

/// One spelling per line, the same for every language. Saved as you type, so closing the sheet can't lose anything.
struct SpellingsSheet: View {
    @Environment(AppState.self) private var app
    @State private var text = ""
    @State private var confirmRestore = false

    var body: some View {
        SettingsSheet(title: "Spellings",
                      explanation: "One spelling per line: vypo writes each one exactly like this, whatever capitals it heard.",
                      width: SheetWidth.list) {
            SheetWordEditor(label: "Spellings", text: $text, height: 220)
        } footer: {
            SheetListFooter {
                Button("Restore Defaults…") { confirmRestore = true }
            }
        }
        .onAppear { text = app.prefs.spellings.joined(separator: "\n") }
        .onChange(of: text) {
            let words = FillerWordsSheet.words(text)
            if words != app.prefs.spellings { app.prefs.setSpellings(words) }
        }
        .alert("Restore the default spellings?", isPresented: $confirmRestore) {
            Button("Restore", role: .destructive) { text = Spellings.defaultList.joined(separator: "\n") }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This replaces your list.")
        }
    }
}

/// One word per line, one list per chosen language (§23.2). Saved as you type, so closing the sheet can't lose anything.
struct FillerWordsSheet: View {
    @Environment(AppState.self) private var app
    @State private var shown: Lang?
    @State private var text = ""
    @State private var confirmRestore = false

    /// The language to show instead of the first chosen one; the picker changes it from there.
    var language: Lang?

    init(language: Lang? = nil) {
        self.language = language
        _shown = State(initialValue: language)
    }

    private var current: Lang { shown ?? app.prefs.languages[0] }

    private func joined(_ words: [String]) -> String { words.joined(separator: "\n") }

    var body: some View {
        let lang = current
        SettingsSheet(title: "Filler Words",
                      explanation: "vypo removes these words from what you dictate, in each of your languages.",
                      width: SheetWidth.list) {
            if app.prefs.languages.count > 1 {
                Picker("Language", selection: Binding(get: { lang }, set: show)) {
                    ForEach(app.prefs.languages) { Text($0.name).tag($0) }
                }
                .pickerStyle(.menu)
                .fixedSize()
            }
            // Saved in the binding, so showing another language can't write this text into it.
            SheetWordEditor(label: "\(lang.name)",
                            text: Binding(get: { text }, set: { text = $0; save($0, for: lang) }),
                            height: 200,
                            hint: "No filler words for \(lang.name) yet. Add one per line.")
                .id(lang) // A fresh editor, so ⌘Z can't bring another language's list back.
        } footer: {
            SheetListFooter {
                Button("Restore Defaults…") { confirmRestore = true }
                    .disabled(app.prefs.fillerWords(for: lang) == FillerRemover.defaultWords(lang))
            }
        }
        .onAppear { text = joined(app.prefs.fillerWords(for: lang)) }
        .onChange(of: language) { if let language { show(language) } }
        .alert("Restore the default filler words for \(lang.name)?", isPresented: $confirmRestore) {
            Button("Restore", role: .destructive) {
                app.prefs.setFillerWords(FillerRemover.defaultWords(lang), for: lang)
                text = joined(app.prefs.fillerWords(for: lang))
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This replaces your list.")
        }
    }

    private func show(_ lang: Lang) {
        shown = lang
        text = joined(app.prefs.fillerWords(for: lang))
    }

    private func save(_ text: String, for lang: Lang) {
        let words = Self.words(text)
        if words != app.prefs.fillerWords(for: lang) { app.prefs.setFillerWords(words, for: lang) }
    }

    static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
