import AppIntents
import ChickenKit
import CoreSpotlight
import Foundation
import SwiftData

/// A book in your library, as Siri, Shortcuts, and Spotlight see it.
struct BookEntity: AppEntity, IndexedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Book", numericFormat: "\(placeholder: .int) books")
    static let defaultQuery = BookQuery()

    let id: UUID

    @Property(title: "Title")
    var title: String

    @Property(title: "Author")
    var author: String

    @Property(title: "Progress")
    var progress: Double

    var coverThumbnail: Data?

    var displayRepresentation: DisplayRepresentation {
        let percent = Int((progress * 100).rounded())
        let detail = progress >= 1 ? "\(author) · Finished" : (progress > 0 ? "\(author) · \(percent)% read" : author)
        return DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(detail)",
            image: coverThumbnail.map { .init(data: $0) } ?? .init(systemName: "book.closed")
        )
    }

    init(_ book: Book, coverThumbnail: Data? = nil) {
        id = book.id
        title = book.displayTitle
        author = book.displayAuthor
        progress = book.progress
        self.coverThumbnail = coverThumbnail
    }
}

struct BookQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [BookEntity] {
        let library = LibraryStore.shared
        let pairs = identifiers.compactMap { id -> (Book, URL?)? in
            guard let book = library.book(id: id) else { return nil }
            return (book, library.coverURL(for: book))
        }
        return await Self.entitiesWithThumbnails(pairs)
    }

    @MainActor
    func entities(matching string: String) async throws -> [BookEntity] {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return try await suggestedEntities() }
        let library = LibraryStore.shared
        let matches = library.allBooks()
            .filter {
                $0.displayTitle.localizedStandardContains(trimmed) || $0.displayAuthor.localizedStandardContains(trimmed)
            }
            .sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
            .prefix(20)
        return await Self.entitiesWithThumbnails(matches.map { ($0, library.coverURL(for: $0)) })
    }

    @MainActor
    func suggestedEntities() async throws -> [BookEntity] {
        let library = LibraryStore.shared
        let books = library.allBooks()
            .sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
            .prefix(12)
        return await Self.entitiesWithThumbnails(books.map { ($0, library.coverURL(for: $0)) })
    }

    private static func entitiesWithThumbnails(_ pairs: [(Book, URL?)]) async -> [BookEntity] {
        let thumbs = await Self.renderThumbnails(pairs.map(\.1))
        return zip(pairs, thumbs).map { pair, thumb in
            BookEntity(pair.0, coverThumbnail: thumb)
        }
    }

    @concurrent
    private static func renderThumbnails(_ urls: [URL?]) async -> [Data?] {
        urls.map { $0.flatMap { CoverRenderer.thumbnailJPEG(from: $0, maxPixelSize: 120) } }
    }
}
