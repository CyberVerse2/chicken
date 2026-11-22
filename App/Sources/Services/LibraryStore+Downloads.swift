import ChickenKit
import Foundation
import Observation

/// Whether one book's file is on this device. One object per book, so a
/// cover following its download redraws on its own.
@Observable
final class BookDownload {
    var status: CloudFileWatcher.TransferState

    var isOnDevice: Bool { status.isDownloaded }
    var progress: Double? { status.progress }
    var isUploaded: Bool { status.isUploaded }

    init(status: CloudFileWatcher.TransferState) {
        self.status = status
    }

    fileprivate func update(to newStatus: CloudFileWatcher.TransferState) {
        if status != newStatus { status = newStatus }
    }
}

/// Which books are on this device, and keeping them there. Only matters
/// with iCloud: without it every book is local.
extension LibraryStore {
    /// Nil when the library doesn't sync, so every book is on this device.
    func download(for book: Book) -> BookDownload? {
        guard cloud != nil else { return nil }
        let name = book.storedFileName
        if let existing = bookDownloads[name] { return existing }
        let download = BookDownload(status: fileTransferState(named: name))
        bookDownloads[name] = download
        return download
    }

    func isOnDevice(_ book: Book) -> Bool {
        download(for: book)?.isOnDevice ?? true
    }

    func isKept(_ book: Book) -> Bool {
        preferences.keptBookIDs.contains(book.id)
    }

    // MARK: Actions

    func startDownload(_ books: [Book]) {
        guard let cloud else { return }
        let wanted = books.filter { !isOnDevice($0) }
        noteRequestedDownloads(wanted)
        let urls = wanted.map { cloud.books.appendingPathComponent($0.storedFileName) }
        guard !urls.isEmpty else { return }
        Task { await CloudFolders.startDownloadingAll(urls) }
    }

    /// Kept books are downloaded, and fetched again if the system clears
    /// them to free space.
    func setKept(_ kept: Bool, for books: [Book]) {
        let ids = Set(books.map(\.id))
        if kept {
            preferences.keptBookIDs.formUnion(ids)
            noteRequestedDownloads(books.filter { !isOnDevice($0) })
        } else {
            preferences.keptBookIDs.subtract(ids)
        }
        updateWantedDownloads()
    }

    /// The copy here can go when iCloud has it, it isn't kept, and it isn't
    /// open. With "Download all" on it would only come straight back.
    func canRemoveDownload(_ book: Book) -> Bool {
        guard let download = download(for: book), download.isOnDevice, download.isUploaded else { return false }
        return !preferences.downloadsAllBooks && !isKept(book) && !openBookIDs.contains(book.id)
    }

    func removeDownload(_ books: [Book]) {
        guard let cloud else { return }
        let urls = books.filter(canRemoveDownload).map { cloud.books.appendingPathComponent($0.storedFileName) }
        guard !urls.isEmpty else { return }
        Task { await CloudFolders.evictAll(urls) }
    }

    func setDownloadsAllBooks(_ on: Bool) {
        preferences.downloadsAllBooks = on
        updateWantedDownloads()
    }

    /// Books on this device and the space their files take.
    func downloadedBooks(in books: [Book]? = nil) -> (count: Int, bytes: Int64) {
        let source = books ?? allBooks()
        let onDevice = source.filter(isOnDevice)
        return (onDevice.count, onDevice.reduce(0) { $0 + $1.fileSize })
    }

    /// The reader marks the book it has open, so its file isn't removed
    /// from under it.
    func setOpen(_ open: Bool, _ book: Book) {
        if open {
            openBookIDs.insert(book.id)
            if isAppActive { resumeReadingSession() }
        } else {
            openBookIDs.remove(book.id)
            if openBookIDs.isEmpty { pauseReadingSession() }
        }
    }

    // MARK: From the watcher

    func updateWantedDownloads() {
        let kept = preferences.keptBookIDs
        let names = Set(allBooks().filter { kept.contains($0.id) }.map(\.storedFileName))
        cloudWatcher?.keepDownloaded(all: preferences.downloadsAllBooks, names: names)
    }

    func applyBookFileStates(_ states: [String: CloudFileWatcher.TransferState]) {
        bookFileStates = states
        for (name, download) in bookDownloads {
            download.update(to: fileTransferState(named: name))
        }
        finishRequestedDownloads(states)
    }

    // MARK: Downloads the user asked for

    private func noteRequestedDownloads(_ books: [Book]) {
        let added = Set(books.map(\.storedFileName)).subtracting(requestedDownloads)
        requestedDownloads.formUnion(added)
        requestedDownloadCount += added.count
    }

    private func finishRequestedDownloads(_ states: [String: CloudFileWatcher.TransferState]) {
        guard !requestedDownloads.isEmpty else { return }
        for name in requestedDownloads {
            guard let state = states[name] else {
                requestedDownloads.remove(name)
                requestedDownloadCount = max(0, requestedDownloadCount - 1)
                continue
            }
            switch state {
            case .downloaded:
                requestedDownloads.remove(name)
            case .failed:
                requestedDownloads.remove(name)
                requestedDownloadCount = max(0, requestedDownloadCount - 1)
            case .cloudOnly, .downloading:
                break
            }
        }
        guard requestedDownloads.isEmpty else { return }
        if requestedDownloadCount > 0 {
            ChickenNotifications.shared.downloadsFinished(count: requestedDownloadCount)
        }
        requestedDownloadCount = 0
    }

    private func fileTransferState(named name: String) -> CloudFileWatcher.TransferState {
        guard let states = bookFileStates else { return .downloaded(isUploaded: true) }
        if let file = states[name] { return file }
        let isLocal = FileManager.default.fileExists(atPath: paths.bookFile(named: name).path)
        return isLocal ? .downloaded(isUploaded: false) : .cloudOnly
    }
}
