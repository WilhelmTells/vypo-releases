import Foundation

/// What vypo is built on, read from `THIRD_PARTY_NOTICES.md`: the one file that lists it. The repo's copy is
/// bundled as a resource, so the About window and the file can't drift apart. `NoticesTests` checks that
/// every Swift package in `project.yml` has an entry.
struct Notices {
    struct Entry: Equatable {
        var name: String
        var package: String?
        var author: String
        var licenseName: String
        var licenseURL: URL?
    }

    /// The `###` entries under `## Built in` and `## Downloaded models`, in file order.
    let components: [Entry]
    /// The `## License texts` section: a heading line or a fenced block (`mono`) or a paragraph.
    let licenseTexts: [(text: String, kind: TextKind)]

    enum TextKind { case heading, paragraph, mono }

    private static let componentSections: Set<String> = ["Built in", "Downloaded models"]

    init(markdown: String) {
        var components: [Entry] = []
        var texts: [(String, TextKind)] = []
        var section = ""
        var entry: Entry?
        var fenced: [String]?
        var paragraph: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty { texts.append((paragraph.joined(separator: " "), .paragraph)) }
            paragraph = []
        }

        for line in markdown.components(separatedBy: "\n") {
            if fenced != nil {
                if line.hasPrefix("```") {
                    texts.append((fenced!.joined(separator: "\n"), .mono))
                    fenced = nil
                } else {
                    fenced!.append(line)
                }
                continue
            }
            if line.hasPrefix("## ") {
                flushParagraph()
                if let entry { components.append(entry) }
                entry = nil
                section = String(line.dropFirst(3))
            } else if line.hasPrefix("### ") {
                flushParagraph()
                let title = String(line.dropFirst(4))
                if Self.componentSections.contains(section) {
                    if let entry { components.append(entry) }
                    entry = Entry(name: title, package: nil, author: "", licenseName: "", licenseURL: nil)
                } else if section == "License texts" {
                    texts.append((title, .heading))
                }
            } else if line.hasPrefix("```"), section == "License texts" {
                flushParagraph()
                fenced = []
            } else if entry != nil, line.hasPrefix("- ") {
                Self.apply(field: String(line.dropFirst(2)), to: &entry!)
            } else if section == "License texts" {
                if line.trimmingCharacters(in: .whitespaces).isEmpty { flushParagraph() } else { paragraph.append(line) }
            }
        }
        flushParagraph()
        if let entry { components.append(entry) }
        self.components = components
        self.licenseTexts = texts.map { (text: $0.0, kind: $0.1) }
    }

    private static func apply(field: String, to entry: inout Entry) {
        guard let colon = field.firstIndex(of: ":") else { return }
        let key = field[..<colon]
        let value = field[field.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        switch key {
        case "Package": entry.package = value
        case "Author": entry.author = value
        case "License":
            // `[Name](url)`, or two of them joined by “or”: the first one is shown, both are in the file.
            if let open = value.firstIndex(of: "["), let mid = value.range(of: "]("), mid.lowerBound > open,
               let close = value[mid.upperBound...].firstIndex(of: ")") {
                entry.licenseName = String(value[value.index(after: open)..<mid.lowerBound])
                entry.licenseURL = URL(string: String(value[mid.upperBound..<close]))
            } else {
                entry.licenseName = value
            }
        default: break
        }
    }

    /// The copy in the app bundle.
    static func bundled() -> Notices? {
        guard let url = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return Notices(markdown: text)
    }

    static let homepage = URL(string: "https://wilhelmtells.com/vypo")!
}
