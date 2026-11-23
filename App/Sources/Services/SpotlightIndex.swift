import AppIntents
import ChickenKit
import CoreSpotlight
import os
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Puts your books and highlights in Spotlight (and Siri Suggestions): type a
/// title, an author, or a line you highlighted on the Home Screen or in
/// Spotlight on the Mac, and the result opens Chicken there.
final class SpotlightIndex {
    static let shared = SpotlightIndex()

    private static let bookDomain = "cyberverse.Chicken.books"
    private static let highlightDomain = "cyberverse.Chicken.highlights"
    private static let bookPrefix = "book:"
    private static let highlightPrefix = "highlight:"
    private static let cacheKey = "Chicken.spotlight.signatures.v2"

    private var pending: Task<Void, Never>?
    private var indexed: [String: UInt64]?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let stored = try? JSONDecoder().decode([String: UInt64].self, from: data) {
            indexed = stored
        }
    }

    func refresh(library: LibraryStore) {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            let books = library.allBooks()

            var signatures: [String: UInt64] = [:]
            var bookItems: [(item: CSSearchableItem, coverURL: URL?)] = []
            var highlightItems: [CSSearchableItem] = []
            for book in books {
                let identifier = Self.bookPrefix + book.id.uuidString
                let sig = Self.signature(of: book)
                signatures[identifier] = sig
                if self.indexed?[identifier] != sig {
                    bookItems.append((self.item(for: book), library.coverURL(for: book)))
                }
                for highlight in book.highlights ?? [] {
                    let identifier = Self.highlightPrefix + highlight.id.uuidString
                    let hSig = Self.signature(of: highlight, in: book)
                    signatures[identifier] = hSig
                    if self.indexed?[identifier] != hSig {
                        highlightItems.append(self.item(for: highlight, in: book))
                    }
                }
            }
            let removed = self.indexed.map { Array(Set($0.keys).subtracting(signatures.keys)) } ?? []
            guard self.indexed == nil || !bookItems.isEmpty || !highlightItems.isEmpty || !removed.isEmpty else { return }

            let coverURLs = bookItems.map(\.coverURL)
            let thumbnails = await Self.renderThumbnails(coverURLs)
            guard !Task.isCancelled else { return }
            for (entry, thumbnail) in zip(bookItems, thumbnails) {
                entry.item.attributeSet.thumbnailData = thumbnail
            }

            let index = CSSearchableIndex.default()
            do {
                if self.indexed == nil {
                    try await index.deleteSearchableItems(withDomainIdentifiers: [Self.bookDomain, Self.highlightDomain])
                } else if !removed.isEmpty {
                    try await index.deleteSearchableItems(withIdentifiers: removed)
                }
                let allItems = bookItems.map(\.item) + highlightItems
                if !allItems.isEmpty {
                    try await index.indexSearchableItems(allItems)
                }
                self.indexed = signatures
                if let encoded = try? JSONEncoder().encode(signatures) {
                    UserDefaults.standard.set(encoded, forKey: Self.cacheKey)
                }
            } catch {
                ChickenLog.library.error("Spotlight indexing failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    @concurrent
    private static func renderThumbnails(_ urls: [URL?]) async -> [Data?] {
        var output: [Data?] = []
        output.reserveCapacity(urls.count)
        for url in urls {
            if Task.isCancelled { return output }
            output.append(url.flatMap { CoverRenderer.thumbnailJPEG(from: $0, maxPixelSize: 160) })
        }
        return output
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
        attributes.textContent = book.summary
        var keywordList = ["book", book.format.label]
        if let author = book.author, !author.isEmpty { keywordList.append(author) }
        if let series = book.seriesName, !series.isEmpty { keywordList.append(series) }
        if let isbn = book.isbn, !isbn.isEmpty { keywordList.append(isbn) }
        if let year = book.releaseYear { keywordList.append(String(year)) }
        keywordList.append(contentsOf: book.genres)
        attributes.keywords = keywordList
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

    private static func signature(of book: Book) -> UInt64 {
        let fields = [
            book.title,
            book.author ?? "",
            book.publisher ?? "",
            book.language ?? "",
            book.isbn ?? "",
            book.seriesName ?? "",
            book.genresCSV ?? "",
            book.releaseYear.map(String.init) ?? "",
            book.formatRaw,
            book.summary ?? "",
            String(Int((book.progress * 100).rounded())),
            String(Int(book.lastOpenedAt?.timeIntervalSince1970 ?? 0)),
            book.coverImageName ?? "",
        ].joined(separator: "\u{1F}")
        return fields.stableChickenHash
    }

    private static func signature(of highlight: Highlight, in book: Book) -> UInt64 {
        [highlight.text, highlight.note, book.title, book.author ?? ""]
            .joined(separator: "\u{1F}")
            .stableChickenHash
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
