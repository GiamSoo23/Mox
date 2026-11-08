import XCTest
@testable import MoxCore

final class EnvFileTests: XCTestCase {
    func testParsesKeysValuesCommentsAndQuotes() {
        let text = """
        # A comment
        SUPABASE_URL=https://example.supabase.co

          SPACED = value with spaces
        QUOTED="quoted value"
        WITH_EQUALS=a=b=c
        not a valid line
        """
        let values = EnvFile.parse(text)
        XCTAssertEqual(values["SUPABASE_URL"], "https://example.supabase.co")
        XCTAssertEqual(values["SPACED"], "value with spaces")
        XCTAssertEqual(values["QUOTED"], "quoted value")
        XCTAssertEqual(values["WITH_EQUALS"], "a=b=c")
        XCTAssertEqual(values.count, 4)
    }

    func testTheFirstValueInAFileWins() {
        XCTAssertEqual(EnvFile.parse("KEY=first\nKEY=second")["KEY"], "first")
    }

    func testALoneQuoteIsKeptAsIs() {
        XCTAssertEqual(EnvFile.parse("KEY=\"")["KEY"], "\"")
    }

    func testTheEnvironmentWinsThenEarlierFiles() {
        let merged = EnvFile.merge(
            environment: ["A": "from-env"],
            files: ["A=from-file\nB=first-file", "B=second-file\nC=second-file"]
        )
        XCTAssertEqual(merged["A"], "from-env")
        XCTAssertEqual(merged["B"], "first-file")
        XCTAssertEqual(merged["C"], "second-file")
    }
}
