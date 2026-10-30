import SwiftUI

/// Rename or delete a glossary set, or create one (§23.9).
struct SetSheet: View {
    enum Mode: Identifiable {
        case new
        case edit(GlossarySet)

        var id: String {
            switch self {
            case .new: "new"
            case .edit(let s): s.id.uuidString
            }
        }
    }

    let mode: Mode
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var confirmDelete = false

    private var current: GlossarySet? { if case .edit(let s) = mode { s } else { nil } }
    private var isGeneral: Bool { current?.isGeneral == true }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Form {
                TextField("Name", text: $name)
                    .disabled(isGeneral)
            }
            .formStyle(.grouped)
            HStack {
                if let current, !current.isGeneral {
                    Button("Delete set", role: .destructive) { confirmDelete = true }
                        .foregroundStyle(Color.vyDanger)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    if let current { app.glossary.rename(current.id, to: name) } else { app.glossary.addSet(named: name) }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isGeneral)
            }
            .padding([.horizontal, .bottom], Space.s5)
        }
        .frame(width: 400)
        .onAppear { name = current?.name ?? "" }
        .alert(current.map { "Delete “\($0.name)” and its \(app.glossary.count(in: $0)) terms?" } ?? "", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                if let current { app.glossary.deleteSet(current.id) }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// “Found {n} terms in {file name}” (§23.10).
struct ImportTermsSheet: View {
    struct Result: Identifiable {
        var fileName: String
        var found: [TermExtractor.Found]
        var id: String { fileName }
    }

    private enum Target: Hashable {
        case existing(UUID)
        case new
    }

    let result: Result
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var checked: Set<String> = []
    @State private var target: Target = .existing(GlossarySet.generalID)
    @State private var newSetName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Found \(result.found.count) terms in \(result.fileName)")
                .font(.title3.weight(.semibold))
            List(result.found) { item in
                Toggle(isOn: Binding(get: { checked.contains(item.term) },
                                     set: { if $0 { checked.insert(item.term) } else { checked.remove(item.term) } })) {
                    HStack {
                        Text(item.term)
                        Spacer()
                        Text("\(item.count)×").foregroundStyle(Color.vyLabelSecondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
            .frame(height: 260)
            .listStyle(.bordered)
            HStack {
                Picker("Set", selection: $target) {
                    ForEach(app.glossary.sets) { Text($0.name).tag(Target.existing($0.id)) }
                    Text("New set…").tag(Target.new)
                }
                .pickerStyle(.menu)
                .fixedSize()
                if target == .new {
                    TextField("Name", text: $newSetName)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add \(checked.count) terms") { add() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(checked.isEmpty || (target == .new && newSetName.trimmingCharacters(in: .whitespaces).isEmpty))
            }
        }
        .padding(Space.s5)
        .frame(width: 460)
        .onAppear {
            checked = Set(result.found.filter { $0.count >= 3 }.map(\.term))
            newSetName = (result.fileName as NSString).deletingPathExtension
        }
    }

    private func add() {
        let setID: UUID
        switch target {
        case .existing(let id): setID = id
        case .new: setID = app.glossary.addSet(named: newSetName).id
        }
        var added = 0
        for item in result.found where checked.contains(item.term) {
            if app.glossary.add(term: item.term, scope: .all, setID: setID) { added += 1 }
        }
        // Bookworm: a document import that took at least one term.
        if added > 0 { app.achievementReached(.documentImport) }
        dismiss()
    }
}
