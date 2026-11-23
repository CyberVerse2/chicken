import ChickenKit
import Foundation
import SwiftData

extension LibraryStore {
    /// Files chosen in a file picker, dropped on the window, or opened from
    /// Finder / the Files app.
    func importFiles(_ urls: [URL]) {
        let candidates = urls.map { ImportCandidate(url: $0, metadata: nil, discoveredID: nil) }
        runImport(candidates, folderAccess: [])
    }

    /// Books found by scanning shared folders.
    func importDiscovered(_ books: [DiscoveredBook]) {
        let candidates = books.map { ImportCandidate(url: $0.url, metadata: $0.metadata, discoveredID: $0.id) }
        runImport(candidates, folderAccess: folders)
    }

    func dismissDiscovered(_ book: DiscoveredBook) {
        discoveredBooks.removeAll { $0.id == book.id }
    }

    private func runImport(_ candidates: [ImportCandidate], folderAccess: [WatchedFolder]) {
        guard !candidates.isEmpty, !importState.isImporting else { return }
        importState = .importing(completed: 0, total: candidates.count)
        importErrors = []

        let paths = paths
        let existing = Set(allBooks().map { DuplicateKey(name: $0.originalFileName, size: $0.fileSize) })

        let onBatch: @Sendable ([(ImportedBook, String?)], Int) -> Void = { [weak self] batch, completed in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.applyImported(batch)
                self.importState = .importing(completed: completed, total: candidates.count)
            }
        }
        importTask?.cancel()
        importTask = Task { [weak self] in
            let outcome = await Self.performImport(
                candidates: candidates,
                folderAccess: folderAccess,
                paths: paths,
                existing: existing,
                onBatch: onBatch
            )
            guard let self, !Task.isCancelled else { return }
            self.importErrors = outcome.errors
            self.importState = .finished(imported: outcome.imported, failed: candidates.count - outcome.imported)
            self.save()
            self.moveFilesToICloud()
            self.publishWidgetSnapshot()
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            if case .finished = self.importState { self.importState = .idle }
        }
    }

    @concurrent
    private static func performImport(
        candidates: [ImportCandidate],
        folderAccess: [WatchedFolder],
        paths: LibraryPaths,
        existing: Set<DuplicateKey>,
        onBatch: @escaping @Sendable ([(ImportedBook, String?)], Int) -> Void
    ) async -> (imported: Int, errors: [String]) {
        let scopes = folderAccess.compactMap { $0.startAccessing() }
        defer { scopes.forEach { $0.stopAccessingSecurityScopedResource() } }

        var batch: [(ImportedBook, String?)] = []
        var errors: [String] = []
        var imported = 0
        var seen = existing

        for (index, candidate) in candidates.enumerated() {
            if Task.isCancelled { break }
            do {
                let book = try BookImporter.importFile(at: candidate.url, knownMetadata: candidate.metadata, paths: paths)
                let key = DuplicateKey(name: book.originalFileName, size: book.fileSize)
                if seen.contains(key) {
                    try? FileManager.default.removeItem(at: paths.bookFile(named: book.storedFileName))
                    if let cover = book.coverImageName {
                        try? FileManager.default.removeItem(at: paths.coverFile(named: cover))
                    }
                    errors.append("\(book.originalFileName) is already in your library.")
                } else {
                    seen.insert(key)
                    batch.append((book, candidate.discoveredID))
                    imported += 1
                }
            } catch {
                errors.append(error.localizedDescription)
            }

            let isLast = index == candidates.count - 1
            if batch.count >= 6 || isLast {
                let finished = batch
                batch.removeAll()
                onBatch(finished, index + 1)
            }
        }
        return (imported, errors)
    }

    private func applyImported(_ results: [(ImportedBook, String?)]) {
        guard !results.isEmpty else { return }
        let now = Date()
        var importedIDs: [UUID] = []
        for (imported, discoveredID) in results {
            let book = Book(
                id: imported.id,
                title: imported.title,
                format: imported.format,
                originalFileName: imported.originalFileName,
                storedFileName: imported.storedFileName
            )
            book.author = imported.metadata.author
            book.fileSize = imported.fileSize
            book.pageCount = imported.metadata.pageCount
            book.publisher = imported.metadata.publisher
            book.language = imported.metadata.language
            book.summary = imported.metadata.summary
            book.isbn = imported.metadata.isbn
            if let cover = imported.cover {
                book.applyRenderedCover(cover)
            }
            book.importedAt = now
            book.lastActivityAt = now
            book.derivedDataChecked = true
            context.insert(book)
            importedIDs.append(book.id)
            if let discoveredID {
                discoveredBooks.removeAll { $0.id == discoveredID }
            }
        }
        save()
        if preferences.autoEnrichMetadata {
            enrichBooksIfNeeded(ids: importedIDs)
        }
    }
}

nonisolated private struct ImportCandidate: Sendable {
    let url: URL
    let metadata: DocumentMetadata?
    let discoveredID: String?
}

nonisolated private struct DuplicateKey: Hashable, Sendable {
    let name: String
    let size: Int64
}
