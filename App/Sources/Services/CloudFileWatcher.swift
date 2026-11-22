import ChickenKit
import Foundation
import os

/// Watches Chicken's iCloud folders on a background queue: which covers and
/// books are on this device, and how far along each download is. It reports
/// only when one of those changes, and fetches what this device should hold
/// (every cover; the books it keeps, or all of them) whenever it isn't here,
/// including after the system clears a file to free space.
nonisolated final class CloudFileWatcher: @unchecked Sendable {
    enum TransferState: Equatable, Sendable {
        case cloudOnly
        case downloading(Double)
        case downloaded(isUploaded: Bool)
        case failed

        var isDownloaded: Bool {
            if case .downloaded = self { return true }
            return false
        }

        var progress: Double? {
            if case .downloading(let fraction) = self { return fraction }
            return nil
        }

        var isUploaded: Bool {
            if case .downloaded(let uploaded) = self { return uploaded }
            return true
        }
    }

    struct Change: Sendable {
        /// Names of covers that can be read on this device now.
        let downloadedCovers: Set<String>
        let coversChanged: Bool
        /// Every book file in iCloud, by file name.
        let bookFiles: [String: TransferState]
        /// A book file arrived or went away.
        let bookFilesAddedOrRemoved: Bool
        /// iCloud Drive can't take some file because iCloud is full.
        let uploadsBlockedByQuota: Bool
    }

    private let folders: CloudFolders
    private let onChange: @Sendable (Change) -> Void
    private let query = NSMetadataQuery()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "Chicken iCloud files"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        return queue
    }()
    private var observers: [NSObjectProtocol] = []

    // Touched only on `queue`.
    private var downloadedCovers: Set<String>?
    private var bookFiles: [String: TransferState] = [:]
    private var requestedCovers: Set<String> = []
    private var requestedBooks: Set<String> = []
    private var uploadsBlockedByQuota = false
    private var wantsAllBooks = false
    private var wantedBooks: Set<String> = []
    private var stopped = false

    init(folders: CloudFolders, onChange: @escaping @Sendable (Change) -> Void) {
        self.folders = folders
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func start() {
        query.searchScopes = [NSMetadataQueryUbiquitousDataScope]
        query.predicate = NSPredicate(format: "%K LIKE '*'", NSMetadataItemFSNameKey)
        query.notificationBatchingInterval = 1
        query.operationQueue = queue
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: query, queue: queue) { [weak self] _ in
                self?.scan()
            })
        }
        queue.addOperation { [weak self] in
            guard let self, !self.stopped else { return }
            self.query.start()
        }
    }

    func stop() {
        let currentObservers = observers
        observers = []
        currentObservers.forEach(NotificationCenter.default.removeObserver)
        queue.addOperation { [weak self] in
            guard let self else { return }
            self.stopped = true
            self.query.stop()
        }
    }

    /// The book files this device should hold: all of them, or these.
    func keepDownloaded(all: Bool, names: Set<String>) {
        queue.addOperation { [weak self] in
            guard let self, !self.stopped else { return }
            self.wantsAllBooks = all
            self.wantedBooks = names
            self.requestedBooks.removeAll()
            self.scan()
        }
    }

    private func scan() {
        guard !stopped else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }

        var covers = Set<String>()
        var books: [String: TransferState] = [:]
        var toDownload: [URL] = []
        var overQuota = false
        for case let item as NSMetadataItem in query.results {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
            let folder = url.deletingLastPathComponent()
            // Compare by name: the query and the container can spell the same
            // path differently (`/private/var` and `/var` on iOS).
            guard folder.deletingLastPathComponent().lastPathComponent == folders.root.lastPathComponent else { continue }
            let name = url.lastPathComponent
            if let error = item.value(forAttribute: NSMetadataUbiquitousItemUploadingErrorKey) as? NSError,
               error.domain == NSCocoaErrorDomain, error.code == NSUbiquitousFileNotUploadedDueToQuotaError {
                overQuota = true
            }
            let isDownloaded = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
                == NSMetadataUbiquitousItemDownloadingStatusCurrent
            let downloadError = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingErrorKey) as? NSError
            switch folder.lastPathComponent {
            case folders.covers.lastPathComponent:
                if isDownloaded {
                    covers.insert(name)
                    requestedCovers.remove(name)
                } else if downloadError != nil {
                    requestedCovers.remove(name)
                } else if requestedCovers.insert(name).inserted {
                    toDownload.append(url)
                }
            case folders.books.lastPathComponent:
                let isDownloading = item.value(forAttribute: NSMetadataUbiquitousItemIsDownloadingKey) as? Bool ?? false
                let percent = item.value(forAttribute: NSMetadataUbiquitousItemPercentDownloadedKey) as? Double ?? 0
                let isUploaded = item.value(forAttribute: NSMetadataUbiquitousItemIsUploadedKey) as? Bool ?? true
                let state: TransferState
                if isDownloaded {
                    state = .downloaded(isUploaded: isUploaded)
                    requestedBooks.remove(name)
                } else if downloadError != nil {
                    state = .failed
                    requestedBooks.remove(name)
                } else if isDownloading {
                    state = .downloading((percent / 5).rounded(.down) * 5 / 100)
                } else {
                    state = .cloudOnly
                    if (wantsAllBooks || wantedBooks.contains(name)) && requestedBooks.insert(name).inserted {
                        toDownload.append(url)
                    }
                }
                books[name] = state
            default:
                continue
            }
        }
        for url in toDownload {
            do {
                try FileManager.default.startDownloadingUbiquitousItem(at: url)
            } catch {
                ChickenLog.sync.error("Failed to trigger iCloud download: \(error.localizedDescription, privacy: .public)")
            }
        }

        let coversChanged = covers != downloadedCovers
        let addedOrRemoved = Set(books.keys) != Set(bookFiles.keys)
        let booksChanged = books != bookFiles
        let quotaChanged = overQuota != uploadsBlockedByQuota
        downloadedCovers = covers
        bookFiles = books
        uploadsBlockedByQuota = overQuota
        guard coversChanged || booksChanged || quotaChanged else { return }
        onChange(Change(
            downloadedCovers: covers, coversChanged: coversChanged, bookFiles: books,
            bookFilesAddedOrRemoved: addedOrRemoved, uploadsBlockedByQuota: overQuota
        ))
    }
}
