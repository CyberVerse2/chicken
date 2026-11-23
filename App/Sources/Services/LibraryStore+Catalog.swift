import ChickenKit
import Foundation
import SwiftData

extension LibraryStore {
    func applyCatalogMatch(
        _ rawMatch: BookCatalogMatch,
        to book: Book,
        replaceCover: Bool,
        replaceExistingFields: Bool
    ) async {
        let match = await BookCatalogClient.shared.hydrateDetails(for: rawMatch)
        let coversDirectory = paths.covers
        let shouldReplaceCover = (replaceCover || book.coverImageName == nil) && match.coverURL != nil

        var downloadedCoverName: String?
        var staleCoverFiles: [URL] = []
        if shouldReplaceCover, let coverURL = match.coverURL {
            if replaceCover, let existingName = book.coverImageName {
                staleCoverFiles = storedFiles(of: book).filter { $0.lastPathComponent == existingName }
            }
            if let data = await BookCatalogClient.shared.downloadCoverData(from: coverURL) {
                downloadedCoverName = await Self.encodeCoverData(data, bookID: book.id, directory: coversDirectory)
            }
        }

        if replaceExistingFields {
            if !match.title.isEmpty { book.title = match.title }
            if let author = match.authorLine { book.author = author }
            if let publisher = match.publisher { book.publisher = publisher }
            if let language = match.language { book.language = language }
            if let pageCount = match.pageCount { book.pageCount = pageCount }
            if let summary = match.summary { book.summary = summary }
            if let isbn = match.isbn { book.isbn = isbn }
        } else {
            if let author = match.authorLine, (book.author ?? "").isEmpty { book.author = author }
            if let publisher = match.publisher, (book.publisher ?? "").isEmpty { book.publisher = publisher }
            if let language = match.language, (book.language ?? "").isEmpty { book.language = language }
            if let pageCount = match.pageCount, (book.pageCount ?? 0) <= 0 { book.pageCount = pageCount }
            if let summary = match.summary, (book.summary ?? "").isEmpty { book.summary = summary }
            if let isbn = match.isbn, (book.isbn ?? "").isEmpty { book.isbn = isbn }
        }

        if let downloadedCoverName {
            if !staleCoverFiles.isEmpty {
                await CloudFolders.removeAll(staleCoverFiles)
            }
            book.coverImageName = downloadedCoverName
            CoverImageCache.shared.invalidate()
            coversGeneration += 1
        }

        save()
        moveFilesToICloud()
        publishWidgetSnapshot()
    }

    func enrichMissingMetadata() {
        let candidates = allBooks().filter(Self.needsCatalogEnrichment)
        enqueueEnrichment(for: candidates)
    }

    func enrichBooksIfNeeded(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let idSet = Set(ids)
        let candidates = allBooks().filter { idSet.contains($0.id) && Self.needsCatalogEnrichment($0) }
        enqueueEnrichment(for: candidates)
    }

    private func enqueueEnrichment(for candidates: [Book]) {
        guard !candidates.isEmpty, !catalogEnrichState.isEnriching else { return }
        let items = candidates.map {
            EnrichmentWork(
                id: $0.id,
                query: BookCatalogQuery(title: $0.displayTitle, author: $0.author, isbn: $0.isbn),
                needsCover: $0.coverImageName == nil
            )
        }
        let token = CatalogTokenStore.loadHardcoverToken()
        let coversDirectory = paths.covers
        catalogEnrichState = .enriching(completed: 0, total: items.count)

        catalogEnrichTask?.cancel()
        catalogEnrichTask = Task { [weak self] in
            var completed = 0
            var updated = 0
            for (index, item) in items.enumerated() {
                if Task.isCancelled { return }
                if index > 0 {
                    try? await Task.sleep(for: .milliseconds(400))
                    if Task.isCancelled { return }
                }
                let result = await Self.fetchEnrichment(item: item, token: token, coversDirectory: coversDirectory)
                guard !Task.isCancelled, let self else { return }
                completed += 1
                if let match = result.match, let book = self.book(id: item.id) {
                    var didUpdate = false
                    if let author = match.authorLine, (book.author ?? "").isEmpty {
                        book.author = author
                        didUpdate = true
                    }
                    if let publisher = match.publisher, (book.publisher ?? "").isEmpty {
                        book.publisher = publisher
                        didUpdate = true
                    }
                    if let language = match.language, (book.language ?? "").isEmpty {
                        book.language = language
                        didUpdate = true
                    }
                    if let pageCount = match.pageCount, (book.pageCount ?? 0) <= 0 {
                        book.pageCount = pageCount
                        didUpdate = true
                    }
                    if let summary = match.summary, (book.summary ?? "").isEmpty {
                        book.summary = summary
                        didUpdate = true
                    }
                    if let isbn = match.isbn, (book.isbn ?? "").isEmpty {
                        book.isbn = isbn
                        didUpdate = true
                    }
                    if let coverName = result.coverImageName, book.coverImageName == nil {
                        book.coverImageName = coverName
                        CoverImageCache.shared.invalidate()
                        self.coversGeneration += 1
                        didUpdate = true
                    }
                    if didUpdate { updated += 1 }
                }
                self.catalogEnrichState = .enriching(completed: completed, total: items.count)
            }
            guard !Task.isCancelled, let self else { return }
            if updated > 0 {
                self.save()
                self.moveFilesToICloud()
                self.publishWidgetSnapshot()
            }
            self.catalogEnrichState = .finished(updated: updated)
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            if case .finished = self.catalogEnrichState { self.catalogEnrichState = .idle }
        }
    }

    private static func needsCatalogEnrichment(_ book: Book) -> Bool {
        (book.summary ?? "").isEmpty
            || (book.author ?? "").isEmpty
            || (book.publisher ?? "").isEmpty
            || (book.pageCount ?? 0) <= 0
            || book.coverImageName == nil
    }

    @concurrent
    private static func encodeCoverData(_ data: Data, bookID: UUID, directory: URL) async -> String? {
        CoverRenderer.saveCover(from: data, id: bookID, in: directory)
    }

    @concurrent
    private static func fetchEnrichment(
        item: EnrichmentWork,
        token: String?,
        coversDirectory: URL
    ) async -> (match: BookCatalogMatch?, coverImageName: String?) {
        guard let match = await BookCatalogClient.shared.bestMatch(for: item.query, hardcoverToken: token) else {
            return (nil, nil)
        }
        var coverName: String?
        if item.needsCover, let coverURL = match.coverURL,
           let data = await BookCatalogClient.shared.downloadCoverData(from: coverURL) {
            coverName = CoverRenderer.saveCover(from: data, id: item.id, in: coversDirectory)
        }
        return (match, coverName)
    }
}

nonisolated private struct EnrichmentWork: Sendable {
    let id: UUID
    let query: BookCatalogQuery
    let needsCover: Bool
}
