import ChickenKit
import Foundation
import Observation
import SwiftData

/// Owns the library database and the files behind it. Views read books with
/// `@Query`; anything that mutates the library or touches disk goes through
/// here. Heavy work (copying, parsing, cover rendering, scanning) runs off the
/// main actor and only the resulting values are applied on it.
@Observable
final class LibraryStore {
    let container: ModelContainer
    let paths: LibraryPaths
    let preferences: AppPreferences

    var context: ModelContext { container.mainContext }

    // Background activity surfaced in the UI.
    var importState: ImportState = .idle
    var importErrors: [String] = []
    var coverRefreshState: CoverRefreshState = .idle
    var scanState: ScanState = .idle
    var discoveredBooks: [DiscoveredBook] = []
    var folders: [WatchedFolder] = []
    var migrationSummary: String?

    // iCloud. `cloud` is set once the container is reachable; until then,
    // and whenever iCloud is off, files are found in the local folders.
    var iCloudStatus: ICloudStatus = .off
    var cloud: CloudFolders?
    /// Bumped when covers arrive from iCloud, so covers waiting on a
    /// download look again.
    var cloudFilesGeneration = 0
    /// Bumped when changes arrive from another device, so an open reader can
    /// check whether that device read further.
    var remoteChangeGeneration = 0

    // Reading time, kept live while a reader is open.
    var readingSecondsToday = 0
    var lastSevenDays: [DayReading] = []

    @ObservationIgnored var sessionStart: Date?
    @ObservationIgnored var sessionTimer: Timer?
    @ObservationIgnored var openReaderCount = 0
    @ObservationIgnored var scanTask: Task<Void, Never>?
    @ObservationIgnored var derivedDataTask: Task<Void, Never>?
    @ObservationIgnored var widgetTask: Task<Void, Never>?
    @ObservationIgnored var lastPublishedSnapshot: WidgetSnapshot?
    @ObservationIgnored var pendingProgress: (book: Book, progress: Double, location: String?)?
    @ObservationIgnored var progressFlushTask: Task<Void, Never>?
    @ObservationIgnored var cloudWatcher: CloudFileWatcher?
    /// Covers in iCloud that are on this device, kept by `cloudWatcher` so
    /// showing a cover never has to ask iCloud. Nil until its first report.
    @ObservationIgnored var downloadedCloudCovers: Set<String>?
    /// Book files in iCloud by name, from `cloudWatcher`; nil until its
    /// first report. `bookDownloads` hands out what views observe.
    @ObservationIgnored var bookFileStates: [String: CloudFileWatcher.BookFile]?
    @ObservationIgnored var bookDownloads: [String: BookDownload] = [:]
    @ObservationIgnored var openBookIDs: Set<UUID> = []
    /// Book files the user asked to download, and how many in this batch,
    /// for "Ready to read offline" when the last one lands.
    @ObservationIgnored var requestedDownloads: Set<String> = []
    @ObservationIgnored var requestedDownloadCount = 0
    // Sync health, for telling the user about problems once.
    @ObservationIgnored var syncDatabaseFull = false
    @ObservationIgnored var syncFilesFull = false
    @ObservationIgnored var syncSignedOut = false
    @ObservationIgnored var syncLastHealthy = false
    @ObservationIgnored var cloudObservers: [NSObjectProtocol] = []
    @ObservationIgnored var cloudMoveTask: Task<Void, Never>?
    @ObservationIgnored var cloudChangeTask: Task<Void, Never>?

    init(paths: LibraryPaths = .standard(), preferences: AppPreferences = AppPreferences(), inMemory: Bool = false) {
        self.paths = paths
        self.preferences = preferences
        container = Self.makeContainer(paths: paths, inMemory: inMemory)
        folders = WatchedFolder.load(from: paths)
        migrateLegacyLibraryIfNeeded()
        recomputeReadingStats()
        connectToICloud()
        publishWidgetSnapshot()
        #if DEBUG
        seedDebugLibraryIfRequested()
        addDebugFurtherPositionIfRequested()
        #endif
    }

