import XCTest
@testable import vypo

/// Which states show the pill when it's turned off (Settings → Appearance → Pill).
final class PillVisibilityTests: XCTestCase {
    private static let notices: [PillNotice] = [.termAdded("TikTok"), .copied, .onClipboard, .undone, .collectingDiagnostics]
    private static let modes: [PillMode] = [.collapsed, .ready, .listening, .handsfree, .processing, .add]
        + PillError.allCases.map { .error($0) } + notices.map { .added($0) }

    func testPillOffShowsOnlyWhatNeedsYou() {
        let shown = Self.modes.filter { PillVisibility.isVisible($0, showPill: false) }
        XCTAssertEqual(shown, [.add, .error(.noMicrophone), .error(.micNotAllowed), .error(.noAccessibility),
                               .error(.modelMissing), .error(.globeKeyInUse), .added(.onClipboard),
                               .added(.collectingDiagnostics)])
    }

    func testPillOnShowsEverythingButRest() {
        for mode in Self.modes {
            XCTAssertEqual(PillVisibility.isVisible(mode, showPill: true), mode != .ready && mode != .collapsed, "\(mode)")
        }
    }
}
