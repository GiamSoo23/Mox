import XCTest
@testable import MoxCore

/// Bundles (PROTOCOL.md §9), against the shared fixtures every client loads.
final class BundleTests: XCTestCase {
    private var temp: URL!

    override func setUpWithError() throws {
        temp = FileManager.default.temporaryDirectory.appendingPathComponent("mox-bundle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temp)
    }

    func testValidFixturesUnpackToTheirFiles() throws {
        let zips = try Fixtures.files("bundles/valid", ext: "zip")
        XCTAssertFalse(zips.isEmpty)
        for zip in zips {
            struct Expected: Decodable { let files: [String] }
            let json = zip.deletingPathExtension().appendingPathExtension("json")
            let expected = try JSONDecoder().decode(Expected.self, from: Data(contentsOf: json))
            let entries = try BundleReader.read(Data(contentsOf: zip))
            XCTAssertEqual(entries.map(\.path), expected.files, zip.lastPathComponent)
        }
    }

    func testInvalidFixturesAreRefused() throws {
        let zips = try Fixtures.files("bundles/invalid", ext: "zip")
        XCTAssertEqual(zips.count, 9)
        for zip in zips {
            XCTAssertThrowsError(try BundleReader.read(Data(contentsOf: zip)), zip.lastPathComponent) {
                XCTAssertTrue($0 is BundleReader.Refused, zip.lastPathComponent)
            }
        }
    }

    func testExtractKeepsFoldersAndReturnsTopLevelItems() throws {
        let zip = Fixtures.root.appendingPathComponent("bundles/valid/folder-structure.zip")
        let folder = temp.appendingPathComponent("out")
        let top = try BundleReader.extract(Data(contentsOf: zip), into: folder)
        XCTAssertEqual(top.map(\.lastPathComponent), ["Trip", "cover.txt"])
        let day2 = folder.appendingPathComponent("Trip/notes/day2.txt")
        XCTAssertEqual(try String(contentsOf: day2, encoding: .utf8), "two")
    }

    func testWriteThenReadGivesTheSameFiles() throws {
        let photos = temp.appendingPathComponent("Fotos")
        try FileManager.default.createDirectory(at: photos.appendingPathComponent("día 1"),
                                                withIntermediateDirectories: true)
        try Data("uno".utf8).write(to: photos.appendingPathComponent("día 1/a.txt"))
        try Data("dos".utf8).write(to: photos.appendingPathComponent("b.txt"))
        try Data("x".utf8).write(to: photos.appendingPathComponent(".DS_Store"))
        let note = temp.appendingPathComponent("note.txt")
        try Data("tres".utf8).write(to: note)

        let items = try BundleWriter.items(for: [photos, note])
        XCTAssertEqual(items.map(\.path), ["Fotos/b.txt", "Fotos/día 1/a.txt", "note.txt"])
        let zip = temp.appendingPathComponent("bundle.zip")
        try BundleWriter.write(items, to: zip)

        let entries = try BundleReader.read(Data(contentsOf: zip))
        XCTAssertEqual(entries.map(\.path), items.map(\.path))
        XCTAssertEqual(entries.map { String(decoding: $0.data, as: UTF8.self) }, ["dos", "uno", "tres"])
    }

    func testSameNamesFromTwoFoldersBothArrive() throws {
        for folder in ["a", "b"] {
            let dir = temp.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(folder.utf8).write(to: dir.appendingPathComponent("photo.jpg"))
        }
        let items = try BundleWriter.items(for: [temp.appendingPathComponent("a/photo.jpg"),
                                                 temp.appendingPathComponent("b/photo.jpg")])
        XCTAssertEqual(items.map(\.path), ["photo.jpg", "photo (1).jpg"])
    }

    func testTooBigNamesTheBiggestFiles() {
        let half = CurrentFile.maxSize / 2 + 1
        let items = [BundleWriter.Item(path: "small.txt", source: temp, size: 10),
                     BundleWriter.Item(path: "big.mov", source: temp, size: half),
                     BundleWriter.Item(path: "bigger.mov", source: temp, size: half + 1)]
        XCTAssertThrowsError(try BundleWriter.write(items, to: temp.appendingPathComponent("x.zip"))) {
            let message = $0.localizedDescription
            XCTAssertTrue(message.contains("bigger.mov"), message)
            XCTAssertTrue(message.range(of: "bigger.mov")!.lowerBound < message.range(of: "big.mov")!.lowerBound)
        }
    }

    func testFileName() {
        XCTAssertEqual(BundleWriter.fileName(count: 5), "Mox – 5 files.zip")
    }
}