    private static func makeContainer(paths: LibraryPaths, inMemory: Bool) -> ModelContainer {
        let schema = Schema(ChickenSchema.models)
        if inMemory {
            // swiftlint:disable:next force_try
            return try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        try? paths.createDirectories()
        // Sync through the private CloudKit database when this build can.
        // If CloudKit can't be set up, open the same store unsynced rather
        // than treating it as unreadable.
        if paths.syncsWithICloud && CloudFolders.isEnabledInThisBuild {
            let synced = ModelConfiguration("Chicken", schema: schema, url: paths.store, cloudKitDatabase: .private(CloudFolders.containerID))
            if let container = try? ModelContainer(for: schema, configurations: synced) {
                return container
            }
        }
        let configuration = ModelConfiguration("Chicken", schema: schema, url: paths.store, cloudKitDatabase: .none)
        if let container = try? ModelContainer(for: schema, configurations: configuration) {
            return container
        }
        // A store that can't be opened is set aside rather than deleted; the
        // book files themselves are untouched and the legacy JSON (if any) is
        // re-imported on the next pass.
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        for suffix in ["", "-shm", "-wal"] {
            let url = URL(fileURLWithPath: paths.store.path + suffix)
            try? FileManager.default.moveItem(at: url, to: URL(fileURLWithPath: url.path + ".unreadable-\(stamp)"))
        }
        try? FileManager.default.removeItem(at: LegacyMigrator.markerURL(in: paths))
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("Chicken could not create its library database: \(error)")
        }
    }

    // MARK: - Lookups

