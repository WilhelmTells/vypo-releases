import AppKit
import SwiftUI

/// Settings → History (§13).
struct HistoryPane: View {
    @Environment(AppState.self) private var app
    @State private var search = ""
    @State private var searching = false
    @State private var editing: UUID?
    @State private var draft = ""
    @State private var banner: SuggestionBanner.Content?
    @State private var confirmClear = false
    /// How many of the newest entries show without a search; “Show more” adds another page.
    @State private var shown = Self.page

    static let page = 15

    private var query: String { search.trimmingCharacters(in: .whitespaces) }

    /// Every match while searching, otherwise the newest `shown` entries.
    private var filtered: [HistoryItem] {
        guard !query.isEmpty else { return Array(app.history.items.prefix(shown)) }
        return app.history.items.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    private var hiddenCount: Int { query.isEmpty ? max(0, app.history.items.count - shown) : 0 }

    var body: some View {
        @Bindable var prefs = app.prefs
        // A scroll view, not a Form: a grouped Form boxes every row, so the bubbles can't sit in it.
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s2) {
                PaneHeader(pane: .history)
                    .padding(.horizontal, Space.s3)
                if let banner {
                    SuggestionBanner(content: banner, onAdd: { accept() }, onDismiss: { self.banner = nil })
                        .transition(.opacity)
                }
                // Outside the list: if the field were part of a day group, a search that changes the
                // first day would rebuild it, and the new field would select the text you're typing.
                dayRow(firstTitle, first: true)
                // Lazy: a search can match every entry, and building all bubbles at once made typing stutter.
                LazyVStack(alignment: .leading, spacing: Space.s2) { list }
                    // Bubbles that no longer match fade out and the rest slide into place.
                    .animation(.smooth(duration: 0.3), value: query)
                Text("Fix a text with the pencil. vypo learns from your fixes and suggests glossary terms.")
                    .font(.callout)
                    .foregroundStyle(Color.vyLabelSecondary)
                    .padding(.horizontal, Space.s3)
                    .padding(.top, Space.s1)
                    .padding(.bottom, Space.s5)
                SettingsGroup {
                    SettingsRow("Save history") {
                        Toggle("Save history", isOn: $prefs.saveHistory)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    SettingsRow("Keep for") {
                        Picker("Keep for", selection: $prefs.historyRetention) {
                            Text("7 days").tag(HistoryRetention.days7)
                            Text("30 days").tag(HistoryRetention.days30)
                            Text("Forever").tag(HistoryRetention.forever)
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }
                    SettingsRow("Clear history") {
                        DestructiveButton("Clear history") { confirmClear = true }
                    }
                }
            }
            .frame(maxWidth: 680)
            .padding(.horizontal, Space.s5)
            .padding(.vertical, Space.s5)
            .frame(maxWidth: .infinity)
        }
        .background {
            // ⌘F opens the search.
            Button("Search history") { openSearch() }
                .keyboardShortcut("f")
                .hidden()
        }
        .animation(.easeInOut(duration: Motion.fast), value: banner)
        .onChange(of: prefs.historyRetention) { app.history.prune(prefs.historyRetention) }
        .alert("Clear all history?", isPresented: $confirmClear) {
            Button("Clear", role: .destructive) { app.history.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can’t be undone.")
        }
    }

    /// The first group's day, shown in the row with the search.
    private var firstTitle: String {
        guard let first = filtered.first else { return query.isEmpty ? String(localized: "Today") : "" }
        return Self.dayTitle(first.date)
    }

    /// One group per day, newest first, each dictation in its own bubble. The first group's title
    /// is the search row above.
    @ViewBuilder private var list: some View {
        let groups = Self.byDay(filtered)
        if groups.isEmpty {
            Text(query.isEmpty ? "Nothing dictated yet." : "No matches.")
                .foregroundStyle(Color.vyLabelSecondary)
                .padding(.horizontal, Space.s3)
        }
        ForEach(Array(groups.enumerated()), id: \.element.day) { index, group in
            if index > 0 { dayRow(Self.dayTitle(group.day), first: false) }
            ForEach(group.items) { item in
                HistoryRow(
                    item: item,
                    highlight: query,
                    isEditing: editing == item.id,
                    draft: $draft,
                    onEdit: {
                        draft = item.text
                        editing = item.id
                    },
                    onCancel: { editing = nil },
                    onSave: { save(item) },
                    onDelete: {
                        if editing == item.id { editing = nil }
                        // The bubble fades out and the ones below slide up.
                        withAnimation(.smooth(duration: 0.3)) { app.history.remove(item.id) }
                    }
                )
            }
        }
        if hiddenCount > 0 {
            HStack {
                Button("Show more") { shown += Self.page }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.vyAccent)
                Spacer()
                Text("\(hiddenCount) more")
                    .foregroundStyle(Color.vyLabelSecondary)
            }
            .padding(.horizontal, Space.s4)
        }
    }

    /// The day's title; the first one carries the search at its end.
    private func dayRow(_ title: String, first: Bool) -> some View {
        HStack(spacing: Space.s3) {
            Text(title)
                .textCase(.uppercase)
                .font(.vyTier)
                .tracking(0.6)
                .foregroundStyle(Color.vyLabelSecondary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Space.s3)
            if first { searchControl }
        }
        .frame(minHeight: 28)
        .padding(.leading, Space.s3)
        .padding(.top, first ? 0 : Space.s3)
    }

    /// A magnifying glass that opens into a short search field; it closes again when empty and unfocused.
    /// The field grows to the left out of the glass and shrinks back into it, never past it.
    private var searchControl: some View {
        ZStack(alignment: .trailing) {
            if searching {
                SearchField(prompt: "Search history", text: $search, autofocus: true) { focused in
                    if !focused && query.isEmpty { closeSearch() }
                }
                .onExitCommand { closeSearch() }
                .transition(.opacity)
            } else {
                Button { openSearch() } label: {
                    Label("Search history", systemImage: "magnifyingglass")
                        .labelStyle(.iconOnly)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.vyAccent)
                .help("Search history (⌘F)")
                .transition(.opacity)
            }
        }
        .frame(width: searching ? 220 : 22, alignment: .trailing)
        .clipped()
    }

    private func openSearch() {
        withAnimation(.smooth(duration: 0.22)) { searching = true }
    }

    private func closeSearch() {
        search = ""
        withAnimation(.smooth(duration: 0.38)) { searching = false }
    }

    /// Items grouped by day, keeping their order.
    static func byDay(_ items: [HistoryItem], calendar: Calendar = .current) -> [(day: Date, items: [HistoryItem])] {
        var groups: [(day: Date, items: [HistoryItem])] = []
        for item in items {
            let day = calendar.startOfDay(for: item.date)
            if groups.last?.day == day { groups[groups.count - 1].items.append(item) } else { groups.append((day, [item])) }
        }
        return groups
    }

    /// "Today", "Yesterday", else "21 October" (with the year when it isn't this year).
    static func dayTitle(_ day: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(day) { return String(localized: "Today") }
        if calendar.isDateInYesterday(day) { return String(localized: "Yesterday") }
        let sameYear = calendar.isDate(day, equalTo: Date(), toGranularity: .year)
        let style = Date.FormatStyle.dateTime.day().month(.wide).locale(Formatting.uiLocale)
        return day.formatted(sameYear ? style : style.year())
    }

    /// Saves the fix and turns word substitutions into glossary suggestions (§13).
    private func save(_ item: HistoryItem) {
        let old = item.text
        let new = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        editing = nil
        guard new != old, !new.isEmpty else { return }
        app.history.update(item.id) { $0.text = new }
        var latest: GlossarySuggestion?
        for sub in WordDiff.suggestionCandidates(from: old, to: new) where !app.glossary.contains(term: sub.term) {
            latest = app.glossary.suggest(heard: sub.heard, term: sub.term, scope: GlossaryScope(item.language))
        }
        if let latest { banner = .offer(latest) }
    }

    private func accept() {
        guard case .offer(let s) = banner else { return }
        app.glossary.accept(s)
        banner = .added(s.term)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if banner == .added(s.term) { banner = nil }
        }
    }
}

