import Foundation

/// The zip checksum (CRC-32, IEEE polynomial).
enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 { value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
        return value
    }

    static func checksum<S: Sequence>(_ bytes: S) -> UInt32 where S.Element == UInt8 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }
}

/// A name that isn't taken yet in a folder: `photo.jpg`, `photo (1).jpg`…
public enum UniqueName {
    public static func url(for name: String, in folder: URL) -> URL {
        var candidate = folder.appendingPathComponent(name)
        let stem = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        var number = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let next = ext.isEmpty ? "\(stem) (\(number))" : "\(stem) (\(number)).\(ext)"
            candidate = folder.appendingPathComponent(next)
            number += 1
        }
        return candidate
    }
}
