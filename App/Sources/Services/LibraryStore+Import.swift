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

        Task.detached(priority: .userInitiated) { [weak self] in
            // Discovered files live inside shared folders, whose security
            // scope has to be open while they're copied.
            let scopes = folderAccess.compactMap { $0.startAccessing() }
            defer { scopes.forEach { $0.stopAccessingSecurityScopedResource() } }

            var batch: [(ImportedBook, String?)] = []
            var errors: [String] = []
            var imported = 0
            var seen = existing

            for (index, candidate) in candidates.enumerated() {
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
                    let completed = index + 1
                    await MainActor.run {
                        self?.applyImported(finished)
                        self?.importState = .importing(completed: completed, total: candidates.count)
                    }
                }
            }

            let failed = candidates.count - imported
            let summaryErrors = errors
            await MainActor.run {
                guard let self else { return }
                self.importErrors = summaryErrors
                self.importState = .finished(imported: imported, failed: failed)
                self.save()
                self.moveFilesToICloud()
                self.publishWidgetSnapshot()
            }
            try? await Task.sleep(for: .seconds(2.5))
            await MainActor.run {
                if case .finished = self?.importState { self?.importState = .idle }
            }
        }
    }

    private func applyImported(_ results: [(ImportedBook, String?)]) {
        guard !results.isEmpty else { return }
        let now = Date()
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
            book.coverImageName = imported.coverImageName
            book.importedAt = now
            book.lastActivityAt = now
            book.derivedDataChecked = true
            context.insert(book)
            if let discoveredID {
                discoveredBooks.removeAll { $0.id == discoveredID }
            }
        }
        save()
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
