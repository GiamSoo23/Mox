import Foundation

/// The pairing link a desktop shows as a QR code (shared/PROTOCOL.md §8).
/// Encodes the configuration a phone needs; parsing is used by the tests
/// and by anything that receives a link.
public struct PairingLink: Equatable {
    public static let supportedVersion = "1"
    public static let defaultPageURL = "https://giamsoo23.github.io/Mox/pair/"

    /// Project URL with no trailing slash.
    public let projectURL: String
    public let publishableKey: String
    public let email: String
    public let password: String
    public let desktopName: String?

    public init(projectURL: String, publishableKey: String, email: String, password: String, desktopName: String?) {
        self.projectURL = projectURL.hasSuffix("/") ? String(projectURL.dropLast()) : projectURL
        self.publishableKey = publishableKey
        self.email = email
        self.password = password
        self.desktopName = desktopName
    }

    // MARK: Encoding

    /// §8.2: percent-encode every byte except A–Z a–z 0–9 - . _ ~
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    /// The `key=value&…` parameters, in the order v, u, k, e, p, n.
    public var parameters: String {
        var pairs = [
            ("v", Self.supportedVersion), ("u", projectURL), ("k", publishableKey),
            ("e", email), ("p", password)
        ]
        if let desktopName { pairs.append(("n", desktopName)) }
        return pairs.map { "\($0.0)=\(Self.encode($0.1))" }.joined(separator: "&")
    }

    /// The https link that goes in the QR code. Parameters live in the
    /// fragment, which browsers never send to a server.
    public func url(pageURL: String = PairingLink.defaultPageURL) -> String {
        "\(pageURL)#\(parameters)"
    }

    // MARK: Parsing

    /// Parses either form: the https pairing link or the `mox://pair?` hand-off.
    public static func parse(_ link: String) throws -> PairingLink {
        try validated(decode(rawParameters(of: link)))
    }

    /// The raw `key=value&…` string of either link form.
    static func rawParameters(of link: String) throws -> Substring {
        let text = link.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw: Substring
        if text.hasPrefix("mox://pair?") {
            raw = text.dropFirst("mox://pair?".count)
        } else if let hash = text.firstIndex(of: "#") {
            raw = text[text.index(after: hash)...]
        } else {
            throw PairingError.noParameters
        }
        guard !raw.isEmpty else { throw PairingError.noParameters }
        return raw
    }

    /// Splits and percent-decodes the parameters. Duplicates are invalid.
    static func decode(_ raw: Substring) throws -> [String: String] {
        var params: [String: String] = [:]
        for part in raw.split(separator: "&", omittingEmptySubsequences: true) {
            let key = String(part.prefix { $0 != "=" })
            let rawValue = part.dropFirst(key.count + (part.contains("=") ? 1 : 0))
            guard params[key] == nil else { throw PairingError.duplicateKey(key) }
            // removingPercentEncoding never turns "+" into a space (§8.2).
            guard let value = String(rawValue).removingPercentEncoding else { throw PairingError.badEncoding }
            params[key] = value
        }
        return params
    }

    /// Applies the rules of §8.2 to decoded parameters.
    static func validated(_ params: [String: String]) throws -> PairingLink {
        for key in ["v", "u", "k", "e", "p"] where (params[key] ?? "").isEmpty {
            throw PairingError.missing(key)
        }
        guard params["v"] == supportedVersion else { throw PairingError.unsupportedVersion }
        let link = PairingLink(projectURL: params["u"] ?? "", publishableKey: params["k"] ?? "",
                               email: params["e"] ?? "", password: params["p"] ?? "",
                               desktopName: params["n"].flatMap { $0.isEmpty ? nil : $0 })
        try link.checkFields()
        return link
    }

    private func checkFields() throws {
        let urlPattern = #"^https://[A-Za-z0-9.-]+(:\d+)?$"#
        guard projectURL.range(of: urlPattern, options: .regularExpression) != nil else {
            throw PairingError.badProjectURL
        }
        if publishableKey.hasPrefix("sb_secret_") { throw PairingError.secretKey }
        guard publishableKey.hasPrefix("sb_publishable_") else { throw PairingError.badKey }
        guard email.components(separatedBy: "@").count == 2, email.count <= 254 else { throw PairingError.badEmail }
        guard (16...128).contains(password.count) else { throw PairingError.badPassword }
        if let desktopName, desktopName.unicodeScalars.count > 64 { throw PairingError.nameTooLong }
    }
}

/// Why a pairing link can't be used.
public enum PairingError: Error, Equatable {
    case noParameters, badEncoding, duplicateKey(String), missing(String), unsupportedVersion
    case badProjectURL, secretKey, badKey, badEmail, badPassword, nameTooLong
}
