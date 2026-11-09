import Foundation

/// A step of setting up a project for Mox, for the wizard's progress list.
public enum ProvisioningStep: Equatable {
    case waitingForProject
    case applyingMigrations(done: Int, total: Int)
    case exposingSchema
    case creatingMoxUser
    case settingOwner
    case readingKey
    case finished
}

/// Why setting up a project stopped, in words a person can act on.
public enum ProvisioningError: LocalizedError, Equatable {
    case projectPaused
    case projectNotReady
    case alreadyInstalled
    case noSecretKey
    case noPublishableKey

    public var errorDescription: String? {
        switch self {
        case .projectPaused:
            return "This project is paused. Restore it in the Supabase dashboard, then try again."
        case .projectNotReady:
            return "The project took too long to start. Try again in a few minutes."
        case .alreadyInstalled:
            return "Mox is already set up in this project for another Mox user. Setting it up again "
                + "means your other devices will need to pair again."
        case .noSecretKey:
            return "This project has no secret API key, which Mox needs once to create its user. "
                + "Create one in Project Settings → API Keys."
        case .noPublishableKey:
            return "This project has no publishable API key. Create one in Project Settings → API Keys."
        }
    }
}

/// Turns a new or existing Supabase project into a working Mox backend
/// (#80): migrations, exposed schema, the Mox user and its ownership, and
/// the publishable key. Safe to run again: it only does what's missing.
public final class Provisioner {
    private let api: ManagementAPI
    private let session: URLSession
    private let pause: (UInt64) async -> Void
    private let maxWaitSeconds: Int

    /// `pause` waits between status checks; tests make it instant.
    public init(api: ManagementAPI, session: URLSession = .shared, maxWaitSeconds: Int = 600,
                pause: @escaping (UInt64) async -> Void = { try? await Task.sleep(nanoseconds: $0) }) {
        self.api = api
        self.session = session
        self.maxWaitSeconds = maxWaitSeconds
        self.pause = pause
    }

    /// Sets up `project` and returns the settings to store and pair with.
    /// With `replaceExistingOwner`, a project that already has Mox gets a
    /// new Mox user (other paired devices must pair again).
    public func provision(project: Project, replaceExistingOwner: Bool = false,
                          progress: @escaping (ProvisioningStep) -> Void = { _ in }) async throws -> MoxSettings {
        progress(.waitingForProject)
        try await waitUntilReady(project)

        try await applyMissingMigrations(project.id, progress: progress)

        progress(.exposingSchema)
        let schemas = try await api.exposedSchemas(project: project.id)
        if !schemas.contains("mox") {
            try await api.setExposedSchemas(project: project.id, schemas + ["mox"])
        }

        if try await hasOwner(project.id), !replaceExistingOwner {
            throw ProvisioningError.alreadyInstalled
        }

        let previousUser = replaceExistingOwner ? try await generatedOwner(project.id) : nil

        progress(.creatingMoxUser)
        let keys = try await api.apiKeys(project: project.id, reveal: true)
        guard let secretKey = keys.first(where: \.isSecret)?.apiKey else { throw ProvisioningError.noSecretKey }
        let email = "mox-\(Self.randomHex(4))@mox.invalid"
        let password = Self.randomPassword()
        // The secret key is used for this one call and then dropped.
        let userID = try await AuthAdmin.createUser(projectURL: project.url, secretKey: secretKey,
                                                    email: email, password: password, session: session)

        progress(.settingOwner)
        try await api.runSQL(project: project.id,
                             "update mox.meta set owner_id = '\(userID.uuidString.lowercased())' where id = 1")

        // Otherwise every Set Up Again leaves one more user behind. If this
        // fails, the leftover user can't get in anymore, so it's harmless.
        if let previousUser {
            try? await AuthAdmin.deleteUser(projectURL: project.url, secretKey: secretKey,
                                            id: previousUser, session: session)
        }

        progress(.readingKey)
        guard let publishable = keys.first(where: \.isPublishable)?.apiKey else {
            throw ProvisioningError.noPublishableKey
        }

        progress(.finished)
        return MoxSettings(projectURL: project.url, publishableKey: publishable, email: email, password: password)
    }

    // MARK: Steps

    private func waitUntilReady(_ project: Project) async throws {
        var current = project
        let checks = max(1, maxWaitSeconds / 5)
        for _ in 0..<checks {
            if current.isReady { return }
            if current.isPaused { throw ProvisioningError.projectPaused }
            await pause(5_000_000_000)
            current = try await api.project(project.id)
        }
        if !current.isReady { throw ProvisioningError.projectNotReady }
    }

    /// Applies the bundled migrations the project doesn't have yet, and
    /// records each one where the Supabase CLI does, so `supabase db push`
    /// stays consistent afterwards.
    private func applyMissingMigrations(_ ref: String,
                                        progress: (ProvisioningStep) -> Void) async throws {
        try await api.runSQL(project: ref, """
            create schema if not exists supabase_migrations;
            create table if not exists supabase_migrations.schema_migrations (
                version text primary key, statements text[], name text
            );
            """)
        let rows = try await api.runSQL(project: ref, "select version from supabase_migrations.schema_migrations")
        let applied = Set(((try? JSONSerialization.jsonObject(with: rows)) as? [[String: Any]] ?? [])
            .compactMap { $0["version"] as? String })
        let missing = BundledMigrations.all.filter { !applied.contains($0.version) }
        for (index, migration) in missing.enumerated() {
            progress(.applyingMigrations(done: index, total: missing.count))
            try await api.runSQL(project: ref, migration.sql)
            try await api.runSQL(project: ref, """
                insert into supabase_migrations.schema_migrations (version, name)
                values ('\(migration.version)', '\(migration.name)') on conflict (version) do nothing
                """)
        }
        progress(.applyingMigrations(done: missing.count, total: missing.count))
    }

    private func hasOwner(_ ref: String) async throws -> Bool {
        let rows = try await api.runSQL(project: ref, "select owner_id is not null as has_owner from mox.meta")
        let first = ((try? JSONSerialization.jsonObject(with: rows)) as? [[String: Any]])?.first
        return first?["has_owner"] as? Bool ?? false
    }

    /// The current owner, only if it's a user Mox generated. A project's
    /// owner could also be a person's own account, which is never deleted.
    private func generatedOwner(_ ref: String) async throws -> UUID? {
        let rows = try await api.runSQL(project: ref, """
            select u.id from auth.users u join mox.meta m on m.owner_id = u.id
            where u.email like 'mox-%@mox.invalid'
            """)
        let first = ((try? JSONSerialization.jsonObject(with: rows)) as? [[String: Any]])?.first
        return (first?["id"] as? String).flatMap(UUID.init(uuidString:))
    }

    // MARK: Credentials

    static func randomHex(_ bytes: Int) -> String {
        randomBytes(bytes).map { String(format: "%02x", $0) }.joined()
    }

    /// 32 URL-safe characters (192 bits of randomness).
    static func randomPassword() -> String {
        PKCE.base64URL(Data(randomBytes(24)))
    }

    private static func randomBytes(_ count: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return bytes
    }
}