    func book(id: UUID) -> Book? {
        var descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func allBooks() -> [Book] {
        (try? context.fetch(FetchDescriptor<Book>())) ?? []
    }

    /// Most recently opened unfinished book: what "Continue reading" offers.
    func continueReadingBook() -> Book? {
        var descriptor = FetchDescriptor<Book>(
            predicate: #Predicate { $0.lastOpenedAt != nil && $0.progress < 1 },
            sortBy: [SortDescriptor(\.lastActivityAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Where the book's file is: in the local folder until it has moved to
    /// iCloud, then in iCloud, where it may still need downloading (see
    /// `downloadIfNeeded`).
    func fileURL(for book: Book) -> URL {
        let local = paths.bookFile(named: book.storedFileName)
        guard let cloud, !FileManager.default.fileExists(atPath: local.path) else { return local }
        return cloud.books.appendingPathComponent(book.storedFileName)
    }

    /// The cover image, if one exists and is on this device.
    func coverURL(for book: Book) -> URL? {
        guard let name = book.coverImageName else { return nil }
        let local = paths.coverFile(named: name)
        if FileManager.default.fileExists(atPath: local.path) { return local }
        guard let cloud else { return nil }
        let synced = cloud.covers.appendingPathComponent(name)
        if let downloadedCloudCovers {
            return downloadedCloudCovers.contains(name) ? synced : nil
        }
        return CloudFolders.isDownloaded(synced) ? synced : nil
    }

    func save() {
        flushPendingProgress()
        guard context.hasChanges else { return }
        try? context.save()
    }

    // MARK: - Reading state

    func markOpened(_ book: Book) {
        let now = Date()
        book.lastOpenedAt = now
        book.lastActivityAt = now
        save()
        publishWidgetSnapshot()
    }

    /// Records where the reader is. Called on every page turn, so the book
    /// itself is updated at most every 1.5 seconds: each change to it redraws
    /// every view showing it (the library stays live behind the reader) and
    /// queues it for iCloud. `save()` writes anything still waiting.
    func updateProgress(for book: Book, progress: Double, location: String?) {
        if let pending = pendingProgress, pending.book !== book { flushPendingProgress() }
        pendingProgress = (book, progress, location)
        guard progressFlushTask == nil else { return }
        progressFlushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.flushPendingProgress()
        }
    }

    func flushPendingProgress() {
        progressFlushTask?.cancel()
        progressFlushTask = nil
        guard let pending = pendingProgress else { return }
        pendingProgress = nil
        // The book may have been deleted, or merged into its duplicate.
        guard pending.book.modelContext != nil, !pending.book.isDeleted else { return }
        applyProgress(for: pending.book, progress: pending.progress, location: pending.location)
        #if os(iOS)
        ReadingActivityController.shared.refresh()
        #endif
    }

    private func applyProgress(for book: Book, progress: Double, location: String?) {
        let clamped = min(max(progress, 0), 1)
        let now = Date()
        let wasFinished = book.isFinished
        let nowFinished = clamped >= 1
        let progressChanged = abs(book.progress - clamped) >= 0.001
        let locationChanged = location != nil && book.lastLocation != location
        let refreshOpened = book.lastOpenedAt.map { now.timeIntervalSince($0) >= 60 } ?? true
        guard progressChanged || locationChanged || wasFinished != nowFinished || refreshOpened else { return }

        book.progress = clamped
        if locationChanged { book.lastLocation = location }
        if refreshOpened {
            book.lastOpenedAt = now
            book.lastActivityAt = now
        }
        if nowFinished && !wasFinished {
            book.finishedAt = now
        } else if !nowFinished && wasFinished {
            book.finishedAt = nil
        }
        recordPosition(for: book, progress: clamped, location: location)
        publishWidgetSnapshot()
    }

    /// "Mark as Finished" / "Mark as Unread" from the library.
    func setFinished(_ finished: Bool, for book: Book) {
        if finished {
            book.progress = 1
            book.finishedAt = book.finishedAt ?? Date()
        } else {
            book.progress = 0
            book.finishedAt = nil
            book.lastLocation = nil
        }
        save()
        publishWidgetSnapshot()
    }

    func setPreferences(_ preferences: ReaderPreferences, for book: Book) {
        guard book.preferences != preferences else { return }
        book.preferences = preferences
    }

    // MARK: - Highlights and bookmarks

    @discardableResult
    func addHighlight(to book: Book, chapterIndex: Int, text: String, color: HighlightColor, location: String?) -> Highlight? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return nil }
        if let existing = book.highlights?.first(where: { $0.chapterIndex == chapterIndex && $0.text == trimmed }) {
            existing.color = color
            save()
            return existing
        }
        let highlight = Highlight(chapterIndex: chapterIndex, text: trimmed, color: color, location: location)
        highlight.book = book
        context.insert(highlight)
        save()
        return highlight
    }

    func removeHighlight(_ highlight: Highlight) {
        context.delete(highlight)
        save()
    }

    func updateNote(_ note: String, on highlight: Highlight) {
        highlight.note = note
        save()
    }

    func bookmark(in book: Book, chapterIndex: Int) -> Bookmark? {
        book.bookmarks?.first { $0.chapterIndex == chapterIndex }
    }

    func toggleBookmark(in book: Book, chapterIndex: Int, title: String, location: String?) {
        if let existing = bookmark(in: book, chapterIndex: chapterIndex) {
            context.delete(existing)
        } else {
            let bookmark = Bookmark(chapterIndex: chapterIndex, title: title, location: location)
            bookmark.book = book
            context.insert(bookmark)
        }
        save()
    }

    func removeBookmark(_ bookmark: Bookmark) {
        context.delete(bookmark)
        save()
    }

    // MARK: - Removing books

    func delete(_ book: Book) {
        let files = storedFiles(of: book)
        preferences.keptBookIDs.remove(book.id)
        context.delete(book)
        save()
        Task.detached(priority: .utility) {
            files.forEach(CloudFolders.remove)
        }
        publishWidgetSnapshot()
    }

    /// The book's file and cover, wherever each is, including copies iCloud
    /// knows about but hasn't downloaded.
    func storedFiles(of book: Book) -> [URL] {
        var files = [paths.bookFile(named: book.storedFileName)]
        if let name = book.coverImageName { files.append(paths.coverFile(named: name)) }
        if let cloud {
            files.append(cloud.books.appendingPathComponent(book.storedFileName))
            if let name = book.coverImageName { files.append(cloud.covers.appendingPathComponent(name)) }
        }
        return files.filter(CloudFolders.exists)
    }
}

// MARK: - State types

enum ImportState: Equatable {
    case idle
    case importing(completed: Int, total: Int)
    case finished(imported: Int, failed: Int)

    var isImporting: Bool {
        if case .importing = self { return true }
        return false
    }
}

enum CoverRefreshState: Equatable {
    case idle
    case refreshing(completed: Int, total: Int)
    case finished(refreshed: Int)

    var isRefreshing: Bool {
        if case .refreshing = self { return true }
        return false
    }
}

enum ScanState: Equatable {
    case idle
    case scanning(checked: Int, found: Int, folder: String)
    case finished(found: Int)

    var isScanning: Bool {
        if case .scanning = self { return true }
        return false
    }
}

enum ICloudStatus: Equatable {
    /// This library doesn't sync (tests, `CHICKEN_LIBRARY_ROOT` clones).
    case off
    case checking
    /// Signed out of iCloud, or iCloud is turned off for Chicken.
    case unavailable
    case on
}

struct DayReading: Identifiable, Hashable {
    let dayStart: Date
    let seconds: Int

    var id: Date { dayStart }
    var isToday: Bool { Calendar.current.isDateInToday(dayStart) }
    var narrowWeekday: String { dayStart.formatted(.dateTime.weekday(.narrow)) }
}
