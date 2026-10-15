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

    init(paths: LibraryPaths = .standard(), preferences: AppPreferences = AppPreferences(), inMemory: Bool = false) {
        self.paths = paths
        self.preferences = preferences
        container = Self.makeContainer(paths: paths, inMemory: inMemory)
        folders = WatchedFolder.load(from: paths)
        migrateLegacyLibraryIfNeeded()
        recomputeReadingStats()
        scheduleDerivedDataRefresh()
        publishWidgetSnapshot()
    }

    private static func makeContainer(paths: LibraryPaths, inMemory: Bool) -> ModelContainer {
        let schema = Schema(ChickenSchema.models)
        if inMemory {
            // swiftlint:disable:next force_try
            return try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        try? paths.createDirectories()
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
        UserDefaults.standard.removeObject(forKey: LegacyMigrator.completedKey)
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

    func fileURL(for book: Book) -> URL {
        paths.bookFile(named: book.storedFileName)
    }

    func coverURL(for book: Book) -> URL? {
        guard let name = book.coverImageName else { return nil }
        let url = paths.coverFile(named: name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func save() {
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

    func updateProgress(for book: Book, progress: Double, location: String?) {
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
        let fileURL = fileURL(for: book)
        let coverURL = coverURL(for: book)
        context.delete(book)
        save()
        try? FileManager.default.removeItem(at: fileURL)
        if let coverURL { try? FileManager.default.removeItem(at: coverURL) }
        publishWidgetSnapshot()
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

struct DayReading: Identifiable, Hashable {
    let dayStart: Date
    let seconds: Int

    var id: Date { dayStart }
    var isToday: Bool { Calendar.current.isDateInToday(dayStart) }
    var narrowWeekday: String { dayStart.formatted(.dateTime.weekday(.narrow)) }
}
