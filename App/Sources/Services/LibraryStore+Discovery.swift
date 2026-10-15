import ChickenKit
import Foundation

/// Finding books in folders the user has explicitly shared ("ask before
/// looking"), then letting them review what to import.
extension LibraryStore {
    func addFolder(_ url: URL) {
        guard let folder = WatchedFolder(url: url) else { return }
        guard !folders.contains(where: { $0.path == folder.path }) else { return }
        folders.append(folder)
        WatchedFolder.save(folders, to: paths)
        scanFolders()
    }

    func removeFolder(_ folder: WatchedFolder) {
        folders.removeAll { $0.id == folder.id }
        WatchedFolder.save(folders, to: paths)
        discoveredBooks.removeAll { $0.url.path.hasPrefix(folder.path) }
    }

    func scanFolders() {
        guard !scanState.isScanning, !folders.isEmpty else { return }
        scanTask?.cancel()
        scanState = .scanning(checked: 0, found: 0, folder: folders.first?.name ?? "")
        discoveredBooks = []

        let folders = folders
        let imported = Set(allBooks().map(\.originalFileName))

        scanTask = Task.detached(priority: .utility) { [weak self] in
            let roots = folders.compactMap { $0.startAccessing() }
            defer { roots.forEach { $0.stopAccessingSecurityScopedResource() } }

            let found = BookDiscovery.scan(roots: roots, excludingFileNames: imported) { progress in
                Task { @MainActor in
                    guard let self, self.scanState.isScanning else { return }
                    self.scanState = .scanning(checked: progress.checked, found: progress.found, folder: progress.currentFolder)
                }
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.discoveredBooks = found
                self?.scanState = .finished(found: found.count)
            }

            // Reading PDF/EPUB metadata sharpens the "is this a book?" score.
            // Do it after listing so results appear immediately.
            let enrichable = found.filter { $0.format == .pdf || $0.format == .epub }
            let enriched = await withTaskGroup(of: DiscoveredBook.self) { group in
                var results: [DiscoveredBook] = []
                var iterator = enrichable.makeIterator()
                for _ in 0..<4 {
                    guard let next = iterator.next() else { break }
                    group.addTask { next.enriched() }
                }
                for await result in group {
                    if Task.isCancelled { break }
                    results.append(result)
                    if let next = iterator.next() { group.addTask { next.enriched() } }
                }
                return results
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                let byID = Dictionary(enriched.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                self.discoveredBooks = BookDiscovery.sort(self.discoveredBooks.map { byID[$0.id] ?? $0 })
            }
        }
    }
}
