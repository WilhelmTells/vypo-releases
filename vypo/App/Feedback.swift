import AppKit

/// “Send Feedback…”: a new mail to the maintainer with the version of vypo, macOS and the Mac model, and nothing
/// else: no diagnostics, no dictated text, nothing from the history. Whoever wants adds the diagnostics with
/// Settings → About → Copy Diagnostics… by hand.
enum Feedback {
    static let address = "contact.wilhelmtells@proton.me"
    static let subject = "vypo feedback"

    /// The `mailto:` link. The first lines are empty, for writing.
    static func mailURL(version: String, macOS: String, macModel: String) -> URL {
        let body = """


            –
            vypo \(version), macOS \(macOS), \(macModel)
            \(String(localized: "To add diagnostics, choose Settings → About → Copy Diagnostics… in vypo and paste them here."))
            """
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [URLQueryItem(name: "subject", value: subject), URLQueryItem(name: "body", value: body)]
        return components.url!
    }

    @MainActor
    static func send() {
        let url = mailURL(version: Updates.versionText,
                          macOS: ProcessInfo.processInfo.operatingSystemVersionString,
                          macModel: Diagnostics.sysctlString("hw.model"))
        guard NSWorkspace.shared.urlForApplication(toOpen: url) != nil else {
            noMailApp()
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// No mail app set up: the address, to copy.
    @MainActor
    private static func noMailApp() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = String(localized: "No mail app is set up")
        alert.informativeText = String(localized: "Write to \(address) instead.")
        alert.addButton(withTitle: String(localized: "Copy Address"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(address, forType: .string)
        }
    }
}
