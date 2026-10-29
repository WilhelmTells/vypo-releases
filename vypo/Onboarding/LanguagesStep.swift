import SwiftUI

/// Step 4: the languages you dictate in, as tiles. The Mac's language and English are chosen already.
struct LanguagesStep: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showList: Bool
    @State private var order: [Lang] = []

    init(showList: Bool = false) { _showList = State(initialValue: showList) }

    var body: some View {
        let chosen = app.prefs.languages
        let mac = Lang.macLanguage()
        VStack(spacing: 0) {
            OBTitle(title: "Which languages do you dictate in?")
                .padding(.bottom, 24)
            WrapLayout(spacing: 12, lineSpacing: 12) {
                ForEach(chosen) { lang in
                    LanguageTile(lang: lang, isMac: lang == mac)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.95)))
                }
                Button { showList.toggle() } label: { AddTile() }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showList, arrowEdge: .bottom) { LanguageList(order: order) }
                    .accessibilityLabel("Add language")
            }
            .frame(maxWidth: .infinity)
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.2), value: chosen)
            Text("vypo only inserts text in the languages you choose.")
                .font(OBFont.secondary).foregroundStyle(Color.vyLabelSecondary)
                .padding(.top, 20)
        }
        .frame(width: 460)
        .onAppear { if order.isEmpty { order = Self.listOrder(chosen: app.prefs.languages) } }
        .onChange(of: showList) { _, open in if open { order = Self.listOrder(chosen: app.prefs.languages) } }
    }

    /// Chosen languages first, then the rest alphabetically; fixed while the list is open, so a row doesn't jump when ticked.
    static func listOrder(chosen: [Lang]) -> [Lang] {
        chosen + Lang.allCases.filter { !chosen.contains($0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

private struct LanguageTile: View {
    var lang: Lang
    var isMac: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(lang.nativeName).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.vyLabel)
                .lineLimit(1).minimumScaleFactor(0.8)
            if isMac {
                Text("Mac language").font(.system(size: 10)).foregroundStyle(Color.vyLabelSecondary)
            }
        }
        .padding(.horizontal, 6)
        .frame(width: 96, height: 60)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.vyBgGroup))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.vySeparator, lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }
}

private struct AddTile: View {
    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "plus").font(.system(size: 20, weight: .regular)).foregroundStyle(Color.vyLabel)
            Text("Add language").font(.system(size: 10)).foregroundStyle(Color.vyLabelSecondary)
        }
        .frame(width: 104, height: 68)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.vyBgGroup.opacity(0.0001)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.vyLabelTertiary, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// The popover of the “+” tile: a search field and a list of six visible rows.
struct LanguageList: View {
    @Environment(AppState.self) private var app
    var order: [Lang]
    @State private var search = ""

    var body: some View {
        let chosen = app.prefs.languages
        let rows = order.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.nativeName.localizedCaseInsensitiveContains(search) || $0.englishName.localizedCaseInsensitiveContains(search) }
        VStack(spacing: 8) {
            TextField("Search", text: $search).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { lang in
                        let isChosen = chosen.contains(lang)
                        let isLast = chosen == [lang]
                        Button { app.prefs.setChosen(lang, !isChosen) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                                    .opacity(isChosen ? 1 : 0).frame(width: 14)
                                Text(lang.nativeName).font(OBFont.body)
                                Spacer()
                                Text(lang.englishName).font(OBFont.secondary).foregroundStyle(Color.vyLabelSecondary)
                            }
                            .padding(.horizontal, 6).frame(height: 30)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(isLast ? Text("Choose at least one language.") : Text(verbatim: ""))
                        .accessibilityAddTraits(isChosen ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.automatic)
            .frame(height: 180)
        }
        .padding(12)
        .frame(width: 260)
    }
}

/// Lays children out in centred rows that wrap.
struct WrapLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(in: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(in: bounds.width, subviews: subviews) {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func rows(in width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? 0 : spacing
            if rows[rows.count - 1].width + extra + size.width > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let gap = rows[rows.count - 1].indices.isEmpty ? 0 : spacing
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += gap + size.width
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
