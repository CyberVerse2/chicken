import ChickenKit
import CoreData
import Foundation
import SwiftData

/// iCloud sync. The database syncs itself through CloudKit (see
/// `makeContainer`); this keeps the files behind it in step. Book files and
/// covers live in Chicken's iCloud container, where every device sees them
/// and downloads a book when it's opened. Without iCloud everything stays in
/// the local folders and works as before.
extension LibraryStore {
    func connectToICloud() {
        guard paths.syncsWithICloud && CloudFolders.isEnabledInThisBuild else {
            scheduleDerivedDataRefresh()
            return
        }
        iCloudStatus = .checking
        observeRemoteChanges()
        Task.detached(priority: .utility) { [weak self] in
            let folders = CloudFolders.resolve()
            await MainActor.run {
                guard let self else { return }
                self.cloud = folders
                self.iCloudStatus = folders == nil ? .unavailable : .on
                guard folders != nil else {
                    self.scheduleDerivedDataRefresh()
                    return
                }
                self.watchICloudFiles()
                self.moveFilesToICloud(thenRefreshDerivedData: true)
                self.mergeDuplicateBooks()
            }
        }
    }

    /// Moves books and covers from the local folders into iCloud. Only files
    /// the library knows about move, so a book that's halfway through being
    /// imported is left alone until it's in the database.
    func moveFilesToICloud(thenRefreshDerivedData refreshDerivedData: Bool = false) {
        guard let cloud else {
            if refreshDerivedData { scheduleDerivedDataRefresh() }
            return
        }
        let books = allBooks()
        let bookFiles = Set(books.map(\.storedFileName))
        let coverFiles = Set(books.compactMap(\.coverImageName))
        let paths = paths
        let previous = cloudMoveTask
        cloudMoveTask = Task.detached(priority: .utility) { [weak self] in
            await previous?.value
            CloudFolders.moveIntoICloud(from: paths.books, to: cloud.books, only: bookFiles)
            let movedCovers = CloudFolders.moveIntoICloud(from: paths.covers, to: cloud.covers, only: coverFiles)
            await MainActor.run {
                guard let self else { return }
                // A cover moved from this device is downloaded by definition;
                // record it now rather than wait for the watcher to say so.
                if !movedCovers.isEmpty {
                    self.downloadedCloudCovers?.formUnion(movedCovers)
                    self.cloudFilesGeneration += 1
                }
                if refreshDerivedData { self.scheduleDerivedDataRefresh() }
            }
        }
    }

    /// The book's file if it can be read right now, without a download.
    func readableFileURL(for book: Book) -> URL? {
        let url = fileURL(for: book)
        return CloudFolders.isDownloaded(url) ? url : nil
    }

