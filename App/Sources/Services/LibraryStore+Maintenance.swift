import ChickenKit
import Foundation
import SwiftData

/// Background upkeep: covers and metadata for books imported before they
/// could be extracted, and the manual "refresh covers" action.
extension LibraryStore {
    func scheduleCoverMetadataBackfill() {
        let pending: [BackfillWork] = allBooks().compactMap { book in
            guard book.coverImageName != nil,
                  (book.coverAspectRatio == nil || book.coverDominantHex == nil || book.coverPreviewData == nil),
                  let url = coverURL(for: book)
            else { return nil }
            return BackfillWork(id: book.id, coverURL: url, origin: book.coverOrigin)
        }
        guard !pending.isEmpty else { return }

        coverBackfillTask?.cancel()
        coverBackfillTask = Task { [weak self] in
            var changed = false
            for chunk in pending.chunked(into: 6) {
                guard !Task.isCancelled else { return }
                let results = await Self.inspectCoverChunk(chunk)
                guard !Task.isCancelled, let self else { return }
                var staleFiles: [URL] = []
                for result in results {
                    guard let book = self.book(id: result.id) else { continue }
                    let invalidPDFOrLandscape = !result.origin.isTrustedArtwork
                        && (result.looksLikeTextPage || result.metrics.aspectRatio > CoverMetrics.maxAcceptedAspectRatio)
                    if invalidPDFOrLandscape {
                        if let name = book.coverImageName {
                            staleFiles += self.storedFiles(of: book).filter { $0.lastPathComponent == name }
                        }
                        book.clearCover()
                        changed = true
                    } else {
                        book.coverOrigin = result.origin
                        book.coverAspectRatio = result.metrics.aspectRatio
                        book.coverDominantHex = Int(result.metrics.dominantColor.hex)
                        book.coverHasLegibleText = result.metrics.hasLegibleText
                        book.coverPreviewData = result.previewData
                        changed = true
                    }
                }
                if !staleFiles.isEmpty {
                    await CloudFolders.removeAll(staleFiles)
                }
                self.save()
            }
            guard !Task.isCancelled, let self, changed else { return }
            self.coversGeneration += 1
            self.publishWidgetSnapshot()
        }
    }

    @concurrent
    private static func inspectCoverChunk(_ chunk: [BackfillWork]) async -> [BackfillResult] {
        chunk.compactMap { item in
            guard let inspected = CoverRenderer.inspectCover(at: item.coverURL, origin: item.origin, detectText: true) else {
                return nil
            }
            return BackfillResult(
                id: item.id,
                origin: item.origin,
                metrics: inspected.metrics,
                previewData: inspected.previewData,
                looksLikeTextPage: inspected.looksLikeTextPage
            )
        }
    }

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
            if let isbn = metadata.isbn { book.isbn = isbn }
            if let cover = result.renderedCover,
               book.coverOrigin.canBeReplacedAutomatically(by: cover.origin) {
                book.applyRenderedCover(cover)
            }
            book.derivedDataChecked = true
        }
        save()
    }

    /// Re-extracts every cover. Books whose source has no usable cover fall
    /// back to the stylized cover. Books still in iCloud keep the cover they
    /// have rather than being downloaded for this.
    func refreshAllCovers() {
        guard !coverRefreshState.isRefreshing else { return }
        let books = allBooks().filter {
            ($0.format == .pdf || $0.format == .epub)
                && $0.coverOrigin != .custom
                && readableFileURL(for: $0) != nil
        }
        guard !books.isEmpty else { return }

        var staleCovers: [URL] = []
        for book in books {
            staleCovers += storedFiles(of: book).filter { $0.lastPathComponent == book.coverImageName }
            book.clearCover()
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
                let rendered = await Self.generateCovers(chunk: chunk, covers: covers)
                guard !Task.isCancelled, let self else { return }
                completed += chunk.count
                refreshed += rendered.filter { $0.1 != nil }.count
                for (id, cover) in rendered {
                    if let cover, let book = self.book(id: id) {
                        book.applyRenderedCover(cover)
                    }
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
    private static func generateCovers(chunk: [DerivedWork], covers: URL) async -> [(UUID, RenderedCover?)] {
        chunk.map { ($0.id, CoverRenderer.renderCover(for: $0.fileURL, format: $0.format, id: $0.id, in: covers)) }
    }

    /// Total size of the managed library on disk.
    func librarySizeDescription(for books: [Book]? = nil) -> String {
        let source = books ?? allBooks()
        let bytes = source.reduce(Int64(0)) { $0 + $1.fileSize }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

nonisolated private struct BackfillWork: Sendable {
    let id: UUID
    let coverURL: URL
    let origin: CoverOrigin
}

nonisolated private struct BackfillResult: Sendable {
    let id: UUID
    let origin: CoverOrigin
    let metrics: CoverMetrics
    let previewData: Data?
    let looksLikeTextPage: Bool
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
            renderedCover: needsCover ? CoverRenderer.renderCover(for: fileURL, format: format, id: id, in: coversDirectory) : nil
        )
    }
}

nonisolated private struct DerivedResult: Sendable {
    let id: UUID
    let metadata: DocumentMetadata
    let renderedCover: RenderedCover?
}

extension Array {
    nonisolated func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
