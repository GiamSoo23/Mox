import XCTest
@testable import MoxCore

/// v2 rows against shared/fixtures/rows/, the same files CI inserts into the
/// real schema and the other clients test against.
final class CurrentFileTests: XCTestCase {
    private func decodeRow(_ url: URL) throws -> CurrentFile {
        try JSONDecoder().decode(CurrentFile.self, from: Data(contentsOf: url))
    }

    func testEveryValidRowFixtureDecodesAndValidates() throws {
        let rows = try Fixtures.files("rows/valid", ext: "json")
        XCTAssertGreaterThanOrEqual(rows.count, 4)
        for file in rows {
            XCTAssertNoThrow(try decodeRow(file).validate(), file.lastPathComponent)
        }
    }

    func testEveryInvalidRowFixtureIsRefused() throws {
        let rows = try Fixtures.files("rows/invalid", ext: "json")
        XCTAssertGreaterThanOrEqual(rows.count, 11)
        for file in rows {
            // Either it doesn't decode (missing device id) or validate() refuses it.
            XCTAssertThrowsError(try decodeRow(file).validate(), file.lastPathComponent)
        }
    }

    func testFieldsOfAValidRow() throws {
        let row = try decodeRow(Fixtures.root.appendingPathComponent("rows/valid/bundle-from-android.json"))
        XCTAssertEqual(row.kind, "bundle")
        XCTAssertEqual(row.itemCount, 5)
        XCTAssertEqual(row.sourcePlatform, "android")
        XCTAssertEqual(row.sourceName, "Android")
        XCTAssertEqual(row.sourceDeviceId, UUID(uuidString: "a2b3c4d5-e6f7-4a8b-9c0d-1e2f3a4b5c6d"))
    }

    func testANullMimeTypeIsNil() throws {
        let row = try decodeRow(Fixtures.root.appendingPathComponent("rows/valid/no-mime-type.json"))
        XCTAssertNil(row.mimeType)
    }
}
