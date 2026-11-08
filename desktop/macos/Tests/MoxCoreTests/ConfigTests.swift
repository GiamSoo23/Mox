import XCTest
@testable import MoxCore

final class ConfigTests: XCTestCase {
    private let complete = [
        "SUPABASE_URL": "https://example.supabase.co",
        "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_test",
        "MOX_USER_EMAIL": "mox-1234@mox.invalid",
        "MOX_USER_PASSWORD": "a-long-random-password"
    ]

    func testSettingsWhenAllFourValuesAreSet() throws {
        let settings = try XCTUnwrap(Config.from(complete).settings)
        XCTAssertEqual(settings.projectURL.absoluteString, "https://example.supabase.co")
        XCTAssertEqual(settings.publishableKey, "sb_publishable_test")
        XCTAssertEqual(settings.email, "mox-1234@mox.invalid")
        XCTAssertEqual(settings.password, "a-long-random-password")
    }

    func testNoSettingsWhenAnyValueIsMissingOrEmpty() {
        for name in complete.keys {
            var env = complete
            env[name] = nil
            XCTAssertNil(Config.from(env).settings, "missing \(name)")
            env[name] = ""
            XCTAssertNil(Config.from(env).settings, "empty \(name)")
        }
    }

    func testThePreV2KeyNameIsStillAccepted() throws {
        var env = complete
        env["SUPABASE_PUBLISHABLE_KEY"] = nil
        env["SUPABASE_ANON_KEY"] = "sb_publishable_old_name"
        XCTAssertEqual(Config.from(env).settings?.publishableKey, "sb_publishable_old_name")
    }

    func testDefaults() {
        let config = Config.from([:])
        XCTAssertEqual(config.hotkey.human, "⇧⌘M", "⌘⇧U is taken by Finder, so ⌘⇧M is the default")
        XCTAssertEqual(config.pollInterval, 5)
    }

    func testOptionalValuesOverrideTheDefaults() {
        let config = Config.from(["MOX_HOTKEY": "ctrl+option+k", "MOX_POLL_SECONDS": "2.5"])
        XCTAssertEqual(config.hotkey.human, "⌃⌥K")
        XCTAssertEqual(config.pollInterval, 2.5)
        XCTAssertEqual(Config.from(["MOX_HOTKEY": "cmd+shift+1"]).hotkey.human, "⇧⌘M", "invalid → default")
    }

    func testLoadsFromEnvFilesAndSkipsMissingOnes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent(".env")
        let text = complete.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
        try text.write(to: file, atomically: true, encoding: .utf8)

        let config = Config.load(
            environment: ["MOX_USER_EMAIL": "from-env@mox.invalid"],
            envFilePaths: [dir.appendingPathComponent("missing.env").path, file.path]
        )
        XCTAssertEqual(config.settings?.projectURL.host, "example.supabase.co")
        XCTAssertEqual(config.settings?.email, "from-env@mox.invalid", "the environment wins over files")
    }
}
