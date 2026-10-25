import XCTest
@testable import vypo

/// THIRD_PARTY_NOTICES.md is the one list of what vypo is built on. The app bundles that very file; these
/// tests keep it complete: a Swift package added to project.yml (Sparkle, say) fails here until it has an entry.
final class NoticesTests: XCTestCase {
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func notices() throws -> Notices {
        let text = try String(contentsOf: Self.repoRoot.appendingPathComponent("THIRD_PARTY_NOTICES.md"), encoding: .utf8)
        return Notices(markdown: text)
    }

    /// The keys under `packages:` in project.yml.
    private func packages() throws -> [String] {
        let yml = try String(contentsOf: Self.repoRoot.appendingPathComponent("project.yml"), encoding: .utf8)
        var found: [String] = []
        var inPackages = false
        for line in yml.components(separatedBy: "\n") {
            if line == "packages:" { inPackages = true; continue }
            guard inPackages else { continue }
            if let first = line.first, first != " " { break }
            if line.hasPrefix("  "), !line.hasPrefix("   "), line.hasSuffix(":") {
                found.append(String(line.dropFirst(2).dropLast()))
            }
        }
        return found
    }

    func testEveryPackageHasAnEntry() throws {
        let packages = try packages()
        XCTAssertFalse(packages.isEmpty, "project.yml: no packages found, the test's reading is broken")
        let listed = Set(try notices().components.compactMap(\.package))
        for p in packages {
            XCTAssertTrue(listed.contains(p), "Swift package \(p) has no entry in THIRD_PARTY_NOTICES.md (needs a `- Package: \(p)` line)")
        }
    }

    func testEveryEntryNamesAuthorAndLicense() throws {
        let notices = try notices()
        XCTAssertGreaterThanOrEqual(notices.components.count, 10)
        for c in notices.components {
            XCTAssertFalse(c.author.isEmpty, "\(c.name): no Author")
            XCTAssertFalse(c.licenseName.isEmpty, "\(c.name): no License")
            XCTAssertNotNil(c.licenseURL, "\(c.name): the License needs a link")
        }
    }

    func testTheModelChainAndTheLicenseTextsAreThere() throws {
        let notices = try notices()
        let names = notices.components.map(\.name)
        XCTAssertTrue(names.contains("Parakeet Ultra"))
        XCTAssertTrue(names.contains("Parakeet CTC 110M"))
        let file = try String(contentsOf: Self.repoRoot.appendingPathComponent("THIRD_PARTY_NOTICES.md"), encoding: .utf8)
        for needle in ["moondream/parakeet-ultra", "nvidia/parakeet-tdt-0.6b-v3", "FluidInference/parakeet-ultra-coreml",
                       "Apache Commons Codec", "Sindre Sorhus"] {
            XCTAssertTrue(file.contains(needle), needle)
        }
        let texts = notices.licenseTexts.map(\.text).joined(separator: "\n")
        XCTAssertTrue(texts.contains("Apache License"))
        XCTAssertTrue(texts.contains("Permission is hereby granted"))
        XCTAssertTrue(texts.contains("Redistributions in binary form must reproduce"))
    }

    func testTheAppBundlesTheSameFile() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md"), "not bundled")
        let bundled = try String(contentsOf: url, encoding: .utf8)
        let repo = try String(contentsOf: Self.repoRoot.appendingPathComponent("THIRD_PARTY_NOTICES.md"), encoding: .utf8)
        XCTAssertEqual(bundled, repo)
        XCTAssertNotNil(Notices.bundled())
    }

    func testSparkleAndWhatItBringsAreListed() throws {
        let names = try notices().components.map(\.name)
        for n in ["Sparkle", "bsdiff and bspatch", "sais-lite", "ed25519 (portable C implementation)", "SUSignatureVerifier"] {
            XCTAssertTrue(names.contains(n), n)
        }
        let texts = try notices().licenseTexts.map(\.text).joined(separator: "\n")
        XCTAssertTrue(texts.contains("Colin Percival"))
        XCTAssertTrue(texts.contains("Orson Peters"))
    }
}

/// “Send Feedback…” writes only the versions into the mail.
final class FeedbackTests: XCTestCase {
    func testTheMailHasTheAddressSubjectAndOnlyTheVersions() throws {
        let url = Feedback.mailURL(version: "0.2.0 (2)", macOS: "Version 26.0", macModel: "Mac14,5")
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.scheme, "mailto")
        XCTAssertEqual(parts.path, "contact.wilhelmtells@proton.me")
        XCTAssertEqual(parts.queryItems?.first { $0.name == "subject" }?.value, "vypo feedback")
        let body = try XCTUnwrap(parts.queryItems?.first { $0.name == "body" }?.value)
        XCTAssertTrue(body.hasPrefix("\n\n"), "empty lines to write in come first")
        XCTAssertTrue(body.contains("vypo 0.2.0 (2) · macOS Version 26.0 · Mac14,5"))
        XCTAssertEqual(body.components(separatedBy: "\n").count, 5, "nothing else is added")
    }
}
