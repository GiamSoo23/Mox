import XCTest
@testable import MoxCore

final class ConfigTests: XCTestCase {
    private let required = [
        "SUPABASE_URL": "https://example.supabase.co",
        "SUPABASE_ANON_KEY": "sb_publishable_test"
    ]

    func testDefaultsWhenOnlyTheRequiredValuesAreSet() throws {
        let config = try Config.from(required)
        XCTAssertEqual(config.supabaseURL.absoluteString, "https://example.supabase.co")
        XCTAssertEqual(config.supabaseAnonKey, "sb_publishable_test")
        XCTAssertEqual(config.hotkey.human, "⇧⌘M", "⌘⇧U is taken by Finder, so ⌘⇧M is the default")
        XCTAssertEqual(config.pollInterval, 5)
    }

    func testOptionalValuesOverrideTheDefaults() throws {
        var env = required
        env["MOX_HOTKEY"] = "ctrl+option+k"
        env["MOX_POLL_SECONDS"] = "2.5"
        let config = try Config.from(env)
        XCTAssertEqual(config.hotkey.human, "⌃⌥K")
        XCTAssertEqual(config.pollInterval, 2.5)
    }

    func testAnInvalidHotkeyFallsBackToTheDefault() throws {
        var env = required
        env["MOX_HOTKEY"] = "cmd+shift+1"
        XCTAssertEqual(try Config.from(env).hotkey.human, "⇧⌘M")
    }

    func testMissingValuesAreReportedByName() {
        XCTAssertThrowsError(try Config.from(["SUPABASE_ANON_KEY": "k"])) { error in
            XCTAssertEqual(error as? ConfigError, .missing("SUPABASE_URL"))
        }
        XCTAssertThrowsError(try Config.from(["SUPABASE_URL": "https://example.supabase.co"])) { error in
            XCTAssertEqual(error as? ConfigError, .missing("SUPABASE_ANON_KEY"))
        }
        var emptyKey = required
        emptyKey["SUPABASE_ANON_KEY"] = ""
        XCTAssertThrowsError(try Config.from(emptyKey))
    }

    func testLoadsFromEnvFilesAndSkipsMissingOnes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent(".env")
        try "SUPABASE_URL=https://file.supabase.co\nSUPABASE_ANON_KEY=from-file\n"
            .write(to: file, atomically: true, encoding: .utf8)

        let config = try Config.load(
            environment: ["SUPABASE_ANON_KEY": "from-env"],
            envFilePaths: [dir.appendingPathComponent("missing.env").path, file.path]
        )
        XCTAssertEqual(config.supabaseURL.host, "file.supabase.co")
        XCTAssertEqual(config.supabaseAnonKey, "from-env", "the environment wins over files")
    }
}
