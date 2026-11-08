import XCTest
@testable import MoxCore

/// Runs PairingLink against shared/fixtures/pairing/, the same files the
/// pairing page and the Android app test against.
final class PairingLinkTests: XCTestCase {
    private struct Expected: Decodable {
        let version: Int
        let projectUrl: String
        let publishableKey: String
        let email: String
        let password: String
        let desktopName: String?
    }

    private func expected(for link: URL) throws -> Expected {
        let json = link.deletingPathExtension().appendingPathExtension("json")
        return try JSONDecoder().decode(Expected.self, from: Data(contentsOf: json))
    }

    func testParsesEveryValidFixtureExactly() throws {
        let links = try Fixtures.files("pairing/valid", ext: "txt")
        XCTAssertGreaterThanOrEqual(links.count, 6)
        for file in links {
            let parsed = try PairingLink.parse(Fixtures.text(file))
            let want = try expected(for: file)
            XCTAssertEqual(parsed.projectURL, want.projectUrl, file.lastPathComponent)
            XCTAssertEqual(parsed.publishableKey, want.publishableKey, file.lastPathComponent)
            XCTAssertEqual(parsed.email, want.email, file.lastPathComponent)
            XCTAssertEqual(parsed.password, want.password, file.lastPathComponent)
            XCTAssertEqual(parsed.desktopName, want.desktopName, file.lastPathComponent)
        }
    }

    func testRefusesEveryInvalidFixture() throws {
        let links = try Fixtures.files("pairing/invalid", ext: "txt")
        XCTAssertGreaterThanOrEqual(links.count, 12)
        for file in links {
            XCTAssertThrowsError(try PairingLink.parse(Fixtures.text(file)), file.lastPathComponent)
        }
    }

    func testEncodesExactlyLikeTheFixtures() throws {
        // These fixtures are in canonical form (no extra keys, no trailing slash).
        for name in ["basic", "plus-sign-in-email", "unicode-desktop-name", "no-desktop-name"] {
            let file = Fixtures.root.appendingPathComponent("pairing/valid/\(name).txt")
            let want = try expected(for: file)
            let link = PairingLink(projectURL: want.projectUrl, publishableKey: want.publishableKey,
                                   email: want.email, password: want.password, desktopName: want.desktopName)
            XCTAssertEqual(link.url(), try Fixtures.text(file), name)
        }
    }

    func testRoundTripsAndKeepsAPlusSign() throws {
        let link = PairingLink(projectURL: "https://abc.supabase.co/", publishableKey: "sb_publishable_x",
                               email: "mox+desk@example.com", password: "a+b c&d=e#f%g/h?i0123",
                               desktopName: "Gregory’s MacBook")
        XCTAssertEqual(try PairingLink.parse(link.url()), link)
        XCTAssertEqual(link.projectURL, "https://abc.supabase.co", "trailing slash removed")
    }

    func testSpecificErrors() throws {
        let secret = Fixtures.root.appendingPathComponent("pairing/invalid/secret-key.txt")
        XCTAssertThrowsError(try PairingLink.parse(Fixtures.text(secret))) {
            XCTAssertEqual($0 as? PairingError, .secretKey)
        }
        let future = Fixtures.root.appendingPathComponent("pairing/invalid/future-version.txt")
        XCTAssertThrowsError(try PairingLink.parse(Fixtures.text(future))) {
            XCTAssertEqual($0 as? PairingError, .unsupportedVersion)
        }
    }
}
