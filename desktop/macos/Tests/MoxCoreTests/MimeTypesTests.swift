import XCTest
@testable import MoxCore

final class MimeTypesTests: XCTestCase {
    func testKnownExtensionsCaseInsensitive() {
        XCTAssertEqual(MimeTypes.forExtension("png"), "image/png")
        XCTAssertEqual(MimeTypes.forExtension("JPG"), "image/jpeg")
        XCTAssertEqual(MimeTypes.forExtension("heic"), "image/heic")
        XCTAssertEqual(MimeTypes.forExtension("mov"), "video/quicktime")
        XCTAssertEqual(MimeTypes.forExtension("pdf"), "application/pdf")
    }

    func testUnknownOrMissingExtensionsAreGenericBinary() {
        XCTAssertEqual(MimeTypes.forExtension("xyz"), "application/octet-stream")
        XCTAssertEqual(MimeTypes.forExtension(""), "application/octet-stream")
    }
}
