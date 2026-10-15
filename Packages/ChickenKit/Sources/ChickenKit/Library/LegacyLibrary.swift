import Foundation

/// Reader for the JSON files written by Chicken 1.x (`library.json`,
/// `highlights.json`, `bookmarks.json`, `reader-preferences.json`,
/// `reading-log.json`). Used once to seed the new store; files are left in
/// place so nothing is lost if the migration needs to run again.
public struct LegacyLibrary: Sendable {
    public struct Book: Codable, Sendable, Hashable {
        public var id: UUID
        public var title: String
        public var author: String?
        public var format: BookFormat
        public var originalFileName: String
        public var storedFileName: String
        public var importedAt: Date
        public var lastOpenedAt: Date?
        public var progress: Double
        public var pageCount: Int?
        public var publisher: String?
        public var language: String?
        public var summary: String?
        public var coverImageName: String?
        public var lastLocation: String?
        public var finishedAt: Date?
    }

    public struct Highlight: Codable, Sendable, Hashable {
        public var id: UUID
        public var bookID: UUID
        public var chapterIndex: Int
        public var text: String
        public var color: String
        public var note: String
        public var createdAt: Date
        public var location: String?
    }

    public struct Bookmark: Codable, Sendable, Hashable {
        public var id: UUID
        public var bookID: UUID
        public var chapterIndex: Int
        public var title: String
        public var location: String?
        public var createdAt: Date
    }

    public var books: [Book] = []
    public var highlights: [Highlight] = []
    public var bookmarks: [Bookmark] = []
    public var readerPreferences: [UUID: ReaderPreferences] = [:]
    public var readingLog: [String: Int] = [:]

    public static func catalogExists(in root: URL) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent("library.json").path)
    }

    /// Loads whatever legacy files exist. A missing or damaged secondary file
    /// is skipped rather than failing the whole migration.
    public static func load(from root: URL) throws -> LegacyLibrary {
        let decoder = JSONDecoder()
        func decode<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
            guard let data = try? Data(contentsOf: root.appendingPathComponent(name)) else { return nil }
            return try? decoder.decode(type, from: data)
        }

        let catalogData = try Data(contentsOf: root.appendingPathComponent("library.json"))
        var library = LegacyLibrary()
        library.books = try Self.decodeBooks(catalogData, decoder: decoder)
        library.highlights = decode([Highlight].self, "highlights.json") ?? []
        library.bookmarks = decode([Bookmark].self, "bookmarks.json") ?? []
        library.readerPreferences = decode([UUID: ReaderPreferences].self, "reader-preferences.json") ?? [:]
        library.readingLog = decode([String: Int].self, "reading-log.json") ?? [:]
        return library
    }

    /// Decodes books one at a time so a single malformed record doesn't
    /// discard the rest of the catalog.
    static func decodeBooks(_ data: Data, decoder: JSONDecoder) throws -> [Book] {
        guard let raw = try JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        return raw.compactMap { element in
            guard let itemData = try? JSONSerialization.data(withJSONObject: element) else { return nil }
            return try? decoder.decode(Book.self, from: itemData)
        }
    }
}