    /// Fetches the book from iCloud if this device doesn't have it yet.
    func downloadFile(for book: Book) async throws -> URL {
        while iCloudStatus == .checking {
            try await Task.sleep(for: .milliseconds(200))
        }
        let url = fileURL(for: book)
        do {
            try await CloudFolders.download(url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            throw BookDownloadError.notInICloud(signedIn: iCloudStatus == .on)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw BookDownloadError.failed
        }
        return url
    }

    // MARK: - Watching for changes

    /// Notices covers arriving (from other devices, or downloads finishing)
    /// and book files coming or going. The watching happens on a background
    /// queue; this only hears about it when something actually changed.
    private func watchICloudFiles() {
        guard cloudWatcher == nil, let cloud else { return }
        let watcher = CloudFileWatcher(folders: cloud) { [weak self] change in
            Task { @MainActor in self?.cloudFilesDidChange(change) }
        }
        watcher.start()
        cloudWatcher = watcher
    }

    private func cloudFilesDidChange(_ change: CloudFileWatcher.Change) {
        downloadedCloudCovers = change.downloadedCovers
        if change.coversChanged {
            cloudFilesGeneration += 1
            publishWidgetSnapshot()
        }
        // A duplicate waits for the kept copy's file; this may be it.
        if change.bookFilesChanged { mergeDuplicateBooks() }
    }

    /// Books, highlights, and reading time changed on another device.
    private func observeRemoteChanges() {
        cloudObservers.append(NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.libraryDidChangeRemotely() }
        })
    }

    /// Debounced: CloudKit delivers a first sync in many small batches.
    private func libraryDidChangeRemotely() {
        cloudChangeTask?.cancel()
        cloudChangeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            self.mergeDuplicateBooks()
            self.recomputeReadingStats()
            self.publishWidgetSnapshot()
        }
    }

    // MARK: - Duplicates

    /// The same file added on two devices arrives as two books. Keeps the
    /// first one added, folds the other's reading position, highlights, and
    /// bookmarks into it, and deletes the other's copy of the file.
    func mergeDuplicateBooks() {
        let books = allBooks()
        let entries = books.map {
            DuplicateBooks.Entry(id: $0.id, fileName: $0.originalFileName, fileSize: $0.fileSize, importedAt: $0.importedAt)
        }
        var merged = false
        for group in DuplicateBooks.groups(in: entries) {
            var seen = Set<ObjectIdentifier>()
            let members = group
                .flatMap { entry in books.filter { $0.id == entry.id } }
                .filter { seen.insert(ObjectIdentifier($0)).inserted }
            // Wait until the kept copy's file has reached iCloud (or this
            // device), so the book stays readable everywhere.
            guard let keeper = members.first, CloudFolders.exists(fileURL(for: keeper)) else { continue }
            for duplicate in members.dropFirst() {
                merge(duplicate, into: keeper)
                merged = true
            }
        }
        guard merged else { return }
        save()
        publishWidgetSnapshot()
    }

    private func merge(_ duplicate: Book, into keeper: Book) {
        // Where you are follows whichever copy you read last.
        if (duplicate.lastOpenedAt ?? .distantPast) > (keeper.lastOpenedAt ?? .distantPast) {
            keeper.lastOpenedAt = duplicate.lastOpenedAt
            keeper.progress = duplicate.progress
            keeper.lastLocation = duplicate.lastLocation
            keeper.lastChapterTitle = duplicate.lastChapterTitle
            keeper.finishedAt = duplicate.finishedAt
            keeper.preferencesData = duplicate.preferencesData ?? keeper.preferencesData
        }
        keeper.lastActivityAt = max(keeper.lastActivityAt, duplicate.lastActivityAt)
        if keeper.coverImageName == nil { keeper.coverImageName = duplicate.coverImageName }

        for highlight in duplicate.highlights ?? [] {
            if keeper.highlights?.contains(where: { $0.chapterIndex == highlight.chapterIndex && $0.text == highlight.text }) == true {
                context.delete(highlight)
            } else {
                highlight.book = keeper
            }
        }
        for bookmark in duplicate.bookmarks ?? [] {
            if keeper.bookmarks?.contains(where: { $0.chapterIndex == bookmark.chapterIndex }) == true {
                context.delete(bookmark)
            } else {
                bookmark.book = keeper
            }
        }

        let keptNames = [keeper.storedFileName, keeper.coverImageName]
        let files = storedFiles(of: duplicate).filter { !keptNames.contains($0.lastPathComponent) }
        context.delete(duplicate)
        Task.detached(priority: .utility) {
            files.forEach(CloudFolders.remove)
        }
    }
}

enum BookDownloadError: LocalizedError {
    case notInICloud(signedIn: Bool)
    case failed

    var errorDescription: String? {
        switch self {
        case .notInICloud(signedIn: true):
            return "This book hasn't reached iCloud yet. Open Chicken on the device you added it from, then try again."
        case .notInICloud(signedIn: false):
            return "This book is in iCloud. Sign in to iCloud and turn it on for Chicken to read it here."
        case .failed:
            return "Chicken couldn't download this book from iCloud. Check your connection and try again."
        }
    }
}
