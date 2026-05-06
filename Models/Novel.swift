import Foundation

// MARK: - Book format

enum BookFormat: String, Codable, CaseIterable, Hashable {
    case pdf
    case epub
    case text
    case document
    case unknown

    nonisolated init(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "pdf":
            self = .pdf
        case "epub":
            self = .epub
        case "txt", "md", "rtf":
            self = .text
        case "doc", "docx":
            self = .document
        default:
            self = .unknown
        }
    }

    nonisolated var label: String {
        switch self {
        case .pdf: return "PDF"
        case .epub: return "EPUB"
        case .text: return "Text"
        case .document: return "Document"
        case .unknown: return "File"
        }
    }

    nonisolated var systemImage: String {
        switch self {
        case .pdf: return "doc.richtext"
        case .epub: return "text.book.closed"
        case .text: return "doc.plaintext"
        case .document: return "doc.text"
        case .unknown: return "doc"
        }
    }
}

// MARK: - Book

struct Book: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var author: String?
    var format: BookFormat
    var originalFileName: String
    var storedFileName: String
    var importedAt: Date
    var lastOpenedAt: Date?
    var progress: Double
    var pageCount: Int?
    var publisher: String?
    var language: String?
    var summary: String?
    var coverImageName: String?
    var lastLocation: String?
    /// Stamped the moment `progress` first crosses 1.0. Powers the
    /// "books finished this year" counter; cleared if a user reopens
    /// the book and rolls progress back below 1.
    var finishedAt: Date?

    var displayAuthor: String {
        guard let author, !author.isEmpty else { return "Unknown author" }
        return author
    }

    /// Stable hash that maps to the cover-tint palette (so a book always paints
    /// the same color until it gets a real cover image).
    var coverTintIndex: Int {
        Int(title.stableChickenHash % 6)
    }
}

extension String {
    nonisolated var stableChickenHash: UInt64 {
        var hash: UInt64 = 5381
        for byte in utf8 { hash = hash &* 33 &+ UInt64(byte) }
        return hash
    }
}

// MARK: - Highlight

struct Highlight: Identifiable, Codable, Hashable {
    var id: UUID
    var bookID: UUID
    /// Index into the book's chapter list. For PDFs this is the page index.
    var chapterIndex: Int
    /// The exact text the user selected. Used to re-locate the span when rendering.
    var text: String
    var color: HighlightColor
    var note: String
    var createdAt: Date
    /// Stable reader location. EPUB highlights use this to jump back to the
    /// spine/progression that produced the selection.
    var location: String?

    init(
        id: UUID = UUID(),
        bookID: UUID,
        chapterIndex: Int,
        text: String,
        color: HighlightColor,
        note: String = "",
        createdAt: Date = Date(),
        location: String? = nil
    ) {
        self.id = id
        self.bookID = bookID
        self.chapterIndex = chapterIndex
        self.text = text
        self.color = color
        self.note = note
        self.createdAt = createdAt
        self.location = location
    }
}

// MARK: - Bookmark

struct Bookmark: Identifiable, Codable, Hashable {
    var id: UUID
    var bookID: UUID
    var chapterIndex: Int
    var title: String
    var location: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        bookID: UUID,
        chapterIndex: Int,
        title: String,
        location: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.bookID = bookID
        self.chapterIndex = chapterIndex
        self.title = title
        self.location = location
        self.createdAt = createdAt
    }
}
