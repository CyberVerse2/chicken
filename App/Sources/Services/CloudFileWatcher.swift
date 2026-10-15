import Foundation

/// Watches Chicken's iCloud folders on a background queue: which covers are
/// on this device, and when book files come or go. It reports only when one
/// of those changes, not for every upload or download progress tick, and
/// asks iCloud to fetch each new cover once.
nonisolated final class CloudFileWatcher: @unchecked Sendable {
    struct Change: Sendable {
        /// Names of covers that can be read on this device now.
        let downloadedCovers: Set<String>
        let coversChanged: Bool
        let bookFilesChanged: Bool
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
    private var bookFiles: Set<String> = []
    private var requestedCovers: Set<String> = []

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

    private func scan() {
        query.disableUpdates()
        defer { query.enableUpdates() }

        var covers = Set<String>()
        var books = Set<String>()
        var toDownload: [URL] = []
        for case let item as NSMetadataItem in query.results {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
            let folder = url.deletingLastPathComponent()
            // Compare by name: the query and the container can spell the same
            // path differently (`/private/var` and `/var` on iOS).
            guard folder.deletingLastPathComponent().lastPathComponent == folders.root.lastPathComponent else { continue }
            let name = url.lastPathComponent
            switch folder.lastPathComponent {
            case folders.covers.lastPathComponent:
                let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
                if status == NSMetadataUbiquitousItemDownloadingStatusCurrent {
                    covers.insert(name)
                } else if requestedCovers.insert(name).inserted {
                    toDownload.append(url)
                }
            case folders.books.lastPathComponent:
                books.insert(name)
            default:
                continue
            }
        }
        // Covers are small and the library shows them all.
        for url in toDownload {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }

        let coversChanged = covers != downloadedCovers
        let bookFilesChanged = books != bookFiles
        downloadedCovers = covers
        bookFiles = books
        guard coversChanged || bookFilesChanged else { return }
        onChange(Change(downloadedCovers: covers, coversChanged: coversChanged, bookFilesChanged: bookFilesChanged))
    }
}