/// One history entry as a bubble. Hover, the icons and the copied checkmark live here, so they
/// redraw only this row instead of the whole list.
struct HistoryRow: View {
    let item: HistoryItem
    /// The search; its matches are marked, and the whole text shows.
    var highlight = ""
    /// Snapshots only: show the card as if the pointer were on it.
    var previewHovered = false
    let isEditing: Bool
    @Binding var draft: String
    let onEdit: () -> Void
    let onCancel: () -> Void
    let onSave: () -> Void
    let onDelete: () -> Void
    @State private var hovered = false
    @State private var copied = false

    private var meta: String {
        [item.date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Formatting.uiLocale)),
         item.appName, item.language.code].compactMap { $0 }.joined(separator: " · ")
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.md + 2, style: .continuous) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(spacing: Space.s3) {
                Text(meta)
                    .font(.callout)
                    .foregroundStyle(Color.vyLabelSecondary)
                Spacer(minLength: Space.s2)
                if !isEditing {
                    actions
                        .opacity(hovered || copied ? 1 : 0)
                }
            }
            .frame(minHeight: 18)
            if isEditing {
                TextEditor(text: $draft)
                    .font(.body)
                    .frame(minHeight: 54)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: Radius.sm).fill(Color.vyBgWindow))
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Color.vyBorderControl, lineWidth: 1))
                HStack {
                    Spacer()
                    Button("Cancel", action: onCancel)
                    Button("Save", action: onSave)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.top, Space.s1)
            } else {
                Text(Self.marked(item.text, highlight))
                    .font(.body)
                    .fontWeight(.regular)
                    .foregroundStyle(Color.vyLabel)
                    .lineLimit(highlight.isEmpty ? 4 : nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Space.s3)
        .padding(.horizontal, Space.s4)
        // The card and its hover sit behind the content: a fill on top would swallow the clicks on the icons.
        .softCard(hovered: hovered && !isEditing)
        .overlay {
            if isEditing { shape.strokeBorder(Color.vyAccent, lineWidth: 1).allowsHitTesting(false) }
        }
        .onHover { hovered = $0 }
        .onAppear { if previewHovered { hovered = true } }
        .animation(.easeInOut(duration: Motion.fast), value: hovered)
        .contextMenu {
            Button("Copy", action: copy)
            Button("Edit", action: onEdit)
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    /// `text` with every case-insensitive match of `query` on a pastel orange background.
    static func marked(_ text: String, _ query: String) -> AttributedString {
        var result = AttributedString(text)
        guard !query.isEmpty else { return result }
        var start = result.startIndex
        while start < result.endIndex,
              let range = result[start...].range(of: query, options: [.caseInsensitive], locale: Formatting.uiLocale) {
            result[range].backgroundColor = Color.vySearchHighlight
            start = range.upperBound
        }
        return result
    }

    /// Copy, edit and delete, shown on hover.
    private var actions: some View {
        HStack(spacing: Space.s3) {
            Button(action: copy) {
                Label("Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .labelStyle(.iconOnly)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 18)
            }
            .help("Copy")
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
                    .labelStyle(.iconOnly)
                    .frame(width: 18)
            }
            .help("Edit")
            Button(action: onDelete) {
                Label("Delete", systemImage: "trash")
                    .labelStyle(.iconOnly)
                    .frame(width: 18)
            }
            .help("Delete")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.vyAccent)
    }

    /// Copies the text and shows a checkmark for a moment.
    private func copy() {
        Paster.copy(item.text)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
    }
}

/// Rows in a rounded group with separators, like a section of a grouped Form.
private struct SettingsGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { Divider().padding(.horizontal, 10) }
                    row
                        .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: Radius.sm + 2).fill(.quaternary))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm + 2).strokeBorder(Color.vySeparator, lineWidth: 0.5))
    }
}

