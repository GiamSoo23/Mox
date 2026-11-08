import Foundation

/// What a device needs to reach its owner's Supabase project
/// (shared/PROTOCOL.md §1). The password is a secret: the app keeps these
/// settings in the Keychain.
public struct MoxSettings: Codable, Equatable {
    public let projectURL: URL
    public let publishableKey: String
    public let email: String
    public let password: String

    public init(projectURL: URL, publishableKey: String, email: String, password: String) {
        self.projectURL = projectURL
        self.publishableKey = publishableKey
        self.email = email
        self.password = password
    }

    /// The link a phone scans to get these same settings.
    public func pairingLink(desktopName: String?) -> PairingLink {
        PairingLink(projectURL: projectURL.absoluteString, publishableKey: publishableKey,
                    email: email, password: password, desktopName: desktopName)
    }
}
