import XCTest
@testable import MoxCore

final class OAuthLoopbackTests: XCTestCase {
    func testReadsTheCodeWhenTheStateMatches() {
        XCTAssertEqual(OAuthCallback.parse(requestLine: "GET /callback?code=abc123&state=s1 HTTP/1.1",
                                           expectedState: "s1"), .code("abc123"))
    }

    func testRefusesAnotherState() {
        guard case .denied = OAuthCallback.parse(requestLine: "GET /callback?code=abc&state=evil HTTP/1.1",
                                                 expectedState: "s1") else { return XCTFail("accepted") }
    }

    func testReportsWhenThePersonDeclines() {
        let line = "GET /callback?error=access_denied&error_description=User%20denied&state=s1 HTTP/1.1"
        XCTAssertEqual(OAuthCallback.parse(requestLine: line, expectedState: "s1"), .denied("User denied"))
    }

    func testIgnoresOtherRequests() {
        XCTAssertEqual(OAuthCallback.parse(requestLine: "GET /favicon.ico HTTP/1.1", expectedState: "s1"),
                       .notCallback)
        XCTAssertEqual(OAuthCallback.parse(requestLine: "POST /callback?code=a&state=s1 HTTP/1.1",
                                           expectedState: "s1"), .notCallback)
        XCTAssertEqual(OAuthCallback.parse(requestLine: "", expectedState: "s1"), .notCallback)
    }

    func testAMissingCodeIsAnError() {
        guard case .denied = OAuthCallback.parse(requestLine: "GET /callback?state=s1 HTTP/1.1",
                                                 expectedState: "s1") else { return XCTFail("accepted") }
    }

    func testThePageEscapesTheMessage() {
        XCTAssertTrue(OAuthLoopbackServer.html("<script>").contains("&lt;script&gt;"))
    }

    /// The real listener, on the real port: what the browser does at the end.
    func testTheServerReturnsTheCodeFromTheBrowser() async throws {
        let server = OAuthLoopbackServer(expectedState: "s1")
        let code = Task { try await server.waitForCode() }
        try await Task.sleep(nanoseconds: 300_000_000)
        let url = URL(string: "http://127.0.0.1:\(OAuthLoopbackServer.port)/callback?code=xyz&state=s1")!
        let (data, _) = try await URLSession.shared.data(from: url)
        XCTAssertTrue(String(bytes: data, encoding: .utf8)?.contains("Signed in") ?? false)
        let received = try await code.value
        XCTAssertEqual(received, "xyz")
    }

    func testTheMoxClientNeedsASecret() {
        XCTAssertNil(OAuthClient.mox(secret: nil))
        XCTAssertNil(OAuthClient.mox(secret: ""))
        XCTAssertEqual(OAuthClient.mox(secret: "s")?.redirectURI, "http://localhost:53682/callback")
    }
}
