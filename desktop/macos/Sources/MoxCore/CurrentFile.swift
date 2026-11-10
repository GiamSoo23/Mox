import Foundation

/// The single row of `mox.current_file`: the file in the slot right now
/// (shared/PROTOCOL.md §5).
public struct CurrentFile: Decodable, Equatable {
    public static let maxSize: Int64 = 52_428_800
    public static let platforms: Set<String> = ["macos", "windows", "android", "ios"]

    public let id: Int
    public let originalName: String
    public let mimeType: String?
    public let sizeBytes: Int64
    public let kind: String
    public let itemCount: Int
    public let sourcePlatform: String
    public let sourceDeviceId: UUID
    public let uploadedAt: String

    /// Text to paste, not a file to save (#101).
    public var isText: Bool { kind == "text" }

    /// The row's JSON uses the table's snake_case column names. Unknown
    /// columns are ignored, so newer schemas don't break this client.
    enum CodingKeys: String, CodingKey {
        case id
        case originalName = "original_name"
        case mimeType = "mime_type"
        case sizeBytes = "size_bytes"
        case kind
        case itemCount = "item_count"
        case sourcePlatform = "source_platform"
        case sourceDeviceId = "source_device_id"
        case uploadedAt = "uploaded_at"
    }

    /// Checks the rules of §5. The database enforces them too; this lets the
    /// app refuse a bad row with a clear message instead of misbehaving.
    public func validate() throws {
        guard id == 1 else { throw MoxError.invalidRow("id must be 1") }
        guard (1...255).contains(originalName.unicodeScalars.count) else {
            throw MoxError.invalidRow("the file name must be 1–255 characters")
        }
        guard (1...Self.maxSize).contains(sizeBytes) else {
            throw MoxError.invalidRow("the size must be between 1 byte and 50 MB")
        }
        switch (kind, itemCount) {
        case ("file", 1), ("text", 1): break
        case ("bundle", 2...): break
        default: throw MoxError.invalidRow("kind \(kind) can't have \(itemCount) items")
        }
        guard Self.platforms.contains(sourcePlatform) else {
            throw MoxError.invalidRow("unknown platform \(sourcePlatform)")
        }
    }

    /// "Mac", "Android", "Windows" or "iPhone", for menus and notifications.
    public var sourceName: String {
        ["macos": "Mac", "windows": "Windows", "android": "Android", "ios": "iPhone"][sourcePlatform] ?? sourcePlatform
    }
}
