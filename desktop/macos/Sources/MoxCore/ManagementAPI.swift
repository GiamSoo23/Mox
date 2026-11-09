import Foundation

/// The Supabase Management API calls the setup wizard needs (#22, #79),
/// authenticated with an OAuth access token or a personal access token.
/// Confirmed against the real API in the #22 spikes: organizations,
/// projects, API keys, SQL and exposed schemas.
public final class ManagementAPI {
    public static let defaultBaseURL = URL(string: "https://api.supabase.com/v1")!

    private let token: String
    private let baseURL: URL
    private let session: URLSession

    public init(token: String, baseURL: URL = ManagementAPI.defaultBaseURL, session: URLSession = .shared) {
        self.token = token
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: Organizations and projects

    public func organizations() async throws -> [Organization] {
        try await decode(get("organizations"))
    }

    /// Who can administer an organization, for the shared-project warning (#78).
    public func members(organization: String) async throws -> [OrganizationMember] {
        try await decode(get("organizations/\(organization)/members"))
    }

    public func projects() async throws -> [Project] {
        try await decode(get("projects"))
    }

    public func project(_ ref: String) async throws -> Project {
        try await decode(get("projects/\(ref)"))
    }

    /// Creates a project. The free plan allows two active projects; past
    /// that, this throws `ManagementError.projectLimitReached`.
    public func createProject(name: String, organization: String, region: String,
                              databasePassword: String) async throws -> Project {
        try await decode(send("POST", "projects", json: [
            "name": name, "organization_id": organization,
            "region": region, "db_pass": databasePassword
        ]))
    }

    // MARK: Inside a project

    /// The project's API keys. With `reveal`, secret keys include their
    /// value; the wizard uses one once to create the Mox user, then drops it.
    public func apiKeys(project ref: String, reveal: Bool = false) async throws -> [APIKey] {
        try await decode(get("projects/\(ref)/api-keys", query: reveal ? "reveal=true" : nil))
    }

    /// Runs SQL as the database owner and returns the rows as raw JSON.
    @discardableResult
    public func runSQL(project ref: String, _ query: String) async throws -> Data {
        try await send("POST", "projects/\(ref)/database/query", json: ["query": query])
    }

    /// The schemas PostgREST serves (Project Settings → Data API).
    public func exposedSchemas(project ref: String) async throws -> [String] {
        let config: PostgRESTConfig = try await decode(get("projects/\(ref)/postgrest"))
        return config.dbSchema.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    public func setExposedSchemas(project ref: String, _ schemas: [String]) async throws {
        _ = try await send("PATCH", "projects/\(ref)/postgrest", json: ["db_schema": schemas.joined(separator: ",")])
    }

    // MARK: Requests

    private func get(_ path: String, query: String? = nil) async throws -> Data {
        try await send("GET", path, query: query)
    }

    private func send(_ method: String, _ path: String, query: String? = nil,
                      json: [String: Any]? = nil) async throws -> Data {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        comps.percentEncodedQuery = query
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw ManagementError.from(status: status, body: data) }
        return data
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        try JSONDecoder().decode(T.self, from: data)
    }
}

/// Creates the Mox user through a project's Auth admin endpoint. Needs the
/// project's secret key, which the wizard reads once and never stores.
public enum AuthAdmin {
    public static func createUser(projectURL: URL, secretKey: String, email: String, password: String,
                                  session: URLSession = .shared) async throws -> UUID {
        var req = URLRequest(url: projectURL.appendingPathComponent("auth/v1/admin/users"))
        req.httpMethod = "POST"
        req.setValue(secretKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": email, "password": password, "email_confirm": true
        ])
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw ManagementError.from(status: status, body: data) }
        struct Created: Decodable { let id: UUID }
        return try JSONDecoder().decode(Created.self, from: data).id
    }

    public static func deleteUser(projectURL: URL, secretKey: String, id: UUID,
                                  session: URLSession = .shared) async throws {
        let path = "auth/v1/admin/users/\(id.uuidString.lowercased())"
        var req = URLRequest(url: projectURL.appendingPathComponent(path))
        req.httpMethod = "DELETE"
        req.setValue(secretKey, forHTTPHeaderField: "apikey")
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw ManagementError.from(status: status, body: data) }
    }
}

// MARK: Models

public struct Organization: Decodable, Equatable {
    /// The organization's slug, used in other calls.
    public let id: String
    public let name: String
}

public struct OrganizationMember: Decodable, Equatable {
    public let userID: String
    public let email: String?
    public let roleName: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id", email, roleName = "role_name"
    }
}

public struct Project: Decodable, Equatable {
    /// The project ref (the subdomain of its URL).
    public let id: String
    public let organizationID: String
    public let name: String
    public let region: String
    public let status: String

    enum CodingKeys: String, CodingKey {
        case id, organizationID = "organization_id", name, region, status
    }

    public var url: URL { URL(string: "https://\(id).supabase.co")! }
    public var isReady: Bool { status == "ACTIVE_HEALTHY" }
    /// Free projects pause after a week without activity.
    public var isPaused: Bool { status == "INACTIVE" }
}

public struct APIKey: Decodable, Equatable {
    public let name: String
    public let type: String?
    public let apiKey: String?

    enum CodingKeys: String, CodingKey {
        case name, type, apiKey = "api_key"
    }

    public var isPublishable: Bool { type == "publishable" }
    public var isSecret: Bool { type == "secret" }
}

private struct PostgRESTConfig: Decodable {
    let dbSchema: String
    enum CodingKeys: String, CodingKey { case dbSchema = "db_schema" }
}

// MARK: Errors

public enum ManagementError: LocalizedError, Equatable {
    case unauthorized
    case missingPermission(String)
    case projectLimitReached
    case http(Int, String)

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Supabase didn't accept the sign-in. Sign in again."
        case .missingPermission(let detail):
            return "Mox wasn't given a permission it needs: \(detail)"
        case .projectLimitReached:
            return "Your Supabase account already has the maximum number of free projects. "
                + "Install Mox in one of them (nothing you have changes), or pause one you don't use."
        case .http(let status, let message):
            return "Supabase answered HTTP \(status): \(message)"
        }
    }

    static func from(status: Int, body: Data) -> ManagementError {
        let message = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["message"] as? String
            ?? String(data: body, encoding: .utf8) ?? ""
        let lower = message.lowercased()
        if status == 401 { return .unauthorized }
        if status == 403, lower.contains("scope") { return .missingPermission(message) }
        if lower.contains("limit") && (lower.contains("project") || lower.contains("free")) {
            return .projectLimitReached
        }
        return .http(status, message)
    }
}
