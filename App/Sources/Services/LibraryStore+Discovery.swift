import ChickenKit
import Foundation

/// Finding books in folders the user has explicitly shared ("ask before
/// looking"), then letting them review what to import.
extension LibraryStore {
    func addFolder(_ url: URL) {
        addFolders([url])
    }

    /// Shares several folders at once and scans them together.
    func addFolders(_ urls: [URL]) {
        var added = false
        for url in urls {
            guard let folder = WatchedFolder(url: url) else { continue }
            guard !folders.contains(where: { $0.path == folder.path }) else { continue }
            folders.append(folder)
            added = true
        }
        guard added else { return }
        WatchedFolder.save(folders, to: paths)
        scanTask?.cancel()
        scanState = .idle
        scanFolders()
    }

    func removeFolder(_ folder: WatchedFolder) {
        scanTask?.cancel()
        scanTask = nil
        if scanState.isScanning { scanState = .idle }
        folders.removeAll { $0.id == folder.id }
        WatchedFolder.save(folders, to: paths)
        let prefix = folder.path.hasSuffix("/") ? folder.path : folder.path + "/"
        discoveredBooks.removeAll { $0.url.path == folder.path || $0.url.path.hasPrefix(prefix) }
    }

    func scanFolders() {
        guard !scanState.isScanning, !folders.isEmpty else { return }
        scanTask?.cancel()
        scanState = .scanning(checked: 0, found: 0, folder: folders.first?.name ?? "")
        discoveredBooks = []

        let folders = folders
        let imported = Set(allBooks().map(\.originalFileName))

        let reportProgress: @Sendable (BookDiscovery.Progress) -> Void = { [weak self] progress in
            Task { @MainActor [weak self] in
                guard let self, case .scanning(let currentChecked, _, _) = self.scanState,
                      progress.checked >= currentChecked
                else { return }
                self.scanState = .scanning(checked: progress.checked, found: progress.found, folder: progress.currentFolder)
            }
        }
        scanTask = Task { [weak self] in
            let found = await Self.scanInBackground(folders: folders, imported: imported, onProgress: reportProgress)
            guard let self, !Task.isCancelled else { return }
            self.discoveredBooks = found

            let enrichable = found.filter { $0.format == .pdf || $0.format == .epub }
            if enrichable.isEmpty {
                self.scanState = .finished(found: found.count)
                return
            }

            self.scanState = .enriching(found: found.count)
            let enriched = await Self.enrichInBackground(enrichable, folders: folders)
            guard !Task.isCancelled else { return }
            let byID = Dictionary(enriched.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            self.discoveredBooks = BookDiscovery.sort(self.discoveredBooks.map { byID[$0.id] ?? $0 })
            self.scanState = .finished(found: self.discoveredBooks.count)
        }
    }

    @concurrent
    private static func scanInBackground(
        folders: [WatchedFolder],
        imported: Set<String>,
        onProgress: @escaping @Sendable (BookDiscovery.Progress) -> Void
    ) async -> [DiscoveredBook] {
        let roots = folders.compactMap { $0.startAccessing() }
        defer { roots.forEach { $0.stopAccessingSecurityScopedResource() } }
        return BookDiscovery.scan(roots: roots, excludingFileNames: imported, progress: onProgress)
    }

    @concurrent
    private static func enrichInBackground(_ books: [DiscoveredBook], folders: [WatchedFolder]) async -> [DiscoveredBook] {
        let roots = folders.compactMap { $0.startAccessing() }
        defer { roots.forEach { $0.stopAccessingSecurityScopedResource() } }
        return await withTaskGroup(of: DiscoveredBook.self) { group in
            var results: [DiscoveredBook] = []
            var iterator = books.makeIterator()
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
    }
}
