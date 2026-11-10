import XCTest
@testable import MoxCore

/// Runs the Provisioner against a fake Supabase (MockURLProtocol routes each
/// request by path and SQL text). No network.
final class ProvisionerTests: XCTestCase {
    private struct FakeProject {
        var appliedVersions: [String] = []
        var hasOwner = false
        var exposed = "public,graphql_public"
        var keys = #"[{"name":"moxv2","type":"publishable","api_key":"sb_publishable_x"},"#
            + #"{"name":"default","type":"secret","api_key":"sb_secret_x"}]"#
        var statusAfterWait = "ACTIVE_HEALTHY"
        /// The current owner's id, when Mox generated that user.
        var generatedOwner: String?
    }

    private var fake = FakeProject()
    private var migrationRuns = 0
    private var patchedSchemas: String?
    private var createdUser = false
    private var ownerSQL: String?
    private var deletedUserPath: String?
    private var deployedFunction = false
    private var secretsSet: String?
    private var pushSQL: String?
    private var deployStatus = 201
    private let userID = "390e2d0b-0494-4f4e-a248-ea81c182f505"
    private let oldUserID = "11111111-2222-4333-8444-555555555555"

    private func project(_ status: String = "ACTIVE_HEALTHY") -> Project {
        Project(id: "ref", organizationID: "org", name: "Mox", region: "us-west-2", status: status)
    }

    private func makeProvisioner() -> Provisioner {
        let session = MockURLProtocol.session()
        MockURLProtocol.handler = { [unowned self] request in self.route(request) }
        return Provisioner(api: ManagementAPI(token: "t", session: session), session: session, pause: { _ in })
    }

