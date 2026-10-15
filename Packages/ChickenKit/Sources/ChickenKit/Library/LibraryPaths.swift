import Foundation

/// On-disk layout of the managed library. The folder name and structure match
/// what earlier versions of Chicken wrote, so a migrated Mac library is read
/// in place: `Application Support/Chicken/{Books,Covers,library.json,...}`.
public struct LibraryPaths: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public static func standard(fileManager: FileManager = .default) -> LibraryPaths {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return LibraryPaths(root: base.appendingPathComponent("Chicken", isDirectory: true))
    }

    public var books: URL { root.appendingPathComponent("Books", isDirectory: true) }
    public var covers: URL { root.appendingPathComponent("Covers", isDirectory: true) }
    public var store: URL { root.appendingPathComponent("Library.store") }

    public var epubCache: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("Chicken/EPUBCache", isDirectory: true)
    }

    public func bookFile(named storedFileName: String) -> URL {
        books.appendingPathComponent(storedFileName)
    }

    public func coverFile(named coverImageName: String) -> URL {
        covers.appendingPathComponent(coverImageName)
    }

    public func createDirectories() throws {
        let fileManager = FileManager.default
        for directory in [root, books, covers] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
