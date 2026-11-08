import CryptoKit
import Foundation

/// "Sign in with Supabase" for the setup wizard (#22): OAuth 2 with PKCE
/// against the Supabase Management API. Spike 1 showed the token exchange
/// requires the client secret as well, so official builds carry it; builds
/// without it use a personal access token instead.
public enum SupabaseOAuth {
    public static let authorizeURL = URL(string: "https://api.supabase.com/v1/oauth/authorize")!
    public static let tokenURL = URL(string: "https://api.supabase.com/v1/oauth/token")!

    /// The page the browser opens; `state` must come back unchanged.
    public static func authorizationURL(client: OAuthClient, pkce: PKCE, state: String) -> URL {
        var comps = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: client.id),
            URLQueryItem(name: "redirect_uri", value: client.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]
        return comps.url!
    }

    public static func exchange(code: String, client: OAuthClient, pkce: PKCE,
                                session: URLSession = .shared) async throws -> OAuthTokens {
        try await requestTokens([
            "grant_type": "authorization_code", "code": code,
            "redirect_uri": client.redirectURI, "code_verifier": pkce.verifier
        ], client: client, session: session)
    }

    public static func refresh(_ refreshToken: String, client: OAuthClient,
                               session: URLSession = .shared) async throws -> OAuthTokens {
        try await requestTokens(["grant_type": "refresh_token", "refresh_token": refreshToken],
                                client: client, session: session)
    }

    private static func requestTokens(_ form: [String: String], client: OAuthClient,
                                      session: URLSession) async throws -> OAuthTokens {
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let basic = Data("\(client.id):\(client.secret)".utf8).base64EncodedString()
        req.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        req.httpBody = formEncode(form).data(using: .utf8)
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw ManagementError.from(status: status, body: data) }
        return try JSONDecoder().decode(OAuthTokens.self, from: data)
    }

    static func formEncode(_ form: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return form.keys.sorted().map { key in
            let value = form[key]!.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            return "\(key)=\(value)"
        }.joined(separator: "&")
    }
}

/// An OAuth app registered with Supabase (Organization settings → OAuth Apps).
public struct OAuthClient: Equatable {
    public let id: String
    public let secret: String
    public let redirectURI: String

    public init(id: String, secret: String, redirectURI: String) {
        self.id = id
        self.secret = secret
        self.redirectURI = redirectURI
    }
}

/// A PKCE verifier and its S256 challenge (RFC 7636).
public struct PKCE: Equatable {
    public let verifier: String
    public let challenge: String

    public init(verifier: String) {
        self.verifier = verifier
        self.challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    /// A fresh random verifier (64 bytes of randomness, base64url).
    public static func generate() -> PKCE {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return PKCE(verifier: base64URL(Data(bytes)))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// What the token endpoint returns.
public struct OAuthTokens: Decodable, Equatable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token", refreshToken = "refresh_token", expiresIn = "expires_in"
    }
}
