import ChickenKit
import Foundation
import SwiftData

/// Background upkeep: covers and metadata for books imported before they
/// could be extracted, and the manual "refresh covers" action.
extension LibraryStore {
    func scheduleDerivedDataRefresh() {
        let pending = allBooks()
            .filter { !$0.derivedDataChecked && ($0.format == .pdf || $0.format == .epub) }
            .map { DerivedWork(id: $0.id, fileURL: fileURL(for: $0), format: $0.format, needsCover: $0.coverImageName == nil) }
            .filter { CloudFolders.isDownloaded($0.fileURL) }
        guard !pending.isEmpty else { return }

        let covers = paths.covers
        derivedDataTask?.cancel()
        derivedDataTask = Task { [weak self] in
            for chunk in pending.chunked(into: 8) {
                guard !Task.isCancelled else { return }
                let results = await Self.extractDerived(chunk: chunk, covers: covers)
                guard !Task.isCancelled, let self else { return }
                self.applyDerived(results)
            }
            self?.moveFilesToICloud()
        }
    }

    @concurrent
    private static func extractDerived(chunk: [DerivedWork], covers: URL) async -> [DerivedResult] {
        chunk.map { $0.run(coversDirectory: covers) }
    }

    private func applyDerived(_ results: [DerivedResult]) {
        for result in results {
            guard let book = book(id: result.id) else { continue }
            let metadata = result.metadata
            if book.format == .epub, let title = metadata.title, !title.isEmpty { book.title = title }
            if let author = metadata.author { book.author = author }
            if let pageCount = metadata.pageCount { book.pageCount = pageCount }
            if let publisher = metadata.publisher { book.publisher = publisher }
            if let language = metadata.language { book.language = language }
            if let summary = metadata.summary { book.summary = summary }
            if let cover = result.coverImageName { book.coverImageName = cover }
            book.derivedDataChecked = true
        }
        save()
    }

    /// Re-extracts every cover. Books whose source has no usable cover fall
    /// back to the stylized cover. Books still in iCloud keep the cover they
    /// have rather than being downloaded for this.
    func refreshAllCovers() {
        guard !coverRefreshState.isRefreshing else { return }
        let books = allBooks().filter { ($0.format == .pdf || $0.format == .epub) && readableFileURL(for: $0) != nil }
        guard !books.isEmpty else { return }

        var staleCovers: [URL] = []
        for book in books {
            staleCovers += storedFiles(of: book).filter { $0.lastPathComponent == book.coverImageName }
            book.coverImageName = nil
        }
        save()
        CoverImageCache.shared.invalidate()
        coversGeneration += 1

        let work = books.map { DerivedWork(id: $0.id, fileURL: fileURL(for: $0), format: $0.format, needsCover: true) }
        let covers = paths.covers
        coverRefreshState = .refreshing(completed: 0, total: work.count)

        coverRefreshTask?.cancel()
        coverRefreshTask = Task { [weak self] in
            await CloudFolders.removeAll(staleCovers)
            var completed = 0
            var refreshed = 0
            for chunk in work.chunked(into: 6) {
                guard !Task.isCancelled else { return }
                let names = await Self.generateCovers(chunk: chunk, covers: covers)
                guard !Task.isCancelled, let self else { return }
                completed += chunk.count
                refreshed += names.filter { $0.1 != nil }.count
                for (id, name) in names {
                    self.book(id: id)?.coverImageName = name
                }
                self.coverRefreshState = .refreshing(completed: completed, total: work.count)
            }
            guard !Task.isCancelled, let self else { return }
            self.save()
            self.coverRefreshState = .finished(refreshed: refreshed)
            self.moveFilesToICloud()
            self.publishWidgetSnapshot()
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            if case .finished = self.coverRefreshState { self.coverRefreshState = .idle }
        }
    }

    @concurrent
    private static func generateCovers(chunk: [DerivedWork], covers: URL) async -> [(UUID, String?)] {
        chunk.map { ($0.id, CoverRenderer.generateCover(for: $0.fileURL, format: $0.format, id: $0.id, in: covers)) }
    }

    /// Total size of the managed library on disk.
    func librarySizeDescription(for books: [Book]? = nil) -> String {
        let source = books ?? allBooks()
        let bytes = source.reduce(Int64(0)) { $0 + $1.fileSize }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

nonisolated private struct DerivedWork: Sendable {
    let id: UUID
    let fileURL: URL
    let format: BookFormat
    let needsCover: Bool

    func run(coversDirectory: URL) -> DerivedResult {
        DerivedResult(
            id: id,
            metadata: DocumentMetadataReader.metadata(for: fileURL, format: format),
            coverImageName: needsCover ? CoverRenderer.generateCover(for: fileURL, format: format, id: id, in: coversDirectory) : nil
        )
    }
}

nonisolated private struct DerivedResult: Sendable {
    let id: UUID
    let metadata: DocumentMetadata
    let coverImageName: String?
}

extension Array {
    nonisolated func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
