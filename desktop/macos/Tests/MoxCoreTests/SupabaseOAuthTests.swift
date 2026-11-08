import XCTest
@testable import MoxCore

final class SupabaseOAuthTests: XCTestCase {
    private let client = OAuthClient(id: "client-id", secret: "client-secret",
                                     redirectURI: "http://localhost:53682/callback")

    func testPKCEMatchesTheRFC7636Example() {
        // RFC 7636, appendix B.
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        XCTAssertEqual(pkce.challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testGeneratedVerifiersAreLongRandomAndURLSafe() {
        let first = PKCE.generate(), second = PKCE.generate()
        XCTAssertNotEqual(first.verifier, second.verifier)
        XCTAssertGreaterThanOrEqual(first.verifier.count, 43)
        XCTAssertNil(first.verifier.rangeOfCharacter(from: CharacterSet(charactersIn: "+/=")))
    }

    func testAuthorizationURLCarriesPKCEAndState() throws {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        let url = SupabaseOAuth.authorizationURL(client: client, pkce: pkce, state: "xyz")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(url.host, "api.supabase.com")
        XCTAssertEqual(query["client_id"], "client-id")
        XCTAssertEqual(query["redirect_uri"], "http://localhost:53682/callback")
        XCTAssertEqual(query["response_type"], "code")
        XCTAssertEqual(query["code_challenge"], pkce.challenge)
        XCTAssertEqual(query["code_challenge_method"], "S256")
        XCTAssertEqual(query["state"], "xyz")
    }

    func testExchangeSendsTheCodeVerifierAndClientCredentials() async throws {
        let session = MockURLProtocol.session()
        MockURLProtocol.reply(200, #"{"access_token":"at","refresh_token":"rt","expires_in":86400}"#)
        let pkce = PKCE(verifier: "verifier-123")
        let tokens = try await SupabaseOAuth.exchange(code: "the-code", client: client, pkce: pkce, session: session)
        XCTAssertEqual(tokens, OAuthTokens(accessToken: "at", refreshToken: "rt", expiresIn: 86400))

        let sent = try XCTUnwrap(MockURLProtocol.recorded.last)
        XCTAssertEqual(sent.request.httpMethod, "POST")
        XCTAssertEqual(sent.request.url, SupabaseOAuth.tokenURL)
        let basic = Data("client-id:client-secret".utf8).base64EncodedString()
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "Authorization"), "Basic \(basic)")
        let form = MockURLProtocol.text(sent.body)
        XCTAssertTrue(form.contains("grant_type=authorization_code"))
        XCTAssertTrue(form.contains("code=the-code"))
        XCTAssertTrue(form.contains("code_verifier=verifier-123"))
        XCTAssertTrue(form.contains("redirect_uri=http%3A%2F%2Flocalhost%3A53682%2Fcallback"))
    }

    func testRefreshAndErrors() async throws {
        let session = MockURLProtocol.session()
        MockURLProtocol.reply(200, #"{"access_token":"new","expires_in":3600}"#)
        let tokens = try await SupabaseOAuth.refresh("rt", client: client, session: session)
        XCTAssertEqual(tokens.accessToken, "new")
        XCTAssertNil(tokens.refreshToken)
        let refreshForm = MockURLProtocol.text(MockURLProtocol.recorded.last!.body)
        XCTAssertTrue(refreshForm.contains("grant_type=refresh_token"))

        // What Spike 1 saw without a client secret.
        MockURLProtocol.reply(422, #"{"message":"Required parameter: client_secret"}"#)
        do {
            _ = try await SupabaseOAuth.refresh("rt", client: client, session: session)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? ManagementError, .http(422, "Required parameter: client_secret"))
        }
    }
}
