import Foundation

/// Watches Chicken's iCloud folders on a background queue: which covers and
/// books are on this device, and how far along each download is. It reports
/// only when one of those changes, and fetches what this device should hold
/// (every cover; the books it keeps, or all of them) whenever it isn't here,
/// including after the system clears a file to free space.
nonisolated final class CloudFileWatcher: @unchecked Sendable {
    struct BookFile: Equatable, Sendable {
        var isDownloaded: Bool
        /// 0...1 while downloading, in steps of 5%; nil otherwise.
        var progress: Double?
        var isUploaded: Bool
    }

    struct Change: Sendable {
        /// Names of covers that can be read on this device now.
        let downloadedCovers: Set<String>
        let coversChanged: Bool
        /// Every book file in iCloud, by file name.
        let bookFiles: [String: BookFile]
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
    private var bookFiles: [String: BookFile] = [:]
    private var requestedCovers: Set<String> = []
    private var requestedBooks: Set<String> = []
    private var uploadsBlockedByQuota = false
    private var wantsAllBooks = false
    private var wantedBooks: Set<String> = []

    init(folders: CloudFolders, onChange: @escaping @Sendable (Change) -> Void) {
        self.folders = folders
        self.onChange = onChange
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
        queue.addOperation { [weak self] in self?.query.start() }
    }

    /// The book files this device should hold: all of them, or these.
    func keepDownloaded(all: Bool, names: Set<String>) {
        queue.addOperation { [weak self] in
            guard let self else { return }
            self.wantsAllBooks = all
            self.wantedBooks = names
            self.scan()
        }
    }

    private func scan() {
        query.disableUpdates()
        defer { query.enableUpdates() }

        var covers = Set<String>()
        var books: [String: BookFile] = [:]
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
            switch folder.lastPathComponent {
            case folders.covers.lastPathComponent:
                if isDownloaded {
                    covers.insert(name)
                    requestedCovers.remove(name)
                } else if requestedCovers.insert(name).inserted {
                    toDownload.append(url)
                }
            case folders.books.lastPathComponent:
                let isDownloading = item.value(forAttribute: NSMetadataUbiquitousItemIsDownloadingKey) as? Bool ?? false
                let percent = item.value(forAttribute: NSMetadataUbiquitousItemPercentDownloadedKey) as? Double ?? 0
                books[name] = BookFile(
                    isDownloaded: isDownloaded,
                    progress: isDownloading && !isDownloaded ? (percent / 5).rounded(.down) * 5 / 100 : nil,
                    isUploaded: item.value(forAttribute: NSMetadataUbiquitousItemIsUploadedKey) as? Bool ?? true
                )
                if isDownloaded {
                    requestedBooks.remove(name)
                } else if (wantsAllBooks || wantedBooks.contains(name)) && requestedBooks.insert(name).inserted {
                    toDownload.append(url)
                }
            default:
                continue
            }
        }
        for url in toDownload {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
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
