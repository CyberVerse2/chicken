import AppIntents
import ChickenKit
import CoreSpotlight
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Puts your books and highlights in Spotlight (and Siri Suggestions): type a
/// title, an author, or a line you highlighted on the Home Screen or in
/// Spotlight on the Mac, and the result opens Chicken there.
@MainActor
final class SpotlightIndex {
    static let shared = SpotlightIndex()

    private static let bookDomain = "cyberverse.Chicken.books"
    private static let highlightDomain = "cyberverse.Chicken.highlights"
    private static let bookPrefix = "book:"
    private static let highlightPrefix = "highlight:"

    private var pending: Task<Void, Never>?
    private var lastSignature: Int?

    private init() {}

    /// Rebuilds the index shortly after the library changes. Cheap enough
    /// to run whole: a few hundred small items.
    func refresh(library: LibraryStore) {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            let books = library.allBooks()
            let signature = Self.signature(of: books)
            guard signature != self.lastSignature else { return }
            self.lastSignature = signature

            let items = books.map { self.item(for: $0, library: library) }
                + books.flatMap { book in (book.highlights ?? []).map { self.item(for: $0, in: book) } }
            let index = CSSearchableIndex.default()
            try? await index.deleteSearchableItems(withDomainIdentifiers: [Self.bookDomain, Self.highlightDomain])
            try? await index.indexSearchableItems(items)
        }
    }

    /// What a Spotlight result asks to open.
    enum Target {
        case book(UUID)
        case highlight(UUID)
    }

    static func target(for activity: NSUserActivity) -> Target? {
        guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return nil }
        if identifier.hasPrefix(bookPrefix), let id = UUID(uuidString: String(identifier.dropFirst(bookPrefix.count))) {
            return .book(id)
        }
        if identifier.hasPrefix(highlightPrefix), let id = UUID(uuidString: String(identifier.dropFirst(highlightPrefix.count))) {
            return .highlight(id)
        }
        return nil
    }

    // MARK: Items

    private func item(for book: Book, library: LibraryStore) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = book.title
        attributes.displayName = book.title
        attributes.authorNames = book.author.map { [$0] }
        attributes.creator = book.author
        attributes.publishers = book.publisher.map { [$0] }
        attributes.languages = book.language.map { [$0] }
        var description = book.displayAuthor
        if book.isFinished {
            description += " · Finished"
        } else if book.progress > 0 {
            description += " · \(Int((book.progress * 100).rounded()))% read"
        }
        attributes.contentDescription = description
        // Searchable, but Spotlight's one result line is for who and how far.
        attributes.textContent = book.summary
        attributes.keywords = ["book", book.format.label] + (book.author.map { [$0] } ?? [])
        attributes.lastUsedDate = book.lastOpenedAt
        attributes.thumbnailData = library.coverURL(for: book).flatMap { CoverRenderer.thumbnailJPEG(from: $0, maxPixelSize: 160) }

        let item = CSSearchableItem(
            uniqueIdentifier: Self.bookPrefix + book.id.uuidString,
            domainIdentifier: Self.bookDomain,
            attributeSet: attributes
        )
        item.associateAppEntity(BookEntity(book, library: library), priority: book.lastOpenedAt == nil ? 1 : 10)
        return item
    }

    private func item(for highlight: Highlight, in book: Book) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        let passage = highlight.text.replacingOccurrences(of: "\n", with: " ")
        attributes.title = passage.count > 90 ? String(passage.prefix(90)) + "…" : passage
        attributes.displayName = attributes.title
        attributes.textContent = highlight.text + (highlight.note.isEmpty ? "" : "\n" + highlight.note)
        attributes.contentDescription = highlight.note.isEmpty
            ? "Highlighted in \(book.title)"
            : "\(highlight.note) — \(book.title)"
        attributes.authorNames = book.author.map { [$0] }
        attributes.contentCreationDate = highlight.createdAt
        attributes.keywords = ["highlight", "quote", book.title]
        return CSSearchableItem(
            uniqueIdentifier: Self.highlightPrefix + highlight.id.uuidString,
            domainIdentifier: Self.highlightDomain,
            attributeSet: attributes
        )
    }

    /// Changes when anything Spotlight shows changes.
    private static func signature(of books: [Book]) -> Int {
        var hasher = Hasher()
        for book in books {
            hasher.combine(book.id)
            hasher.combine(book.title)
            hasher.combine(book.author)
            hasher.combine(Int((book.progress * 100).rounded()))
            hasher.combine(book.coverImageName)
            for highlight in book.highlights ?? [] {
                hasher.combine(highlight.id)
                hasher.combine(highlight.note)
            }
        }
        return hasher.finalize()
    }
}

extension View {
    /// Keeps Spotlight current and opens what its results point at.
    func spotlightIndexing(library: LibraryStore, bookCount: Int, highlightCount: Int, open: @escaping (SpotlightIndex.Target) -> Void) -> some View {
        onAppear { SpotlightIndex.shared.refresh(library: library) }
            .onChange(of: bookCount) { SpotlightIndex.shared.refresh(library: library) }
            .onChange(of: highlightCount) { SpotlightIndex.shared.refresh(library: library) }
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                if let target = SpotlightIndex.target(for: activity) { open(target) }
            }
    }
}
