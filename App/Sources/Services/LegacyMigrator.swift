import ChickenKit
import Foundation
import SwiftData

/// One-time import of a Chicken 1.x library (JSON catalog + files in
/// `Application Support/Chicken`). On a sandboxed Mac build, macOS moves that
/// folder into the container first, via `container-migration.plist`. Book and
/// cover files are already where the new store expects them, so only the
/// catalog needs converting. The JSON files are left untouched.
enum LegacyMigrator {
    /// Marker kept beside the library (not in UserDefaults) so it travels
    /// with the data it describes.
    static func markerURL(in paths: LibraryPaths) -> URL {
        paths.root.appendingPathComponent(".legacy-migrated")
    }

    struct Result {
        let books: Int
        let highlights: Int
        let bookmarks: Int
    }

    static func run(in context: ModelContext, paths: LibraryPaths) throws -> Result? {
        let marker = markerURL(in: paths)
        guard !FileManager.default.fileExists(atPath: marker.path) else { return nil }
        guard LegacyLibrary.catalogExists(in: paths.root) else { return nil }

        let existing = Set(((try? context.fetch(FetchDescriptor<Book>())) ?? []).map(\.id))
        let legacy = try LegacyLibrary.load(from: paths.root)
        var booksByID: [UUID: Book] = [:]

        for item in legacy.books where !existing.contains(item.id) {
            let book = Book(
                id: item.id,
                title: item.title,
                format: item.format,
                originalFileName: item.originalFileName,
                storedFileName: item.storedFileName
            )
            book.author = item.author
            book.importedAt = item.importedAt
            book.lastOpenedAt = item.lastOpenedAt
            book.lastActivityAt = item.lastOpenedAt ?? item.importedAt
            book.progress = item.progress
            book.pageCount = item.pageCount
            book.publisher = item.publisher
            book.language = item.language
            book.summary = item.summary.map(HTMLText.plainText(from:))
            book.coverImageName = item.coverImageName
            book.derivedDataChecked = item.coverImageName != nil
            book.lastLocation = item.lastLocation
            book.finishedAt = item.finishedAt ?? (item.progress >= 1 ? (item.lastOpenedAt ?? item.importedAt) : nil)
            book.preferences = legacy.readerPreferences[item.id]
            let fileURL = paths.bookFile(named: item.storedFileName)
            book.fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            context.insert(book)
            booksByID[item.id] = book
        }

        var highlightCount = 0
        for item in legacy.highlights {
            guard let book = booksByID[item.bookID] else { continue }
            let highlight = Highlight(
                id: item.id,
                chapterIndex: item.chapterIndex,
                text: item.text,
                color: HighlightColor(rawValue: item.color) ?? .amber,
                note: item.note,
                createdAt: item.createdAt,
                location: item.location
            )
            highlight.book = book
            context.insert(highlight)
            highlightCount += 1
        }

        var bookmarkCount = 0
        for item in legacy.bookmarks {
            guard let book = booksByID[item.bookID] else { continue }
            let bookmark = Bookmark(id: item.id, chapterIndex: item.chapterIndex, title: item.title, location: item.location, createdAt: item.createdAt)
            bookmark.book = book
            context.insert(bookmark)
            bookmarkCount += 1
        }

        if existing.isEmpty {
            for (day, seconds) in legacy.readingLog where seconds > 0 {
                context.insert(ReadingDay(day: day, seconds: seconds))
            }
        }

        try context.save()
        try? Data().write(to: marker)
        return Result(books: booksByID.count, highlights: highlightCount, bookmarks: bookmarkCount)
    }
}

extension LibraryStore {
    func migrateLegacyLibraryIfNeeded() {
        do {
            if let result = try LegacyMigrator.run(in: context, paths: paths), result.books > 0 {
                migrationSummary = "Brought over \(result.books) books, \(result.highlights) highlights, and \(result.bookmarks) bookmarks from your previous library."
            }
        } catch {
            migrationSummary = "Chicken couldn't read your previous library (\(error.localizedDescription)). Your files are untouched."
        }
    }
}
