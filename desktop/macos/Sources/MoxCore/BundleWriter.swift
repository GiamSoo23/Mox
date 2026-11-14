import Foundation

/// Packs several files, or a folder, into one zip with no compression
/// (PROTOCOL.md §9).
public enum BundleWriter {
    /// A file to pack: where it goes in the bundle, and where it is now.
    public struct Item: Equatable {
        public let path: String
        public let source: URL
        public let size: Int64
    }

    /// The files to send for what was selected. Folders keep their
    /// structure; hidden files and links are left out.
    public static func items(for urls: [URL]) throws -> [Item] {
        var items: [Item] = []
        var taken = Set<String>()
        for url in urls {
            let top = uniqueTop(url.lastPathComponent, taken: &taken)
            if isFolder(url) {
                items += try folderItems(url, as: top)
            } else if let size = regularSize(url) {
                items.append(Item(path: top, source: url, size: size))
            }
        }
        return items
    }

    /// "Mox – 5 files.zip", the name the row carries.
    public static func fileName(count: Int) -> String { "Mox – \(count) files.zip" }

    /// Checks the 50 MB limit before packing, then writes the zip.
    public static func write(_ items: [Item], to destination: URL) throws {
        let total = items.reduce(Int64(0)) { $0 + $1.size }
        guard total <= CurrentFile.maxSize else { throw TooBig(items: items, total: total) }
        var zip = Data()
        var central = Data()
        for item in items {
            let data = try Data(contentsOf: item.source)
            let name = Data(item.path.utf8)
            let crc = CRC32.checksum(data)
            let offset = UInt32(zip.count)
            zip.append(header(signature: 0x0403_4b50, name: name, crc: crc, size: data.count, local: true))
            zip.append(name)
            zip.append(data)
            var entry = header(signature: 0x0201_4b50, name: name, crc: crc, size: data.count, local: false)
            entry.append(le32(offset))
            central.append(entry)
            central.append(name)
        }
        var end = Data()
        end.append(le32(0x0605_4b50))
        end.append(le16(0) + le16(0) + le16(UInt16(items.count)) + le16(UInt16(items.count)))
        end.append(le32(UInt32(central.count)) + le32(UInt32(zip.count)) + le16(0))
        zip.append(central)
        zip.append(end)
        try zip.write(to: destination)
    }

    /// Which files make a bundle too big, biggest first.
    public struct TooBig: LocalizedError {
        public let items: [Item]
        public let total: Int64
        public var errorDescription: String? {
            let biggest = items.sorted { $0.size > $1.size }.prefix(3)
                .map { "\(($0.path as NSString).lastPathComponent) (\(humanSize($0.size)))" }
            return "These files add up to \(humanSize(total)), and Mox sends up to 50 MB. "
                + "The biggest: \(biggest.joined(separator: ", "))."
        }
    }

    // MARK: Zip records

    /// A local or central header, up to the name (the central one still
    /// needs the local header's offset).
    private static func header(signature: UInt32, name: Data, crc: UInt32, size: Int, local: Bool) -> Data {
        var data = le32(signature)
        if !local { data.append(le16(0x0314)) }               // made by: Unix, zip 2.0
        data.append(le16(20) + le16(0x0800) + le16(0))         // version, UTF-8 names, stored
        data.append(le16(0) + le16(0x5B6A))                    // time, date (fixed: 2025-11-10)
        data.append(le32(crc) + le32(UInt32(size)) + le32(UInt32(size)))
        data.append(le16(UInt16(name.count)) + le16(0))        // name and extra lengths
        if !local {
            data.append(le16(0) + le16(0) + le16(0))           // comment, disk, internal attributes
            data.append(le32(0o100644 << 16))                  // a regular file
        }
        return data
    }

    private static func le16(_ value: UInt16) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
    private static func le32(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }

    // MARK: Files

    private static func folderItems(_ folder: URL, as top: String) throws -> [Item] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys,
                                                          options: [.skipsHiddenFiles]) else { return [] }
        let base = folder.standardizedFileURL.pathComponents.count
        var items: [Item] = []
        for case let url as URL in walker {
            guard let size = regularSize(url) else { continue }
            let rest = url.standardizedFileURL.pathComponents.dropFirst(base)
            items.append(Item(path: ([top] + rest).joined(separator: "/"), source: url, size: size))
        }
        return items.sorted { $0.path < $1.path }
    }

    private static func isFolder(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// The size of a plain file, or nil for links and anything else.
    private static func regularSize(_ url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values?.isRegularFile == true, values?.isSymbolicLink != true else { return nil }
        return Int64(values?.fileSize ?? 0)
    }

    private static func uniqueTop(_ name: String, taken: inout Set<String>) -> String {
        var candidate = name
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        var number = 1
        while taken.contains(candidate) {
            candidate = ext.isEmpty ? "\(stem) (\(number))" : "\(stem) (\(number)).\(ext)"
            number += 1
        }
        taken.insert(candidate)
        return candidate
    }
}
