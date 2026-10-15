import ChickenKit
import Foundation
import SwiftData

extension Notification.Name {
    /// Cover files were regenerated; views should drop cached images.
    nonisolated static let chickenCoversInvalidated = Notification.Name("ChickenCoversInvalidated")
}

/// Background upkeep: covers and metadata for books imported before they
/// could be extracted, and the manual "refresh covers" action.
extension LibraryStore {
    func scheduleDerivedDataRefresh() {
        let pending = allBooks()
            .filter { !$0.derivedDataChecked && ($0.format == .pdf || $0.format == .epub) }
            .map { DerivedWork(id: $0.id, fileURL: fileURL(for: $0), format: $0.format, needsCover: $0.coverImageName == nil) }
        guard !pending.isEmpty else { return }

        let covers = paths.covers
        derivedDataTask?.cancel()
        derivedDataTask = Task.detached(priority: .background) { [weak self] in
            for chunk in pending.chunked(into: 8) {
                guard !Task.isCancelled else { return }
                let results = chunk.map { $0.run(coversDirectory: covers) }
                await MainActor.run { self?.applyDerived(results) }
            }
        }
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
    /// back to the stylized cover.
    func refreshAllCovers() {
        guard !coverRefreshState.isRefreshing else { return }
        let books = allBooks().filter { $0.format == .pdf || $0.format == .epub }
        guard !books.isEmpty else { return }

        for book in books {
            if let url = coverURL(for: book) { try? FileManager.default.removeItem(at: url) }
            book.coverImageName = nil
        }
        save()
        NotificationCenter.default.post(name: .chickenCoversInvalidated, object: nil)

        let work = books.map { DerivedWork(id: $0.id, fileURL: fileURL(for: $0), format: $0.format, needsCover: true) }
        let covers = paths.covers
        coverRefreshState = .refreshing(completed: 0, total: work.count)

        Task.detached(priority: .utility) { [weak self] in
            var completed = 0
            var refreshed = 0
            for chunk in work.chunked(into: 6) {
                let names = chunk.map { ($0.id, CoverRenderer.generateCover(for: $0.fileURL, format: $0.format, id: $0.id, in: covers)) }
                completed += chunk.count
                refreshed += names.filter { $0.1 != nil }.count
                let done = completed
                await MainActor.run {
                    guard let self else { return }
                    for (id, name) in names {
                        self.book(id: id)?.coverImageName = name
                    }
                    self.coverRefreshState = .refreshing(completed: done, total: work.count)
                }
            }
            let total = refreshed
            await MainActor.run {
                self?.save()
                self?.coverRefreshState = .finished(refreshed: total)
                self?.publishWidgetSnapshot()
            }
            try? await Task.sleep(for: .seconds(3))
            await MainActor.run {
                if case .finished = self?.coverRefreshState { self?.coverRefreshState = .idle }
            }
        }
    }

    /// Total size of the managed library on disk.
    func librarySizeDescription() -> String {
        let bytes = allBooks().reduce(Int64(0)) { $0 + $1.fileSize }
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
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
