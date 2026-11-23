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
    var isbn: String?
    var releaseYear: Int?
    var seriesName: String?
    var seriesPosition: Double?
    var genresCSV: String?
    var moodsCSV: String?
    var catalogRating: Double?
    var catalogRatingsCount: Int?
    var catalogURLString: String?
    var hardcoverBookID: Int?
    var coverImageName: String?
    /// Set once cover/metadata extraction has been attempted, so launches
    /// don't keep re-parsing books that have no embedded cover.
    var derivedDataChecked: Bool = false
    var catalogChecked: Bool = false
    var catalogEnrichVersion: Int = 0
    var hasCatalogCover: Bool = false
    var lastLocation: String?
    /// Title of the chapter at `lastLocation`, recorded by the reader so
    /// Home can say where you are without opening the book.
    var lastChapterTitle: String?
    /// Stamped when progress first reaches 100%; powers "books this year".
    var finishedAt: Date?
    /// JSON-encoded `ReaderPreferences`. Stored as plain data rather than a
    /// composite attribute, which SwiftData decodes unreliably.
    var preferencesData: Data?

    @Relationship(deleteRule: .cascade, inverse: \Highlight.book)
    var highlights: [Highlight]? = []

    @Relationship(deleteRule: .cascade, inverse: \Bookmark.book)
    var bookmarks: [Bookmark]? = []

    /// Where each device last was in this book.
    @Relationship(deleteRule: .cascade, inverse: \ReadingPosition.book)
    var positions: [ReadingPosition]? = []

    @Relationship(inverse: \BookCollection.books)
    var collections: [BookCollection]? = []

    init(id: UUID = UUID(), title: String, format: BookFormat, originalFileName: String, storedFileName: String) {
        self.id = id
        self.title = title
        self.formatRaw = format.rawValue
        self.originalFileName = originalFileName
        self.storedFileName = storedFileName
    }

    var format: BookFormat { BookFormat(rawValue: formatRaw) ?? .unknown }

    private static let preferencesEncoder = JSONEncoder()
    private static let preferencesDecoder = JSONDecoder()

    var preferences: ReaderPreferences? {
        get { preferencesData.flatMap { try? Self.preferencesDecoder.decode(ReaderPreferences.self, from: $0) } }
        set { preferencesData = newValue.flatMap { try? Self.preferencesEncoder.encode($0) } }
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let extensions = [".epub", ".pdf", ".markdown", ".md", ".txt", ".rtf"]
        let lower = trimmed.lowercased()
        let cleaned = extensions.first(where: { lower.hasSuffix($0) && trimmed.count > $0.count })
            .map { String(trimmed.dropLast($0.count)) } ?? trimmed
        return cleaned.readableTitle
    }

    var displayAuthor: String {
        guard let author, !author.isEmpty else { return "Unknown author" }
        return author
    }

    enum ReadingStatus: Equatable {
        case unread
        case reading(progress: Double)
        case finished(Date?)
    }

    var readingStatus: ReadingStatus {
        if progress >= 1 { return .finished(finishedAt) }
        if progress > 0 || lastOpenedAt != nil { return .reading(progress: max(0, progress)) }
        return .unread
    }

    var isFinished: Bool { progress >= 1 }

    func markFinished(at date: Date = Date()) {
        progress = 1
        finishedAt = finishedAt ?? date
    }

    func markUnread() {
        progress = 0
        finishedAt = nil
        lastLocation = nil
        lastChapterTitle = nil
        lastOpenedAt = nil
    }

    func recordOpen(at date: Date = Date()) {
        lastOpenedAt = date
        lastActivityAt = date
    }

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

    var genres: [String] {
        Self.splitCSV(genresCSV)
    }

    var moods: [String] {
        Self.splitCSV(moodsCSV)
    }

    var seriesBadgeText: String? {
        guard let series = seriesName?.trimmingCharacters(in: .whitespacesAndNewlines), !series.isEmpty else {
            return nil
        }
        guard let pos = seriesPosition, pos > 0 else { return series }
        let formatted = pos.rounded() == pos ? String(Int(pos)) : String(format: "%.1f", pos)
        return "\(series) · Book \(formatted)"
    }

    var catalogURL: URL? {
        guard let catalogURLString, !catalogURLString.isEmpty else { return nil }
        return URL(string: catalogURLString)
    }

    var formattedRating: String? {
        guard let catalogRating, catalogRating >= 0.1 else { return nil }
        return String(format: "%.1f", catalogRating)
    }

    var isQuickRead: Bool {
        if let pageCount, pageCount > 0, pageCount <= 240 { return true }
        if !isFinished && progress > 0, let left = estimatedPagesLeft, left > 0, left <= 90 { return true }
        return false
    }

    private static func splitCSV(_ raw: String?) -> [String] {
        guard let raw, !raw.isEmpty else { return [] }
        return raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
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

/// Where one device last was in a book. Each device keeps its own row, so a
/// device opening a book can see that another read further since.
@Model
final class ReadingPosition {
    /// `AppPreferences.deviceID`.
    var device: String = ""
    /// "iPhone", "iPad", or "Mac", for saying where the position came from.
    var deviceKind: String = ""
    var progress: Double = 0
    var location: String?
    var chapterIndex: Int = 0
    var updatedAt: Date = Date()
    var book: Book?

    init(device: String, deviceKind: String) {
        self.device = device
        self.deviceKind = deviceKind
    }
}

/// A group of books you make: "To read", "Work", a series.
@Model
final class BookCollection {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var books: [Book]? = []

    init(name: String) {
        self.name = name
    }
}

/// Seconds of active reading on one calendar day (`yyyy-MM-dd`), on one
/// device. Each device keeps its own rows so two devices reading on the same
/// day never overwrite each other's time; a day's total is the sum.
@Model
final class ReadingDay {
    var day: String = ""
    var seconds: Int = 0
    /// `AppPreferences.deviceID`; nil for rows from before sync.
    var device: String?

    init(day: String, seconds: Int, device: String? = nil) {
        self.day = day
        self.seconds = seconds
        self.device = device
    }
}

enum ChickenSchema {
    static let models: [any PersistentModel.Type] = [
        Book.self, Highlight.self, Bookmark.self, ReadingDay.self, ReadingPosition.self, BookCollection.self,
    ]
}
