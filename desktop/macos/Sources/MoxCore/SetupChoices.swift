import Foundation

/// What the setup window offers once the person has signed in (#81), in the
/// agreed priority order: a new project, an existing one, another service
/// (later, #77).
public struct SetupChoices: Equatable {
    /// The free plan allows this many active projects per account.
    public static let freeProjectLimit = 2

    public enum Recommendation: Equatable {
        case newProject
        case existingProject
    }

    public let recommendation: Recommendation
    /// Projects Mox can be installed into, ready ones first, by name.
    public let existing: [Project]
    /// True when the account already uses every free project slot.
    public let atFreeLimit: Bool

    public init(projects: [Project]) {
        let usable = projects.filter { !Self.gone.contains($0.status) }
        let active = usable.filter { !$0.isPaused }
        atFreeLimit = active.count >= Self.freeProjectLimit
        existing = usable.sorted { lhs, rhs in
            if lhs.isPaused != rhs.isPaused { return !lhs.isPaused }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        recommendation = atFreeLimit && !active.isEmpty ? .existingProject : .newProject
    }

    /// Statuses of projects that are being deleted or never started.
    private static let gone: Set<String> = ["REMOVED", "GOING_DOWN", "INIT_FAILED"]
}

/// People besides the signed-in person who can administer an organization's
/// projects, and so could read Mox's files there (#78). Supabase doesn't say
/// which member is "me", so with more than one member, everyone is listed.
public enum SharedProjectCheck {
    public static func otherAdmins(_ members: [OrganizationMember]) -> [String] {
        guard members.count > 1 else { return [] }
        return members.map { $0.email ?? $0.userID }
    }
}

/// Supabase regions the setup window offers for a new project.
public struct SupabaseRegion: Equatable {
    public let code: String
    public let name: String

    public static let all: [SupabaseRegion] = [
        .init(code: "us-east-1", name: "East US (North Virginia)"),
        .init(code: "us-west-1", name: "West US (North California)"),
        .init(code: "ca-central-1", name: "Canada (Central)"),
        .init(code: "sa-east-1", name: "South America (São Paulo)"),
        .init(code: "eu-west-2", name: "West Europe (London)"),
        .init(code: "eu-central-1", name: "Central Europe (Frankfurt)"),
        .init(code: "ap-south-1", name: "South Asia (Mumbai)"),
        .init(code: "ap-southeast-1", name: "Southeast Asia (Singapore)"),
        .init(code: "ap-northeast-1", name: "Northeast Asia (Tokyo)"),
        .init(code: "ap-southeast-2", name: "Oceania (Sydney)")
    ]

    /// A sensible default from the Mac's time zone, e.g. "America/Mexico_City".
    public static func guess(timeZone: String) -> SupabaseRegion {
        let code: String
        switch timeZone {
        case "America/Sao_Paulo", "America/Argentina/Buenos_Aires", "America/Santiago",
             "America/Montevideo", "America/Asuncion":
            code = "sa-east-1"
        case "America/Los_Angeles", "America/Vancouver", "America/Tijuana", "America/Phoenix":
            code = "us-west-1"
        case "America/Toronto", "America/Montreal":
            code = "ca-central-1"
        case "Europe/London", "Europe/Dublin", "Europe/Lisbon":
            code = "eu-west-2"
        case "Asia/Kolkata", "Asia/Calcutta", "Asia/Karachi", "Asia/Dhaka":
            code = "ap-south-1"
        case "Asia/Tokyo", "Asia/Seoul":
            code = "ap-northeast-1"
        default:
            code = Self.byContinent(timeZone)
        }
        return all.first { $0.code == code } ?? all[0]
    }

    private static func byContinent(_ timeZone: String) -> String {
        let continent = timeZone.split(separator: "/").first.map(String.init) ?? ""
        switch continent {
        case "Europe", "Africa": return "eu-central-1"
        case "Asia": return "ap-southeast-1"
        case "Australia", "Pacific": return "ap-southeast-2"
        default: return "us-east-1"
        }
    }
}

extension OAuthClient {
    /// The Mox OAuth app (registered by the maintainer). Its id is public;
    /// the secret comes with official builds (#82) or `MOX_OAUTH_CLIENT_SECRET`.
    public static let moxClientID = "eba42d5a-0991-450c-9f60-44865c10765e"
    public static let moxRedirectURI = "http://localhost:\(OAuthLoopbackServer.port)/callback"
    /// Where official builds keep the secret: a key in the app's Info.plist,
    /// added by build-app.sh at release time (#82).
    public static let infoPlistSecretKey = "MoxOAuthClientSecret"

    /// The secret to use: the environment wins (a developer override), then
    /// the app bundle. Nil when neither has one.
    public static func secret(environment: String?, infoPlist: [String: Any]?) -> String? {
        if let environment, !environment.isEmpty { return environment }
        let bundled = infoPlist?[infoPlistSecretKey] as? String
        return bundled?.isEmpty == false ? bundled : nil
    }

    /// The Mox app with `secret`, or nil when this build has none.
    public static func mox(secret: String?) -> OAuthClient? {
        guard let secret, !secret.isEmpty else { return nil }
        return OAuthClient(id: moxClientID, secret: secret, redirectURI: moxRedirectURI)
    }
}
