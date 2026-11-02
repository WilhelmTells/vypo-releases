import Foundation

/// The places the widget opens: `vypo://stats`, `vypo://stats?stamp=<id>`, `vypo://words?suggestion=<id>`. The scheme
/// comes from `Info.plist`, so the test app's widget opens the test app. Anything else is no link and does nothing.
enum WidgetLink: Equatable, Sendable {
    case stats
    case stamp(String)
    case suggestion(String)

    static var scheme: String { Bundle.main.object(forInfoDictionaryKey: "VYPOURLScheme") as? String ?? "vypo" }

    func url(scheme: String = Self.scheme) -> URL {
        var c = URLComponents()
        c.scheme = scheme
        switch self {
        case .stats:
            c.host = "stats"
        case .stamp(let id):
            c.host = "stats"
            c.queryItems = [URLQueryItem(name: "stamp", value: id)]
        case .suggestion(let id):
            c.host = "words"
            c.queryItems = [URLQueryItem(name: "suggestion", value: id)]
        }
        return c.url ?? URL(fileURLWithPath: "/")
    }

    init?(url: URL, scheme: String = Self.scheme) {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false), c.scheme == scheme, c.path.isEmpty else { return nil }
        let items = c.queryItems ?? []
        let value = items.count == 1 ? items[0].value : nil
        switch (c.host, items.first?.name) {
        case ("stats", nil): self = .stats
        case ("stats", "stamp"):
            guard let value, !value.isEmpty else { return nil }
            self = .stamp(value)
        case ("words", "suggestion"):
            guard let value, !value.isEmpty else { return nil }
            self = .suggestion(value)
        default: return nil
        }
    }
}
