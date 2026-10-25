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
        @Bindable var prefs = app.prefs
        let suggestions = app.glossary.suggestions
        let terms = filtered
        Form {
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
                            Badge(text: "\(app.glossary.set(for: entry).name)")
                        }
                        Button("Edit") { editing = .edit(entry) }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.vyAccent)
                    }
                }
            } header: {
                PaneSectionHeader(pane: .words, title: "Glossary") {
                    toolbar
                    ForEach(suggestions) { s in
                        SuggestionRow(suggestion: s, onAdd: { app.glossary.accept(s) }, onIgnore: { app.glossary.ignore(s) })
                    }
                }
                .textCase(nil)
            } footer: {
                Text("vypo always writes a term exactly like this. Tip: select a word in any app and press \(shortcutText) to add it.")
            }

            Section {
                Toggle(isOn: $prefs.preferGlossaryTerms) {
                    RowLabel(title: "Listen for your terms",
                             description: "vypo recognizes your terms while transcribing, even unusual names.")
                }
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
            } header: {
                Text("How the glossary helps")
            } footer: {
                Text("If a term keeps coming out wrong, edit it and add what vypo wrote instead under “Sounds like”.")
            }

            ReplacementsSection()

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
                    RowLabel(title: "Remove filler words", description: "um, uh, äh, ähm …")
                }
            } header: {
                Text("Filler words")
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editing) { mode in
            TermSheet(mode: mode).environment(app)
        }
        .sheet(isPresented: $editingFillers) {
            FillerWordsSheet().environment(app)
        }
        .sheet(isPresented: $managingSets) {
            SetsSheet().environment(app)
        }
        .sheet(item: $importResult) { result in
            ImportTermsSheet(result: result).environment(app)
        }
        .alert(nothingFound.map { "No new terms found in \($0)." } ?? "", isPresented: Binding(get: { nothingFound != nil }, set: { if !$0 { nothingFound = nil } })) {
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
                    ForEach(app.glossary.sets) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            Button { editing = .add } label: { Label("Add term", systemImage: "plus") }
            Menu {
                Button("Import from document…") { importDocument() }
                Divider()
                Button("Import glossary…") { importFile() }
                Button("Export glossary…") { exportFile() }
                Divider()
                Button("Manage sets…") { managingSets = true }
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
        let list = e.soundsLike.map { "“\($0)”" }.joined(separator: ", ")
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
        VStack(alignment: .leading, spacing: Space.s4) {
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
                    ForEach(app.glossary.sets) { Text($0.name).tag($0.id) }
                }
                .pickerStyle(.menu)
            }
            .formStyle(.grouped)
            HStack {
                if case .edit(let e) = mode {
                    Button("Delete", role: .destructive) {
                        app.glossary.delete(e.id)
                        dismiss()
                    }
                    .foregroundStyle(Color.vyDanger)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(term.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding([.horizontal, .bottom], Space.s5)
        }
        .frame(width: 440)
        .onAppear {
            if case .edit(let e) = mode {
                term = e.term
                soundsLike = e.soundsLike.joined(separator: ", ")
                scope = e.scope
                setID = e.setID ?? GlossarySet.generalID
            }
        }
    }

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

    var body: some View {
        Section {
            ForEach(app.replacements.items) { r in
                HStack(spacing: Space.s3) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(r.summary)").foregroundStyle(Color.vyLabel)
                        Text("becomes \(Replacements.display(r.output))")
                            .font(.callout).foregroundStyle(Color.vyLabelSecondary)
                        if let note = r.inSentence.listNote {
                            Text(note).font(.caption).foregroundStyle(Color.vyLabelSecondary)
                        }
                    }
                    Spacer()
                    Toggle("\(r.summary)", isOn: Binding(get: { r.enabled }, set: { app.replacements.setEnabled(r.id, $0) }))
                        .labelsHidden()
                    Button("Edit") { editing = r }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.vyAccent)
                }
            }
            HStack {
                Button("Add replacement") { editing = Replacement(spoken: [], output: "") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.vyAccent)
                Spacer()
                Button("Restore default entries") { app.replacements.restoreDefaults() }
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(Color.vyLabelSecondary)
            }
        } header: {
            Text("Replacements")
        } footer: {
            Text("Say the phrase on the left and vypo writes the right side. Said on its own, an entry works in every app; in a sentence, as set for the entry.")
        }
        .sheet(item: $editing) { r in
            ReplacementSheet(replacement: r).environment(app)
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

    private var isNew: Bool { !app.replacements.items.contains { $0.id == replacement.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Form {
                Section {
                    TextField("Spoken", text: $spoken, prompt: Text("e.g. slash, Schrägstrich"))
                    TextField("Output", text: $output)
                } footer: {
                    Text("Separate spellings with commas.")
                }
                Section {
                    Picker("In a sentence", selection: $inSentence) {
                        ForEach(SentenceScope.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                } footer: {
                    Text("\(inSentence.explanation)")
                }
            }
            .formStyle(.grouped)
            HStack {
                if !isNew {
                    Button("Delete", role: .destructive) {
                        app.replacements.delete(replacement.id)
                        dismiss()
                    }
                    .foregroundStyle(Color.vyDanger)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    var r = replacement
                    r.spoken = Replacements.variants(spoken)
                    r.output = output.replacingOccurrences(of: "↵", with: "\n")
                    r.inSentence = inSentence
                    app.replacements.upsert(r)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(Replacements.variants(spoken).isEmpty)
            }
            .padding([.horizontal, .bottom], Space.s5)
        }
        .frame(width: 420)
        .onAppear {
            spoken = replacement.spokenText
            output = Replacements.display(replacement.output)
            inSentence = replacement.inSentence
        }
    }
}

/// A suggestion above the term list: a word you corrected in History.
private struct SuggestionRow: View {
    var suggestion: GlossarySuggestion
    var onAdd: () -> Void
    var onIgnore: () -> Void

    var body: some View {
        HStack(spacing: Space.s3) {
            IconTile(symbol: "sparkles", tint: .vyAccent)
            RowLabel(title: "\(suggestion.term)", description: "Suggested: you corrected “\(suggestion.heard)” \(suggestion.count)×")
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

/// Glossary → ⋯ → Manage sets: turn sets on and off, rename, delete, add.
private struct SetsSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var editingSet: SetSheet.Mode?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Sets").font(.title3.weight(.semibold))
            Text("Group terms, e.g. per project, and turn a group off when you don’t need it.")
                .font(.callout)
                .foregroundStyle(Color.vyLabelSecondary)
            Form {
                ForEach(app.glossary.sets) { set in
                    HStack(spacing: Space.s3) {
                        RowLabel(title: "\(set.name)", description: "\(app.glossary.count(in: set)) terms")
                        Spacer()
                        Toggle(set.name, isOn: Binding(get: { set.isActive }, set: { app.glossary.setActive(set.id, $0) }))
                            .labelsHidden()
                        Button("Edit") { editingSet = .edit(set) }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.vyAccent)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 160)
            HStack {
                Button("New set…") { editingSet = .new }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.s5)
        .frame(width: 420)
        .sheet(item: $editingSet) { mode in
            SetSheet(mode: mode).environment(app)
        }
    }
}

/// One word per line, per language, with “Reset to defaults” (§23.2).
struct FillerWordsSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var english = ""
    @State private var german = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            let langs = app.prefs.languages.filter(\.hasExtras)
            if langs.isEmpty {
                Text("Filler words are removed in English and German.")
                    .foregroundStyle(Color.vyLabelSecondary)
            } else {
                HStack(alignment: .top, spacing: Space.s4) {
                    if langs.contains(.en) { column("English", $english) }
                    if langs.contains(.de) { column("German", $german) }
                }
            }
            HStack {
                Button("Reset to defaults") {
                    english = FillerRemover.defaultWords(.en).joined(separator: "\n")
                    german = FillerRemover.defaultWords(.de).joined(separator: "\n")
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    app.prefs.setFillerWords(Self.words(english), for: .en)
                    app.prefs.setFillerWords(Self.words(german), for: .de)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.s5)
        .frame(width: 440)
        .onAppear {
            english = app.prefs.fillerWords(for: .en).joined(separator: "\n")
            german = app.prefs.fillerWords(for: .de).joined(separator: "\n")
        }
    }

    private func column(_ title: LocalizedStringKey, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(title).font(.headline)
            TextEditor(text: text)
                .font(.body)
                .frame(height: 180)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: Radius.sm).fill(Color.vyBgGroup))
                .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Color.vyBorderControl, lineWidth: 1))
                .accessibilityLabel(Text(title))
        }
    }

    static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
