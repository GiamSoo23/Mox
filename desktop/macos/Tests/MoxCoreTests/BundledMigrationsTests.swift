import XCTest
@testable import MoxCore

/// The wizard applies BundledMigrations, so they must be exactly the
/// backend's migrations. If this fails, run scripts/sync-migrations.py.
final class BundledMigrationsTests: XCTestCase {
    func testMatchTheBackendMigrationsExactly() throws {
        let dir = Fixtures.root.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("backend/supabase/migrations")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "sql" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertEqual(BundledMigrations.all.count, files.count, "run desktop/macos/scripts/sync-migrations.py")
        for (bundled, file) in zip(BundledMigrations.all, files) {
            let stem = file.deletingPathExtension().lastPathComponent
            XCTAssertEqual("\(bundled.version)_\(bundled.name)", stem)
            let sql = try String(contentsOf: file, encoding: .utf8)
            XCTAssertEqual(bundled.sql, sql.trimmingCharacters(in: CharacterSet(charactersIn: "\n")),
                           "\(stem) drifted: run desktop/macos/scripts/sync-migrations.py")
        }
    }
}
