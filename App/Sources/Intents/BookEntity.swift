import AppIntents
import ChickenKit
import CoreSpotlight
import Foundation
import SwiftData

extension LibraryStore {
    /// The one library the app, its intents, and Spotlight share.
    @MainActor static let shared = LibraryStore()
}

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

    /// A small cover for Shortcuts and Siri.
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

    @MainActor
    init(_ book: Book, library: LibraryStore = .shared, includeCover: Bool = false) {
        id = book.id
        title = book.displayTitle
        author = book.displayAuthor
        progress = book.progress
        coverThumbnail = includeCover ? library.coverURL(for: book).flatMap { CoverRenderer.thumbnailJPEG(from: $0, maxPixelSize: 120) } : nil
    }
}

struct BookQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [BookEntity] {
        identifiers.compactMap { LibraryStore.shared.book(id: $0) }.map { BookEntity($0, includeCover: true) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [BookEntity] {
        let books = LibraryStore.shared.allBooks().filter {
            $0.displayTitle.localizedStandardContains(string) || $0.displayAuthor.localizedStandardContains(string)
        }
        return books.prefix(20).map { BookEntity($0, includeCover: true) }
    }

    /// Books you've opened most recently first, then the rest.
    @MainActor
    func suggestedEntities() async throws -> [BookEntity] {
        let books = LibraryStore.shared.allBooks().sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
        return books.prefix(12).map { BookEntity($0, includeCover: true) }
    }
}
