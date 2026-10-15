import ChickenKit
import Foundation
import SwiftData

// Models follow CloudKit's rules (every property has a default or is
// optional, relationships are optional, no unique constraints) so iCloud
// sync can be switched on later without a schema migration.

@Model
final class Book {
    var id: UUID = UUID()
    var title: String = ""
    var author: String?
    var formatRaw: String = BookFormat.unknown.rawValue
    var originalFileName: String = ""
    var storedFileName: String = ""
    var fileSize: Int64 = 0
    var importedAt: Date = Date()
    var lastOpenedAt: Date?
    /// `lastOpenedAt ?? importedAt`, stored so the library can sort on it.
    var lastActivityAt: Date = Date()
    var progress: Double = 0
    var pageCount: Int?
    var publisher: String?
    var language: String?
    var summary: String?
    var coverImageName: String?
    /// Set once cover/metadata extraction has been attempted, so launches
    /// don't keep re-parsing books that have no embedded cover.
    var derivedDataChecked: Bool = false
    var lastLocation: String?
    /// Stamped when progress first reaches 100%; powers "books this year".
    var finishedAt: Date?
    /// JSON-encoded `ReaderPreferences`. Stored as plain data rather than a
    /// composite attribute, which SwiftData decodes unreliably.
    var preferencesData: Data?

    @Relationship(deleteRule: .cascade, inverse: \Highlight.book)
    var highlights: [Highlight]? = []

    @Relationship(deleteRule: .cascade, inverse: \Bookmark.book)
    var bookmarks: [Bookmark]? = []

    init(id: UUID = UUID(), title: String, format: BookFormat, originalFileName: String, storedFileName: String) {
        self.id = id
        self.title = title
        self.formatRaw = format.rawValue
        self.originalFileName = originalFileName
        self.storedFileName = storedFileName
    }

    var format: BookFormat { BookFormat(rawValue: formatRaw) ?? .unknown }

    var preferences: ReaderPreferences? {
        get { preferencesData.flatMap { try? JSONDecoder().decode(ReaderPreferences.self, from: $0) } }
        set { preferencesData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var displayAuthor: String {
        guard let author, !author.isEmpty else { return "Unknown author" }
        return author
    }

    var isFinished: Bool { progress >= 1 }

    /// Stable index into the stylized cover palette, so a book keeps its
    /// color until it gets a real cover.
    var coverTintIndex: Int { Int(title.stableChickenHash % 8) }

    var highlightCount: Int { highlights?.count ?? 0 }

    var sortedHighlights: [Highlight] {
        (highlights ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    var sortedBookmarks: [Bookmark] {
        (bookmarks ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    var estimatedPagesLeft: Int? {
        guard let pageCount, pageCount > 0 else { return nil }
        return max(0, pageCount - Int((Double(pageCount) * progress).rounded()))
    }
}

@Model
final class Highlight {
    var id: UUID = UUID()
    /// Spine index for EPUBs, chapter index for PDFs, 0 for text files.
    var chapterIndex: Int = 0
    var text: String = ""
    var colorRaw: String = HighlightColor.amber.rawValue
    var note: String = ""
    var createdAt: Date = Date()
    var location: String?
    var book: Book?

    init(id: UUID = UUID(), chapterIndex: Int, text: String, color: HighlightColor, note: String = "", createdAt: Date = Date(), location: String? = nil) {
        self.id = id
        self.chapterIndex = chapterIndex
        self.text = text
        self.colorRaw = color.rawValue
        self.note = note
        self.createdAt = createdAt
        self.location = location
    }

    var color: HighlightColor {
        get { HighlightColor(rawValue: colorRaw) ?? .amber }
        set { colorRaw = newValue.rawValue }
    }
}

@Model
final class Bookmark {
    var id: UUID = UUID()
    var chapterIndex: Int = 0
    var title: String = ""
    var location: String?
    var createdAt: Date = Date()
    var book: Book?

    init(id: UUID = UUID(), chapterIndex: Int, title: String, location: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.chapterIndex = chapterIndex
        self.title = title
        self.location = location
        self.createdAt = createdAt
    }
}

/// Seconds of active reading on one calendar day (`yyyy-MM-dd`).
@Model
final class ReadingDay {
    var day: String = ""
    var seconds: Int = 0

    init(day: String, seconds: Int) {
        self.day = day
        self.seconds = seconds
    }
}

enum ChickenSchema {
    static let models: [any PersistentModel.Type] = [Book.self, Highlight.self, Bookmark.self, ReadingDay.self]
}
