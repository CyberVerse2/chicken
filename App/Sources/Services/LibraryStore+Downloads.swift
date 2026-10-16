import ChickenKit
import Foundation
import Observation

/// Whether one book's file is on this device. One object per book, so a
/// cover following its download redraws on its own.
@Observable
final class BookDownload {
    /// The book opens without the network.
    var isOnDevice: Bool
    /// 0...1 while downloading.
    var progress: Double?
    /// iCloud has the file, so this device's copy can be removed.
    var isUploaded: Bool

    init(isOnDevice: Bool, progress: Double? = nil, isUploaded: Bool = true) {
        self.isOnDevice = isOnDevice
        self.progress = progress
        self.isUploaded = isUploaded
    }

    fileprivate func update(isOnDevice: Bool, progress: Double?, isUploaded: Bool) {
        // Observation reports every assignment; only assign what changed.
        if self.isOnDevice != isOnDevice { self.isOnDevice = isOnDevice }
        if self.progress != progress { self.progress = progress }
        if self.isUploaded != isUploaded { self.isUploaded = isUploaded }
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
        let state = fileState(named: name)
        let download = BookDownload(isOnDevice: state.isOnDevice, progress: state.progress, isUploaded: state.isUploaded)
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
        Task.detached(priority: .userInitiated) {
            for url in urls { try? FileManager.default.startDownloadingUbiquitousItem(at: url) }
        }
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
        Task.detached(priority: .utility) {
            for url in urls { try? FileManager.default.evictUbiquitousItem(at: url) }
        }
    }

    func setDownloadsAllBooks(_ on: Bool) {
        preferences.downloadsAllBooks = on
        updateWantedDownloads()
    }

    /// Books on this device and the space their files take.
    func downloadedBooks() -> (count: Int, bytes: Int64) {
        let books = allBooks().filter(isOnDevice)
        return (books.count, books.reduce(0) { $0 + $1.fileSize })
    }

    /// The reader marks the book it has open, so its file isn't removed
    /// from under it.
    func setOpen(_ open: Bool, _ book: Book) {
        if open { openBookIDs.insert(book.id) } else { openBookIDs.remove(book.id) }
    }

    // MARK: From the watcher

    /// Tells the watcher which book files to keep on this device.
    func updateWantedDownloads() {
        let kept = preferences.keptBookIDs
        let names = Set(allBooks().filter { kept.contains($0.id) }.map(\.storedFileName))
        cloudWatcher?.keepDownloaded(all: preferences.downloadsAllBooks, names: names)
    }

    func applyBookFileStates(_ states: [String: CloudFileWatcher.BookFile]) {
        bookFileStates = states
        for (name, download) in bookDownloads {
            let state = fileState(named: name)
            download.update(isOnDevice: state.isOnDevice, progress: state.progress, isUploaded: state.isUploaded)
        }
        finishRequestedDownloads(states)
    }

    // MARK: Downloads the user asked for

    /// Books the user chose to download join the current batch; "Download
    /// all books" and opening a book don't come through here.
    private func noteRequestedDownloads(_ books: [Book]) {
        let added = Set(books.map(\.storedFileName)).subtracting(requestedDownloads)
        requestedDownloads.formUnion(added)
        requestedDownloadCount += added.count
    }

    /// When the batch's last book lands, says so once for the whole batch.
    private func finishRequestedDownloads(_ states: [String: CloudFileWatcher.BookFile]) {
        guard !requestedDownloads.isEmpty else { return }
        for name in requestedDownloads {
            guard let state = states[name] else {
                // Removed meanwhile: it no longer counts.
                requestedDownloads.remove(name)
                requestedDownloadCount -= 1
                continue
            }
            if state.isDownloaded { requestedDownloads.remove(name) }
        }
        guard requestedDownloads.isEmpty else { return }
        ChickenNotifications.shared.downloadsFinished(count: requestedDownloadCount)
        requestedDownloadCount = 0
    }

    /// Until the watcher's first report, every book counts as here, so
    /// covers don't flash cloud marks at launch. A file iCloud doesn't know
    /// is either still in the local folder or hasn't arrived yet.
    private func fileState(named name: String) -> (isOnDevice: Bool, progress: Double?, isUploaded: Bool) {
        guard let states = bookFileStates else { return (true, nil, true) }
        if let file = states[name] { return (file.isDownloaded, file.progress, file.isUploaded) }
        let isLocal = FileManager.default.fileExists(atPath: paths.bookFile(named: name).path)
        return (isLocal, nil, !isLocal)
    }
}
