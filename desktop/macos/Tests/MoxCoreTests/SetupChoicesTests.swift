import XCTest
@testable import MoxCore

final class SetupChoicesTests: XCTestCase {
    private func project(_ name: String, _ status: String = "ACTIVE_HEALTHY") -> Project {
        Project(id: name.lowercased(), organizationID: "org", name: name, region: "us-east-1", status: status)
    }

    func testANewProjectIsRecommendedWithAFreeSlot() {
        let choices = SetupChoices(projects: [project("Blog"), project("Old", "INACTIVE")])
        XCTAssertEqual(choices.recommendation, .newProject)
        XCTAssertFalse(choices.atFreeLimit)
    }

    func testAnEmptyAccountGetsANewProject() {
        XCTAssertEqual(SetupChoices(projects: []).recommendation, .newProject)
    }

    func testAnExistingProjectIsRecommendedAtTheFreeLimit() {
        let choices = SetupChoices(projects: [project("Blog"), project("Shop", "COMING_UP"),
                                              project("Old", "INACTIVE")])
        XCTAssertTrue(choices.atFreeLimit)
        XCTAssertEqual(choices.recommendation, .existingProject)
    }

    func testReadyProjectsComeFirstAndDeletedOnesAreHidden() {
        let choices = SetupChoices(projects: [project("zeta"), project("Paused", "INACTIVE"),
                                              project("alpha"), project("Gone", "REMOVED")])
        XCTAssertEqual(choices.existing.map(\.name), ["alpha", "zeta", "Paused"])
    }

    func testOnlyMemberMeansNoWarning() {
        let owner = OrganizationMember(userID: "u1", email: "me@example.com", roleName: "Owner")
        XCTAssertEqual(SharedProjectCheck.otherAdmins([owner]), [])
    }

    func testEveryoneIsListedWhenSomeoneElseIsAMember() {
        let owner = OrganizationMember(userID: "u1", email: "me@example.com", roleName: "Owner")
        let other = OrganizationMember(userID: "u2", email: nil, roleName: "Developer")
        XCTAssertEqual(SharedProjectCheck.otherAdmins([owner, other]), ["me@example.com", "u2"])
    }

    func testRegionGuesses() {
        XCTAssertEqual(SupabaseRegion.guess(timeZone: "America/Mexico_City").code, "us-east-1")
        XCTAssertEqual(SupabaseRegion.guess(timeZone: "America/Sao_Paulo").code, "sa-east-1")
        XCTAssertEqual(SupabaseRegion.guess(timeZone: "Europe/Madrid").code, "eu-central-1")
        XCTAssertEqual(SupabaseRegion.guess(timeZone: "Asia/Tokyo").code, "ap-northeast-1")
        XCTAssertEqual(SupabaseRegion.guess(timeZone: "Australia/Sydney").code, "ap-southeast-2")
        XCTAssertEqual(SupabaseRegion.guess(timeZone: "Etc/UTC").code, "us-east-1")
    }
}
