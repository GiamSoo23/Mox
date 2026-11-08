import XCTest
@testable import MoxCore

final class ManagementAPITests: XCTestCase {
    private var session: URLSession!
    private var api: ManagementAPI!

    override func setUp() {
        session = MockURLProtocol.session()
        api = ManagementAPI(token: "token-123", session: session)
    }

    private var last: MockURLProtocol.Recorded { MockURLProtocol.recorded.last! }

    func testOrganizationsUseTheBearerToken() async throws {
        MockURLProtocol.reply(200, #"[{"id":"giamsoo23","name":"giamsoo23's projects"}]"#)
        let orgs = try await api.organizations()
        XCTAssertEqual(orgs, [Organization(id: "giamsoo23", name: "giamsoo23's projects")])
        XCTAssertEqual(last.request.httpMethod, "GET")
        XCTAssertEqual(last.request.url?.absoluteString, "https://api.supabase.com/v1/organizations")
        XCTAssertEqual(last.request.value(forHTTPHeaderField: "Authorization"), "Bearer token-123")
    }

    func testProjectsAndTheirState() async throws {
        MockURLProtocol.reply(200, #"""
        [{"id":"abcdefghijklmnopqrst","organization_id":"giamsoo23","name":"Mox","region":"us-west-2",
          "status":"ACTIVE_HEALTHY","created_at":"2026-05-26"},
         {"id":"zyxwvutsrqponmlkjihg","organization_id":"giamsoo23","name":"For Fun","region":"us-east-2",
          "status":"INACTIVE"}]
        """#)
        let projects = try await api.projects()
        XCTAssertEqual(projects.map(\.name), ["Mox", "For Fun"])
        XCTAssertTrue(projects[0].isReady)
        XCTAssertTrue(projects[1].isPaused)
        XCTAssertEqual(projects[0].url.absoluteString, "https://abcdefghijklmnopqrst.supabase.co")
    }

    func testCreateProjectSendsWhatTheAPIExpects() async throws {
        MockURLProtocol.reply(201, #"""
        {"id":"newprojectrefxxxxxxx","organization_id":"giamsoo23","name":"Mox",
         "region":"us-east-1","status":"COMING_UP"}
        """#)
        let project = try await api.createProject(name: "Mox", organization: "giamsoo23",
                                                  region: "us-east-1", databasePassword: "db-pass")
        XCTAssertFalse(project.isReady)
        XCTAssertEqual(last.request.httpMethod, "POST")
        XCTAssertEqual(last.request.url?.path, "/v1/projects")
        XCTAssertEqual(MockURLProtocol.lastJSON["name"] as? String, "Mox")
        XCTAssertEqual(MockURLProtocol.lastJSON["organization_id"] as? String, "giamsoo23")
        XCTAssertEqual(MockURLProtocol.lastJSON["region"] as? String, "us-east-1")
        XCTAssertEqual(MockURLProtocol.lastJSON["db_pass"] as? String, "db-pass")
    }

    func testAPIKeysRevealOnlyWhenAsked() async throws {
        MockURLProtocol.reply(200, #"""
        [{"name":"moxv2","type":"publishable","api_key":"sb_publishable_x"},
         {"name":"default","type":"secret","api_key":"sb_secret_x"}]
        """#)
        let keys = try await api.apiKeys(project: "ref", reveal: true)
        XCTAssertEqual(last.request.url?.query, "reveal=true")
        XCTAssertTrue(keys[0].isPublishable)
        XCTAssertTrue(keys[1].isSecret)
        _ = try await api.apiKeys(project: "ref")
        XCTAssertNil(last.request.url?.query)
    }

    func testRunSQLPostsTheQuery() async throws {
        MockURLProtocol.reply(201, #"[{"schema_version":2}]"#)
        let rows = try await api.runSQL(project: "ref", "select schema_version from mox.meta")
        XCTAssertEqual(last.request.url?.path, "/v1/projects/ref/database/query")
        XCTAssertEqual(MockURLProtocol.lastJSON["query"] as? String, "select schema_version from mox.meta")
        XCTAssertEqual(MockURLProtocol.text(rows), #"[{"schema_version":2}]"#)
    }

    func testExposedSchemasAreReadAndWrittenAsAList() async throws {
        MockURLProtocol.reply(200, #"{"db_schema":"public, graphql_public,mox","max_rows":1000}"#)
        XCTAssertEqual(try await api.exposedSchemas(project: "ref"), ["public", "graphql_public", "mox"])

        MockURLProtocol.reply(200, #"{"db_schema":"public,graphql_public,mox"}"#)
        try await api.setExposedSchemas(project: "ref", ["public", "graphql_public", "mox"])
        XCTAssertEqual(last.request.httpMethod, "PATCH")
        XCTAssertEqual(MockURLProtocol.lastJSON["db_schema"] as? String, "public,graphql_public,mox")
    }

    func testMembersForTheSharedProjectWarning() async throws {
        MockURLProtocol.reply(200, #"""
        [{"user_id":"u1","user_name":"g","email":"a@example.com","role_name":"Owner","mfa_enabled":false},
         {"user_id":"u2","user_name":"h","email":"b@example.com","role_name":"Developer","mfa_enabled":true}]
        """#)
        let members = try await api.members(organization: "giamsoo23")
        XCTAssertEqual(last.request.url?.path, "/v1/organizations/giamsoo23/members")
        XCTAssertEqual(members.map(\.roleName), ["Owner", "Developer"])
    }

    func testErrorsBecomeSomethingAPersonCanActOn() async {
        struct Case {
            let status: Int
            let body: String
            let expected: ManagementError
        }
        let limit = "The following organization members have reached their maximum limits "
            + "for the number of active free projects"
        let cases = [
            Case(status: 401, body: #"{"message":"Unauthorized"}"#, expected: .unauthorized),
            Case(status: 403, body: #"{"message":"OAuth token missing required scopes (projects_read)"}"#,
                 expected: .missingPermission("OAuth token missing required scopes (projects_read)")),
            Case(status: 400, body: #"{"message":"\#(limit)"}"#, expected: .projectLimitReached),
            Case(status: 500, body: #"{"message":"boom"}"#, expected: .http(500, "boom"))
        ]
        for testCase in cases {
            let (status, body, expected) = (testCase.status, testCase.body, testCase.expected)
            MockURLProtocol.reply(status, body)
            do {
                _ = try await api.projects()
                XCTFail("expected \(expected)")
            } catch {
                XCTAssertEqual(error as? ManagementError, expected)
            }
        }
    }

    func testCreatingTheMoxUserUsesTheSecretKeyOnce() async throws {
        let id = "390e2d0b-0494-4f4e-a248-ea81c182f505"
        MockURLProtocol.reply(200, #"{"id":"\#(id)","email":"mox-1@mox.invalid"}"#)
        let created = try await AuthAdmin.createUser(
            projectURL: try XCTUnwrap(URL(string: "https://ref.supabase.co")), secretKey: "sb_secret_x",
            email: "mox-1@mox.invalid", password: "correct-horse-battery-staple-42", session: session)
        XCTAssertEqual(created, UUID(uuidString: id))
        XCTAssertEqual(last.request.url?.absoluteString, "https://ref.supabase.co/auth/v1/admin/users")
        XCTAssertEqual(last.request.value(forHTTPHeaderField: "apikey"), "sb_secret_x")
        XCTAssertEqual(MockURLProtocol.lastJSON["email_confirm"] as? Bool, true)
    }
}