    private func route(_ request: URLRequest) -> (Int, Data) {
        let path = request.url?.path ?? ""
        let body = MockURLProtocol.recorded.last?.body ?? Data()
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        func ok(_ text: String) -> (Int, Data) { (200, Data(text.utf8)) }
        switch (request.httpMethod ?? "", path) {
        case ("GET", "/v1/projects/ref"):
            return ok(#"{"id":"ref","organization_id":"org","name":"Mox","region":"us-west-2","#
                + #""status":"\#(fake.statusAfterWait)"}"#)
        case ("GET", "/v1/projects/ref/postgrest"):
            return ok(#"{"db_schema":"\#(fake.exposed)"}"#)
        case ("PATCH", "/v1/projects/ref/postgrest"):
            patchedSchemas = json?["db_schema"] as? String
            return ok("{}")
        case ("GET", "/v1/projects/ref/api-keys"):
            return ok(fake.keys)
        case ("POST", "/auth/v1/admin/users"):
            createdUser = true
            return ok(#"{"id":"\#(userID)"}"#)
        case ("DELETE", "/auth/v1/admin/users/\(oldUserID)"):
            deletedUserPath = path
            return ok("{}")
        case ("POST", "/v1/projects/ref/functions/deploy"):
            deployedFunction = deployStatus < 300
            return (deployStatus, Data(#"{"message":"missing scope: edge_functions_write"}"#.utf8))
        case ("POST", "/v1/projects/ref/secrets"):
            secretsSet = MockURLProtocol.text(body)
            return ok("{}")
        case ("POST", "/v1/projects/ref/database/query"):
            return ok(routeSQL(json?["query"] as? String ?? ""))
        default:
            return (404, Data(#"{"message":"unexpected \#(request.httpMethod ?? "") \#(path)"}"#.utf8))
        }
    }

    /// Answers the SQL endpoint, and counts migrations and the owner update.
    private func routeSQL(_ query: String) -> String {
        if query.contains("select version from supabase_migrations") {
            return "[" + fake.appliedVersions.map { #"{"version":"\#($0)"}"# }.joined(separator: ",") + "]"
        }
        if query.contains("from auth.users") {
            return fake.generatedOwner.map { #"[{"id":"\#($0)"}]"# } ?? "[]"
        }
        if query.contains("has_owner") { return #"[{"has_owner":\#(fake.hasOwner)}]"# }
        if query.contains("mox.push_config") {
            pushSQL = query
            return "[]"
        }
        if query.contains("update mox.meta set owner_id") {
            ownerSQL = query
        } else if !query.contains("supabase_migrations") {
            migrationRuns += 1
        }
        return "[]"
    }

    func testAFreshProjectGetsEverything() async throws {
        var steps: [ProvisioningStep] = []
        let settings = try await makeProvisioner().provision(project: project()) { steps.append($0) }

        XCTAssertEqual(migrationRuns, BundledMigrations.all.count, "every migration applied once")
        XCTAssertEqual(patchedSchemas, "public,graphql_public,mox")
        XCTAssertTrue(createdUser)
        XCTAssertTrue(ownerSQL?.contains(userID) ?? false)
        XCTAssertEqual(settings.projectURL.absoluteString, "https://ref.supabase.co")
        XCTAssertEqual(settings.publishableKey, "sb_publishable_x")
        XCTAssertTrue(settings.email.hasPrefix("mox-") && settings.email.hasSuffix("@mox.invalid"))
        XCTAssertEqual(settings.password.count, 32)
        XCTAssertEqual(steps.first, .waitingForProject)
        XCTAssertEqual(steps.last, .finished)
        XCTAssertTrue(steps.contains(.creatingMoxUser))
    }

    func testAnExistingInstallIsNotReplacedWithoutPermission() async throws {
        fake.appliedVersions = BundledMigrations.all.map(\.version)
        fake.hasOwner = true
        fake.exposed = "public,graphql_public,mox"
        do {
            _ = try await makeProvisioner().provision(project: project())
            XCTFail("expected alreadyInstalled")
        } catch {
            XCTAssertEqual(error as? ProvisioningError, .alreadyInstalled)
        }
        XCTAssertEqual(migrationRuns, 0, "nothing to apply")
        XCTAssertNil(patchedSchemas, "mox was already exposed")
        XCTAssertFalse(createdUser)
    }

    func testReplacingTheOwnerWhenAsked() async throws {
        fake.appliedVersions = BundledMigrations.all.map(\.version)
        fake.hasOwner = true
        _ = try await makeProvisioner().provision(project: project(), replaceExistingOwner: true)
        XCTAssertTrue(createdUser)
        XCTAssertNotNil(ownerSQL)
    }

    func testReplacingRemovesThePreviousGeneratedUser() async throws {
        fake.appliedVersions = BundledMigrations.all.map(\.version)
        fake.hasOwner = true
        fake.generatedOwner = oldUserID
        _ = try await makeProvisioner().provision(project: project(), replaceExistingOwner: true)
        XCTAssertEqual(deletedUserPath, "/auth/v1/admin/users/\(oldUserID)")
    }

    func testAPersonsAccountIsNeverDeleted() async throws {
        fake.appliedVersions = BundledMigrations.all.map(\.version)
        fake.hasOwner = true
        fake.generatedOwner = nil
        _ = try await makeProvisioner().provision(project: project(), replaceExistingOwner: true)
        XCTAssertNil(deletedUserPath)
    }

    func testSetupTurnsOnIPhoneNotifications() async throws {
        _ = try await makeProvisioner().provision(project: project())
        XCTAssertTrue(deployedFunction)
        XCTAssertTrue(secretsSet?.contains("MOX_VAPID_PRIVATE_KEY") ?? false)
        XCTAssertTrue(pushSQL?.contains("https://ref.supabase.co/functions/v1/mox-push") ?? false)
        XCTAssertTrue(pushSQL?.contains("vapid_public_key") ?? false)
    }

    func testSetupGoesOnWhenNotificationsCantBeTurnedOn() async throws {
        deployStatus = 403
        var steps: [ProvisioningStep] = []
        let settings = try await makeProvisioner().provision(project: project()) { steps.append($0) }
        XCTAssertEqual(settings.publishableKey, "sb_publishable_x")
        XCTAssertNil(pushSQL, "the database isn't pointed at a function that wasn't deployed")
        XCTAssertTrue(steps.contains { if case .pushSkipped = $0 { return true }; return false })
        XCTAssertEqual(steps.last, .finished)
    }

    func testOnlyMissingMigrationsAreApplied() async throws {
        fake.appliedVersions = Array(BundledMigrations.all.prefix(2).map(\.version))
        _ = try await makeProvisioner().provision(project: project())
        XCTAssertEqual(migrationRuns, BundledMigrations.all.count - 2)
    }

    func testAPausedProjectStopsWithAClearMessage() async throws {
        do {
            _ = try await makeProvisioner().provision(project: project("INACTIVE"))
            XCTFail("expected projectPaused")
        } catch {
            XCTAssertEqual(error as? ProvisioningError, .projectPaused)
        }
        XCTAssertTrue(MockURLProtocol.recorded.isEmpty, "nothing was sent")
    }

    func testWaitsForANewProjectToStart() async throws {
        fake.statusAfterWait = "ACTIVE_HEALTHY"
        _ = try await makeProvisioner().provision(project: project("COMING_UP"))
        XCTAssertTrue(MockURLProtocol.recorded.contains { $0.request.url?.path == "/v1/projects/ref" })
        XCTAssertTrue(createdUser)
    }

    func testNoSecretKeyMeansNoUserCanBeCreated() async throws {
        fake.keys = #"[{"name":"moxv2","type":"publishable","api_key":"sb_publishable_x"}]"#
        do {
            _ = try await makeProvisioner().provision(project: project())
            XCTFail("expected noSecretKey")
        } catch {
            XCTAssertEqual(error as? ProvisioningError, .noSecretKey)
        }
        XCTAssertFalse(createdUser)
    }

    func testGeneratedCredentialsAreRandom() {
        XCTAssertNotEqual(Provisioner.randomPassword(), Provisioner.randomPassword())
        XCTAssertEqual(Provisioner.randomHex(4).count, 8)
    }
}
