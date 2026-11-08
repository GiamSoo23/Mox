import XCTest
@testable import MoxCore

/// The v1 row as PostgREST returns it. v2 rows get fixture tests with #11.
final class CurrentFileTests: XCTestCase {
    private func decode(_ json: String) throws -> CurrentFile {
        let rows = try JSONDecoder().decode([CurrentFile].self, from: Data(json.utf8))
        return try XCTUnwrap(rows.first)
    }

    func testDecodesASnakeCaseRowAndIgnoresUnknownFields() throws {
        let file = try decode("""
        [{"id":1,"storage_path":"current.jpg","original_name":"IMG_0001.jpg",
          "mime_type":"image/jpeg","size_bytes":2048,"uploaded_from":"android",
          "uploaded_at":"2026-11-08T03:48:08.315078+00:00"}]
        """)
        XCTAssertEqual(file.storagePath, "current.jpg")
        XCTAssertEqual(file.originalName, "IMG_0001.jpg")
        XCTAssertEqual(file.mimeType, "image/jpeg")
        XCTAssertEqual(file.sizeBytes, 2048)
        XCTAssertEqual(file.uploadedFrom, "android")
        XCTAssertEqual(file.uploadedAt, "2026-11-08T03:48:08.315078+00:00")
    }

    func testANullMimeTypeIsNil() throws {
        let file = try decode("""
        [{"storage_path":"current.bin","original_name":"notes","mime_type":null,
          "size_bytes":1,"uploaded_from":"mac","uploaded_at":"2026-11-08T00:00:00+00:00"}]
        """)
        XCTAssertNil(file.mimeType)
    }
}
