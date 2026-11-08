import Foundation

/// MIME types for the file extensions Mox sees most.
public enum MimeTypes {
    private static let byExtension: [String: String] = [
        "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
        "heic": "image/heic", "gif": "image/gif", "webp": "image/webp",
        "pdf": "application/pdf", "zip": "application/zip",
        "txt": "text/plain", "md": "text/markdown",
        "mp4": "video/mp4", "mov": "video/quicktime",
        "mp3": "audio/mpeg", "m4a": "audio/mp4",
        "json": "application/json"
    ]

    /// The MIME type for `ext` (case-insensitive), or
    /// `application/octet-stream` when unknown.
    public static func forExtension(_ ext: String) -> String {
        byExtension[ext.lowercased()] ?? "application/octet-stream"
    }
}
