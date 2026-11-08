import Foundation

/// The shared fixtures in shared/fixtures/, which every client's tests load.
enum Fixtures {
    static let root: URL = {
        // Tests/MoxCoreTests/Fixtures.swift → repository root (5 levels up).
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("shared/fixtures")
    }()

    static func files(_ folder: String, ext: String) throws -> [URL] {
        try FileManager.default
            .contentsOfDirectory(at: root.appendingPathComponent(folder), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == ext }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func text(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