/// A label on the left, its control on the right (the control's own label is hidden).
private struct SettingsRow<Control: View>: View {
    var title: LocalizedStringKey
    @ViewBuilder var control: Control

    init(_ title: LocalizedStringKey, @ViewBuilder control: () -> Control) {
        self.title = title
        self.control = control()
    }

    var body: some View {
        HStack {
            Text(title).foregroundStyle(Color.vyLabel)
            Spacer(minLength: Space.s3)
            control.labelsHidden()
        }
    }
}

/// A rounded search field with a magnifying glass. The prompt hides while the field has focus.
struct SearchField: View {
    var prompt: LocalizedStringKey
    @Binding var text: String
    var autofocus = false
    var onFocusChange: (Bool) -> Void = { _ in }
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Color.vyAccent)
                .accessibilityHidden(true)
            TextField(text: $text) { Text(focused ? "" : prompt) }
                .textFieldStyle(.plain)
                .foregroundStyle(Color.vyLabel)
                .focused($focused)
                .accessibilityLabel(Text(prompt))
                .onAppear { if autofocus { DispatchQueue.main.async { focused = true } } }
                .onChange(of: focused) {
                    onFocusChange(focused)
                    if focused { ClickOutside.start() } else { ClickOutside.stop() }
                }
                .onDisappear { ClickOutside.stop() }
        }
        .padding(.horizontal, Space.s2)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: Radius.sm).fill(Color.vyBgGroup))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Color.vySeparator, lineWidth: 0.5))
        .textCase(nil)
    }
}

/// A click outside the focused text field ends editing. AppKit keeps the field focused when the
/// click lands on something that can't take focus, such as the pane's background or a bubble.
@MainActor
private enum ClickOutside {
    private static var monitor: Any?

    static func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            guard let window = event.window, let editor = window.firstResponder as? NSTextView, editor.isFieldEditor,
                  let content = window.contentView else { return event }
            let hit = content.hitTest(content.convert(event.locationInWindow, from: nil))
            let field = editor.delegate as? NSView
            if let hit, hit.isDescendant(of: editor) || field.map(hit.isDescendant(of:)) == true { return event }
            // After the click is handled, so a button under it still gets it.
            DispatchQueue.main.async { window.makeFirstResponder(nil) }
            return event
        }
    }

    static func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
