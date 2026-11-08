import XCTest
@testable import MoxCore

final class MoxSettingsTests: XCTestCase {
    func testThePairingLinkCarriesTheSameSettings() throws {
        let settings = MoxSettings(projectURL: try XCTUnwrap(URL(string: "https://abc.supabase.co")),
                                   publishableKey: "sb_publishable_x", email: "mox+1@mox.invalid",
                                   password: "correct-horse-battery-staple-42")
        let link = settings.pairingLink(desktopName: "Gregory’s MacBook")
        XCTAssertTrue(link.url().hasPrefix(PairingLink.defaultPageURL + "#v=1&"))
        let parsed = try PairingLink.parse(link.url())
        XCTAssertEqual(parsed.projectURL, "https://abc.supabase.co")
        XCTAssertEqual(parsed.email, "mox+1@mox.invalid")
        XCTAssertEqual(parsed.password, settings.password)
        XCTAssertEqual(parsed.desktopName, "Gregory’s MacBook")
    }
}
