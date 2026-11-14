import Compression
import Foundation

/// Reads a bundle: several files sent as one zip (PROTOCOL.md §9). It refuses
/// the whole bundle, unpacking nothing, when any entry is unsafe.
public enum BundleReader {
    public static let maxEntries = 1000
    public static let maxUnpacked = CurrentFile.maxSize

    /// One file in the bundle: its path inside the bundle, and its bytes.
    public struct Entry: Equatable {
        public let path: String
        public let data: Data
    }

    public struct Refused: LocalizedError, Equatable {
        public let reason: String
        public var errorDescription: String? { "Mox didn't unpack these files: \(reason)." }
    }

    /// The files in a bundle, in order, or `Refused`.
    public static func read(_ zip: Data) throws -> [Entry] {
        let bytes = [UInt8](zip)
        let records = try centralDirectory(bytes)
        guard records.count <= maxEntries else { throw Refused(reason: "it has too many files") }
        var kept: [Record] = []
        var total: Int64 = 0
        for record in records {
            try check(record)
            if isSkipped(record.name) { continue }
            total += Int64(record.size)
            guard total <= maxUnpacked else { throw Refused(reason: "they add up to more than 50 MB") }
            kept.append(record)
        }
        guard kept.count >= 2 else { throw Refused(reason: "a bundle has at least 2 files") }
        return try kept.map { Entry(path: $0.name, data: try contents(of: $0, in: bytes)) }
    }

    /// Unpacks a bundle into `folder`, which it creates, and returns the
    /// top-level items: what goes on the pasteboard.
    public static func extract(_ zip: Data, into folder: URL) throws -> [URL] {
        let entries = try read(zip)
        let manager = FileManager.default
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        var topLevel: [URL] = []
        for entry in entries {
            let parts = entry.path.split(separator: "/").map(String.init)
            var dir = folder
            for part in parts.dropLast() { dir.appendPathComponent(part, isDirectory: true) }
            try manager.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = UniqueName.url(for: parts.last ?? "file", in: dir)
            try entry.data.write(to: file)
            let top = parts.count > 1 ? folder.appendingPathComponent(parts[0], isDirectory: true) : file
            if !topLevel.contains(top) { topLevel.append(top) }
        }
        return topLevel
    }

    // MARK: Rules

    private static func check(_ record: Record) throws {
        let name = record.name
        let chars = Array(name)
        if name.contains("\\") || name.hasPrefix("/") || (chars.count > 1 && chars[1] == ":")
            || name.split(separator: "/", omittingEmptySubsequences: false).contains("..") {
            throw Refused(reason: "“\(name)” points outside the folder")
        }
        if (record.externalAttributes >> 16) & 0o170000 == 0o120000 {
            throw Refused(reason: "“\(name)” is a link")
        }
    }

    private static func isSkipped(_ name: String) -> Bool {
        name.hasSuffix("/") || name.hasPrefix("__MACOSX/")
            || name.split(separator: "/").last == ".DS_Store"
    }

    // MARK: Zip structure

    private struct Record {
        let name: String
        let method: UInt16
        let crc: UInt32
        let compressedSize: Int
        let size: Int
        let externalAttributes: UInt32
        let localHeader: Int
    }

    private static func centralDirectory(_ bytes: [UInt8]) throws -> [Record] {
        let notZip = Refused(reason: "it isn't a zip")
        guard bytes.count >= 22 else { throw notZip }
        var end = bytes.count - 22
        let lowest = max(0, bytes.count - 22 - 65_535)
        while end >= lowest, bytes.u32(end) != 0x0605_4b50 { end -= 1 }
        guard end >= lowest else { throw notZip }
        let count = Int(bytes.u16(end + 10))
        var offset = Int(bytes.u32(end + 16))
        var records: [Record] = []
        for _ in 0..<count {
            guard offset + 46 <= bytes.count, bytes.u32(offset) == 0x0201_4b50 else { throw notZip }
            let nameLength = Int(bytes.u16(offset + 28))
            let skip = nameLength + Int(bytes.u16(offset + 30)) + Int(bytes.u16(offset + 32))
            guard offset + 46 + nameLength <= bytes.count,
                  let name = String(bytes: bytes[(offset + 46)..<(offset + 46 + nameLength)], encoding: .utf8)
            else { throw notZip }
            records.append(Record(name: name, method: bytes.u16(offset + 10), crc: bytes.u32(offset + 16),
                                  compressedSize: Int(bytes.u32(offset + 20)), size: Int(bytes.u32(offset + 24)),
                                  externalAttributes: bytes.u32(offset + 38),
                                  localHeader: Int(bytes.u32(offset + 42))))
            offset += 46 + skip
        }
        return records
    }

    private static func contents(of record: Record, in bytes: [UInt8]) throws -> Data {
        let damaged = Refused(reason: "“\(record.name)” is damaged")
        let header = record.localHeader
        guard header + 30 <= bytes.count, bytes.u32(header) == 0x0403_4b50 else { throw damaged }
        let start = header + 30 + Int(bytes.u16(header + 26)) + Int(bytes.u16(header + 28))
        guard start + record.compressedSize <= bytes.count else { throw damaged }
        let stored = Array(bytes[start..<(start + record.compressedSize)])
        let data: [UInt8]
        switch record.method {
        case 0: data = stored
        case 8: data = try inflate(stored, size: record.size, damaged: damaged)
        default: throw Refused(reason: "“\(record.name)” uses a compression Mox doesn't read")
        }
        guard data.count == record.size, CRC32.checksum(data) == record.crc else { throw damaged }
        return Data(data)
    }

    private static func inflate(_ input: [UInt8], size: Int, damaged: Refused) throws -> [UInt8] {
        guard size > 0 else { return [] }
        var output = [UInt8](repeating: 0, count: size)
        let written = compression_decode_buffer(&output, size, input, input.count, nil, COMPRESSION_ZLIB)
        guard written == size else { throw damaged }
        return output
    }
}

extension [UInt8] {
    func u16(_ index: Int) -> UInt16 { UInt16(self[index]) | UInt16(self[index + 1]) << 8 }
    func u32(_ index: Int) -> UInt32 { UInt32(u16(index)) | UInt32(u16(index + 2)) << 16 }
}
