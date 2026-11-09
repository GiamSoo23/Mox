import XCTest
@testable import MoxCore

final class AppLocationTests: XCTestCase {
    private func offers(_ path: String, isSourceBuild: Bool = false) -> Bool {
        AppLocation.shouldOfferMove(bundlePath: path, home: "/Users/ana", isSourceBuild: isSourceBuild)
    }

    func testOffersFromDownloadsAndTheDesktop() {
        XCTAssertTrue(offers("/Users/ana/Downloads/Mox.app"))
        XCTAssertTrue(offers("/Users/ana/Downloads/macos/Mox.app"))
        XCTAssertTrue(offers("/Users/ana/Desktop/Mox.app"))
    }

    func testOffersFromTheTemporaryCopy() {
        XCTAssertTrue(offers("/private/var/folders/85/T/AppTranslocation/E18A/d/Mox.app"))
    }

    func testStaysQuietInApplications() {
        XCTAssertFalse(offers("/Applications/Mox.app"))
        XCTAssertFalse(offers("/Users/ana/Applications/Mox.app"))
    }

    func testStaysQuietForSourceBuildsAndBareBinaries() {
        XCTAssertFalse(offers("/Users/ana/Desktop/Mox/desktop/macos/Mox.app", isSourceBuild: true))
        XCTAssertFalse(offers("/Users/ana/Downloads/.build/release/Mox"))
    }
}
