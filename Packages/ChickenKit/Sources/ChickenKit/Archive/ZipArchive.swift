import Compression
import Foundation

/// Read-only ZIP reader for EPUB containers. Pure Swift so it runs inside the
/// iOS and macOS sandboxes, where shelling out to `/usr/bin/unzip` is not an
/// option. Supports stored and deflated entries, plus ZIP64 offsets.
public struct ZipArchive: Sendable {
    public struct Entry: Sendable, Hashable {
        public let path: String
        public let uncompressedSize: Int
        let compressionMethod: UInt16
        let compressedSize: Int
        let localHeaderOffset: Int

        public var isDirectory: Bool { path.hasSuffix("/") }
    }

    public enum ZipError: Error, Equatable {
        case notAZip
        case corrupt
        case unsupportedCompression(UInt16)
        case entryTooLarge
        case decompressionFailed
        case missingEntry(String)
    }

    /// Largest single entry Chicken will inflate into memory.
    static let maxEntrySize = 512 * 1024 * 1024

    public let entries: [Entry]
    private let data: Data
    private let index: [String: Int]

    public init(url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .alwaysMapped))
    }

    public init(data: Data) throws {
        self.data = data
        let reader = ByteReader(data: data)
        let directory = try Self.locateCentralDirectory(reader)
        var entries: [Entry] = []
        entries.reserveCapacity(directory.count)

        var offset = directory.offset
        for _ in 0..<directory.count {
            guard reader.uint32(at: offset) == 0x0201_4B50 else { throw ZipError.corrupt }
            let flags = reader.uint16(at: offset + 8)
            let method = reader.uint16(at: offset + 10)
            var compressedSize = Int(reader.uint32(at: offset + 20))
            var uncompressedSize = Int(reader.uint32(at: offset + 24))
            let nameLength = Int(reader.uint16(at: offset + 28))
            let extraLength = Int(reader.uint16(at: offset + 30))
            let commentLength = Int(reader.uint16(at: offset + 32))
            var localHeaderOffset = Int(reader.uint32(at: offset + 42))

            let nameStart = offset + 46
            guard let nameData = reader.bytes(at: nameStart, count: nameLength) else { throw ZipError.corrupt }
            let usesUTF8 = flags & 0x0800 != 0
            let name = (usesUTF8 ? String(data: nameData, encoding: .utf8) : nil)
                ?? String(data: nameData, encoding: .utf8)
                ?? String(data: nameData, encoding: .isoLatin1)
                ?? ""

            // ZIP64 extended information replaces any 32-bit field saturated at 0xFFFFFFFF.
            var extraOffset = nameStart + nameLength
            let extraEnd = extraOffset + extraLength
            while extraOffset + 4 <= extraEnd {
                let headerID = reader.uint16(at: extraOffset)
                let size = Int(reader.uint16(at: extraOffset + 2))
                if headerID == 0x0001 {
                    var cursor = extraOffset + 4
                    if uncompressedSize == 0xFFFF_FFFF {
                        uncompressedSize = Int(reader.uint64(at: cursor))
                        cursor += 8
                    }
                    if compressedSize == 0xFFFF_FFFF {
                        compressedSize = Int(reader.uint64(at: cursor))
                        cursor += 8
                    }
                    if localHeaderOffset == 0xFFFF_FFFF {
                        localHeaderOffset = Int(reader.uint64(at: cursor))
                    }
                }
                extraOffset += 4 + size
            }

            entries.append(
                Entry(
                    path: name,
                    uncompressedSize: uncompressedSize,
                    compressionMethod: method,
                    compressedSize: compressedSize,
                    localHeaderOffset: localHeaderOffset
                )
            )
            offset = nameStart + nameLength + extraLength + commentLength
        }

        self.entries = entries
        var index: [String: Int] = [:]
        for (position, entry) in entries.enumerated() where index[entry.path] == nil {
            index[entry.path] = position
        }
        self.index = index
    }

    public func entry(_ path: String) -> Entry? {
        if let position = index[path] { return entries[position] }
        // Some packagers percent-encode or vary case in hrefs; fall back to a
        // case-insensitive match before giving up.
        let lowered = path.lowercased()
        return entries.first { $0.path.lowercased() == lowered }
    }

    public func contains(_ path: String) -> Bool { entry(path) != nil }

    public func data(for path: String) throws -> Data {
        guard let entry = entry(path) else { throw ZipError.missingEntry(path) }
        return try data(for: entry)
    }

    public func data(for entry: Entry) throws -> Data {
        guard entry.uncompressedSize <= Self.maxEntrySize else { throw ZipError.entryTooLarge }
        let reader = ByteReader(data: data)
        let header = entry.localHeaderOffset
        guard reader.uint32(at: header) == 0x0403_4B50 else { throw ZipError.corrupt }
        let nameLength = Int(reader.uint16(at: header + 26))
        let extraLength = Int(reader.uint16(at: header + 28))
        let start = header + 30 + nameLength + extraLength
        guard let compressed = reader.bytes(at: start, count: entry.compressedSize) else { throw ZipError.corrupt }

        switch entry.compressionMethod {
        case 0:
            return compressed
        case 8:
            return try Self.inflate(compressed, expectedSize: entry.uncompressedSize)
        default:
            throw ZipError.unsupportedCompression(entry.compressionMethod)
        }
    }

    public func string(for path: String) -> String? {
        guard let data = try? data(for: path) else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    /// Writes every entry under `directory`, refusing paths that would escape it.
    public func extractAll(to directory: URL) throws {
        let fileManager = FileManager.default
        let root = directory.standardizedFileURL
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        for entry in entries {
            guard let destination = Self.safeDestination(for: entry.path, in: root) else { continue }
            if entry.isDirectory {
                try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
                continue
            }
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data(for: entry).write(to: destination, options: .atomic)
        }
    }

    static func safeDestination(for path: String, in root: URL) -> URL? {
        let components = path.split(separator: "/").map(String.init)
        guard !components.isEmpty, !components.contains(".."), !path.hasPrefix("/") else { return nil }
        let destination = components.reduce(root) { $0.appendingPathComponent($1) }.standardizedFileURL
        guard destination.path.hasPrefix(root.path + "/") else { return nil }
        return destination
    }

    // MARK: - Internals

    private struct CentralDirectory {
        let offset: Int
        let count: Int
    }

    private static func locateCentralDirectory(_ reader: ByteReader) throws -> CentralDirectory {
        let minimum = 22
        guard reader.count >= minimum else { throw ZipError.notAZip }
        let searchStart = max(0, reader.count - minimum - 0xFFFF)
        var eocd: Int?
        // Start just short of the end rather than at `count - 22`: archives
        // truncated by a byte or two (interrupted downloads) still carry a
        // usable directory record, and the reader zero-fills the missing tail.
        var cursor = reader.count - 4
        while cursor >= searchStart {
            if reader.uint32(at: cursor) == 0x0605_4B50 {
                eocd = cursor
                break
            }
            cursor -= 1
        }
        guard let eocd else { throw ZipError.notAZip }

        var count = Int(reader.uint16(at: eocd + 10))
        var offset = Int(reader.uint32(at: eocd + 16))

        if count == 0xFFFF || offset == 0xFFFF_FFFF {
            let locator = eocd - 20
            guard locator >= 0, reader.uint32(at: locator) == 0x0706_4B50 else { throw ZipError.corrupt }
            let record = Int(reader.uint64(at: locator + 8))
            guard reader.uint32(at: record) == 0x0606_4B50 else { throw ZipError.corrupt }
            count = Int(reader.uint64(at: record + 32))
            offset = Int(reader.uint64(at: record + 48))
        }

        guard offset >= 0, offset < reader.count else { throw ZipError.corrupt }
        return CentralDirectory(offset: offset, count: count)
    }

    private static func inflate(_ compressed: Data, expectedSize: Int) throws -> Data {
        guard expectedSize > 0 else { return Data() }
        var output = Data(count: expectedSize)
        let written = output.withUnsafeMutableBytes { destination -> Int in
            compressed.withUnsafeBytes { source -> Int in
                guard
                    let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress,
                    let sourceBase = source.bindMemory(to: UInt8.self).baseAddress
                else { return 0 }
                // COMPRESSION_ZLIB is raw DEFLATE (RFC 1951), which is what ZIP stores.
                return compression_decode_buffer(
                    destinationBase, expectedSize,
                    sourceBase, compressed.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == expectedSize else { throw ZipError.decompressionFailed }
        return output
    }
}

/// Little-endian reads at absolute offsets with bounds checks. Out-of-range
/// reads return zero so a truncated archive fails a signature check rather
/// than trapping.
private struct ByteReader {
    let data: Data

    var count: Int { data.count }

    func uint16(at offset: Int) -> UInt16 { UInt16(truncatingIfNeeded: value(at: offset, size: 2)) }
    func uint32(at offset: Int) -> UInt32 { UInt32(truncatingIfNeeded: value(at: offset, size: 4)) }
    func uint64(at offset: Int) -> UInt64 { value(at: offset, size: 8) }

    func bytes(at offset: Int, count: Int) -> Data? {
        guard offset >= 0, count >= 0, offset + count <= data.count else { return nil }
        let start = data.startIndex + offset
        return data.subdata(in: start..<(start + count))
    }

    private func value(at offset: Int, size: Int) -> UInt64 {
        guard offset >= 0, offset + size <= data.count else { return 0 }
        var result: UInt64 = 0
        let start = data.startIndex + offset
        for position in 0..<size {
            result |= UInt64(data[start + position]) << (8 * UInt64(position))
        }
        return result
    }
}
