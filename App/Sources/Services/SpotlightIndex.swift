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
    /// What's in the index, by item identifier, as of the last pass. Nil
    /// until the first pass of this launch, which rebuilds it whole.
    private var indexed: [String: Int]?

    private init() {}

    /// Updates the index shortly after the library changes, re-indexing only
    /// the books and highlights that changed. Cover thumbnails are made off
    /// the main actor: there can be hundreds of them.
    func refresh(library: LibraryStore) {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            let books = library.allBooks()

            var signatures: [String: Int] = [:]
            var bookItems: [(item: CSSearchableItem, coverURL: URL?)] = []
            var highlightItems: [CSSearchableItem] = []
            for book in books {
                let identifier = Self.bookPrefix + book.id.uuidString
                signatures[identifier] = Self.signature(of: book)
                if self.indexed?[identifier] != signatures[identifier] {
                    bookItems.append((self.item(for: book), library.coverURL(for: book)))
                }
                for highlight in book.highlights ?? [] {
                    let identifier = Self.highlightPrefix + highlight.id.uuidString
                    signatures[identifier] = Self.signature(of: highlight, in: book)
                    if self.indexed?[identifier] != signatures[identifier] {
                        highlightItems.append(self.item(for: highlight, in: book))
                    }
                }
            }
            let removed = self.indexed.map { Array(Set($0.keys).subtracting(signatures.keys)) } ?? []
            guard self.indexed == nil || !bookItems.isEmpty || !highlightItems.isEmpty || !removed.isEmpty else { return }

            let coverURLs = bookItems.map(\.coverURL)
            let thumbnails = await Task.detached(priority: .utility) {
                coverURLs.map { $0.flatMap { CoverRenderer.thumbnailJPEG(from: $0, maxPixelSize: 160) } }
            }.value
            guard !Task.isCancelled else { return }
            for (entry, thumbnail) in zip(bookItems, thumbnails) {
                entry.item.attributeSet.thumbnailData = thumbnail
            }

            let index = CSSearchableIndex.default()
            if self.indexed == nil {
                try? await index.deleteSearchableItems(withDomainIdentifiers: [Self.bookDomain, Self.highlightDomain])
            } else if !removed.isEmpty {
                try? await index.deleteSearchableItems(withIdentifiers: removed)
            }
            try? await index.indexSearchableItems(bookItems.map(\.item) + highlightItems)
            self.indexed = signatures
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

    /// Everything but the cover thumbnail, which `refresh` adds off the
    /// main actor.
    private func item(for book: Book) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = book.displayTitle
        attributes.displayName = book.displayTitle
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

        let item = CSSearchableItem(
            uniqueIdentifier: Self.bookPrefix + book.id.uuidString,
            domainIdentifier: Self.bookDomain,
            attributeSet: attributes
        )
        item.associateAppEntity(BookEntity(book), priority: book.lastOpenedAt == nil ? 1 : 10)
        return item
    }

    private func item(for highlight: Highlight, in book: Book) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        let passage = highlight.text.replacingOccurrences(of: "\n", with: " ")
        attributes.title = passage.count > 90 ? String(passage.prefix(90)) + "…" : passage
        attributes.displayName = attributes.title
        attributes.textContent = highlight.text + (highlight.note.isEmpty ? "" : "\n" + highlight.note)
        attributes.contentDescription = highlight.note.isEmpty
            ? "Highlighted in \(book.displayTitle)"
            : "\(highlight.note) — \(book.displayTitle)"
        attributes.authorNames = book.author.map { [$0] }
        attributes.contentCreationDate = highlight.createdAt
        attributes.keywords = ["highlight", "quote", book.displayTitle]
        return CSSearchableItem(
            uniqueIdentifier: Self.highlightPrefix + highlight.id.uuidString,
            domainIdentifier: Self.highlightDomain,
            attributeSet: attributes
        )
    }

    /// Changes when anything Spotlight shows for the book changes.
    private static func signature(of book: Book) -> Int {
        var hasher = Hasher()
        hasher.combine(book.title)
        hasher.combine(book.author)
        hasher.combine(book.publisher)
        hasher.combine(book.summary)
        hasher.combine(Int((book.progress * 100).rounded()))
        hasher.combine(book.lastOpenedAt)
        hasher.combine(book.coverImageName)
        return hasher.finalize()
    }

    private static func signature(of highlight: Highlight, in book: Book) -> Int {
        var hasher = Hasher()
        hasher.combine(highlight.text)
        hasher.combine(highlight.note)
        hasher.combine(book.title)
        hasher.combine(book.author)
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
