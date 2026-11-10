import Foundation

/// Plain text sent through the slot (#101, PROTOCOL.md §6).
public enum TextPayload {
    /// Texts stay small: they go to the clipboard, not to a folder.
    public static let maxBytes = 1_000_000
    public static let fileName = "Text.txt"
    public static let mime = "text/plain"

    /// The bytes to upload, or an error a person can act on.
    public static func encode(_ text: String) throws -> Data {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MoxError.upload("There's no text to send.")
        }
        let data = Data(text.utf8)
        guard data.count <= maxBytes else {
            throw MoxError.upload("That text is too long: Mox sends texts up to 1 MB.")
        }
        return data
    }

    public static func decode(_ data: Data) -> String {
        String(bytes: data, encoding: .utf8) ?? ""
    }

    /// A short, single-line version for notifications.
    public static func preview(_ text: String, max: Int = 120) -> String {
        let oneLine = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return oneLine.count <= max ? oneLine : String(oneLine.prefix(max - 1)) + "…"
    }
}
