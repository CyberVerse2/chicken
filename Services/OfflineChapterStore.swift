import Combine
import Foundation
import AppKit
import ImageIO
import PDFKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

struct DiscoveredBook: Identifiable, Codable, Hashable {
    var id: String { url.path }
    let url: URL
    let title: String
    let format: BookFormat
    let sourceFolder: String
    let fileSize: Int64
    let author: String?
    let pageCount: Int?
    let publisher: String?
    let language: String?
    let summary: String?
    let bookScore: Int
    let classification: String

    nonisolated var isLikelyBook: Bool { bookScore >= 45 }
}

private struct DocumentMetadata {
    let title: String?
    let author: String?
    let pageCount: Int?
    let publisher: String?
    let language: String?
    let summary: String?

    nonisolated static let empty = DocumentMetadata(
        title: nil,
        author: nil,
        pageCount: nil,
        publisher: nil,
        language: nil,
        summary: nil
    )

    nonisolated func mergingFallbacks(from fallback: DocumentMetadata?) -> DocumentMetadata {
        guard let fallback else { return self }
        return DocumentMetadata(
            title: title ?? fallback.title,
            author: author ?? fallback.author,
            pageCount: pageCount ?? fallback.pageCount,
            publisher: publisher ?? fallback.publisher,
            language: language ?? fallback.language,
            summary: summary ?? fallback.summary
        )
    }
}

private struct ImportedBookResult {
    let book: Book
    let sourceID: String?
}

private struct DerivedBookUpdate {
    let bookID: UUID
    let title: String?
    let author: String?
    let pageCount: Int?
    let publisher: String?
    let language: String?
    let summary: String?
    let coverImageName: String?

    nonisolated var hasChanges: Bool {
        title != nil
            || author != nil
            || pageCount != nil
            || publisher != nil
            || language != nil
            || summary != nil
            || coverImageName != nil
    }
}

enum LibraryScanState: Equatable {
    case idle
    case scanning(checked: Int, found: Int, currentFolder: String)
    case finished(found: Int)
    case failed(String)

    var isScanning: Bool {
        if case .scanning = self { return true }
        return false
    }
}

enum ImportState: Equatable {
    case idle
    case importing(completed: Int, total: Int)
    case finished(imported: Int)

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

/// One day in the reading log. `dayStart` is the calendar start-of-day in the
/// user's current timezone; `seconds` is the cumulative active reading time.
struct DayReading: Identifiable, Hashable {
    let dayStart: Date
    let seconds: Int
    var id: TimeInterval { dayStart.timeIntervalSince1970 }

    var minutes: Int { seconds / 60 }
    var isToday: Bool { Calendar.current.isDateInToday(dayStart) }
    var dayLetter: String {
        Self.dayLetterFormatter.string(from: dayStart)
    }

    private static let dayLetterFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"  // narrow weekday: M, T, W, T, F, S, S
        return formatter
    }()
}

extension Notification.Name {
    /// Posted when the store has wiped its cover files and any view-side cache
    /// of cover images should drop its entries.
    static let chickenCoverCacheInvalidated = Notification.Name("ChickenCoverCacheInvalidated")
}

@MainActor
final class LocalLibraryStore: ObservableObject {
    @Published private(set) var books: [Book] = []
    @Published private(set) var discoveredBooks: [DiscoveredBook] = []
    @Published private(set) var scanState: LibraryScanState = .idle
    @Published private(set) var importState: ImportState = .idle
    @Published private(set) var highlights: [Highlight] = []
    @Published private(set) var bookmarks: [Bookmark] = []
    @Published private(set) var readerPreferences: [UUID: ReaderPreferences] = [:]
    @Published private(set) var coverRefreshState: CoverRefreshState = .idle
    @Published var readingTheme: ReadingTheme = .paper {
        didSet { UserDefaults.standard.set(readingTheme.rawValue, forKey: Self.readingThemePreferenceKey) }
    }
    /// Daily reading-time goal in minutes. Persisted in UserDefaults.
    @Published var dailyReadingMinutesGoal: Int = 30 {
        didSet { UserDefaults.standard.set(dailyReadingMinutesGoal, forKey: Self.dailyReadingMinutesGoalKey) }
    }
    /// End-of-year books goal — distinct from the daily reading-time goal.
    @Published var annualBookGoal: Int = 12 {
        didSet { UserDefaults.standard.set(annualBookGoal, forKey: Self.annualBookGoalPreferenceKey) }
    }
    /// Live counter for today's reading seconds. Updates while a reading
    /// session is active (every 30 seconds and on session end).
    @Published private(set) var readingSecondsToday: Int = 0
    /// Last seven calendar days, oldest first. Each entry is `(startOfDay, seconds)`.
    @Published private(set) var lastSevenDays: [DayReading] = []

    private static let readingThemePreferenceKey = "Chicken.readingTheme"
    private static let dailyReadingMinutesGoalKey = "Chicken.dailyReadingMinutesGoal"
    private static let annualBookGoalPreferenceKey = "Chicken.annualBookGoal"
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let supportedExtensions = Set(["pdf", "epub", "txt", "md", "rtf", "doc", "docx", "mobi", "azw3"])
    private var saveTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var saveHighlightsTask: Task<Void, Never>?
    private var saveBookmarksTask: Task<Void, Never>?
    private var saveReaderPreferencesTask: Task<Void, Never>?
    private var derivedDataTask: Task<Void, Never>?
    private var coverRefreshTask: Task<Void, Never>?
    private var saveReadingLogTask: Task<Void, Never>?

    private var readingLog: [String: Int] = [:]  // "yyyy-MM-dd" -> seconds
    private var sessionStart: Date?
    private var sessionTimer: Timer?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        if let storedTheme = UserDefaults.standard.string(forKey: Self.readingThemePreferenceKey),
           let theme = ReadingTheme(rawValue: storedTheme) {
            readingTheme = theme
        }
        let storedGoal = UserDefaults.standard.integer(forKey: Self.dailyReadingMinutesGoalKey)
        if storedGoal > 0 { dailyReadingMinutesGoal = storedGoal }
        let storedAnnual = UserDefaults.standard.integer(forKey: Self.annualBookGoalPreferenceKey)
        if storedAnnual > 0 { annualBookGoal = storedAnnual }
        load()
        backfillFinishedAt()
        loadHighlights()
        loadBookmarks()
        loadReaderPreferences()
        loadReadingLog()
        scheduleDerivedDataRefresh()
    }

    // MARK: Reader preferences

    func readerPreferences(for book: Book) -> ReaderPreferences {
        readerPreferences[book.id] ?? {
            var preferences = ReaderPreferences.default
            preferences.theme = readingTheme
            return preferences
        }()
    }

    func updateReaderPreferences(for book: Book, _ preferences: ReaderPreferences) {
        guard readerPreferences[book.id] != preferences else { return }
        readerPreferences[book.id] = preferences
        saveReaderPreferences()
    }

    private func loadReaderPreferences() {
        guard let data = try? Data(contentsOf: readerPreferencesURL),
              let decoded = try? decoder.decode([UUID: ReaderPreferences].self, from: data) else { return }
        readerPreferences = decoded
    }

    private func saveReaderPreferences() {
        let snapshot = readerPreferences
        let url = readerPreferencesURL
        saveReaderPreferencesTask?.cancel()
        saveReaderPreferencesTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            await Self.writeReaderPreferences(snapshot, to: url)
        }
    }

    private static func writeReaderPreferences(_ preferences: [UUID: ReaderPreferences], to url: URL) async {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            let data = try encoder.encode(preferences)
            try data.write(to: url, options: [.atomic])
        } catch {
            debugPrint("[ChickenLibrary] Reader preferences save failed: \(error.localizedDescription)")
        }
    }

    // MARK: Highlights

    func highlights(for book: Book) -> [Highlight] {
        highlights.filter { $0.bookID == book.id }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func highlights(for book: Book, chapterIndex: Int) -> [Highlight] {
        highlights.filter { $0.bookID == book.id && $0.chapterIndex == chapterIndex }
            .sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    func addHighlight(book: Book, chapterIndex: Int, text: String, color: HighlightColor, location: String? = nil) -> Highlight? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return nil }
        if highlights.contains(where: {
            $0.bookID == book.id && $0.chapterIndex == chapterIndex && $0.text == trimmed
        }) {
            return nil
        }
        let highlight = Highlight(
            bookID: book.id,
            chapterIndex: chapterIndex,
            text: trimmed,
            color: color,
            location: location
        )
        highlights.insert(highlight, at: 0)
        saveHighlights()
        return highlight
    }

    func removeHighlight(_ highlight: Highlight) {
        highlights.removeAll { $0.id == highlight.id }
        saveHighlights()
    }

    func updateHighlightNote(_ highlight: Highlight, note: String) {
        guard let index = highlights.firstIndex(where: { $0.id == highlight.id }) else { return }
        highlights[index].note = note
        saveHighlights()
    }

    private func loadHighlights() {
        guard let data = try? Data(contentsOf: highlightsURL) else {
            highlights = []
            return
        }
        highlights = (try? decoder.decode([Highlight].self, from: data)) ?? []
    }

    private func saveHighlights() {
        let snapshot = highlights
        let url = highlightsURL
        saveHighlightsTask?.cancel()
        saveHighlightsTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            await Self.writeHighlights(snapshot, to: url)
        }
    }

    nonisolated private static func writeHighlights(_ highlights: [Highlight], to url: URL) async {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            let data = try encoder.encode(highlights)
            try data.write(to: url, options: [.atomic])
        } catch {
            debugPrint("[ChickenLibrary] Highlights save failed: \(error.localizedDescription)")
        }
    }

    private var highlightsURL: URL {
        applicationSupportDirectory.appendingPathComponent("highlights.json")
    }

    // MARK: Bookmarks

    func bookmarks(for book: Book) -> [Bookmark] {
        bookmarks.filter { $0.bookID == book.id }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func hasBookmark(book: Book, chapterIndex: Int) -> Bool {
        bookmarks.contains { $0.bookID == book.id && $0.chapterIndex == chapterIndex }
    }

    @discardableResult
    func toggleBookmark(book: Book, chapterIndex: Int, title: String, location: String? = nil) -> Bookmark? {
        if let existing = bookmarks.first(where: { $0.bookID == book.id && $0.chapterIndex == chapterIndex }) {
            bookmarks.removeAll { $0.id == existing.id }
            saveBookmarks()
            return nil
        }

        let bookmark = Bookmark(
            bookID: book.id,
            chapterIndex: chapterIndex,
            title: title,
            location: location
        )
        bookmarks.insert(bookmark, at: 0)
        saveBookmarks()
        return bookmark
    }

    func removeBookmark(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        saveBookmarks()
    }

    private func loadBookmarks() {
        guard let data = try? Data(contentsOf: bookmarksURL) else {
            bookmarks = []
            return
        }
        bookmarks = (try? decoder.decode([Bookmark].self, from: data)) ?? []
    }

    private func saveBookmarks() {
        let snapshot = bookmarks
        let url = bookmarksURL
        saveBookmarksTask?.cancel()
        saveBookmarksTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            await Self.writeBookmarks(snapshot, to: url)
        }
    }

    nonisolated private static func writeBookmarks(_ bookmarks: [Bookmark], to url: URL) async {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            let data = try encoder.encode(bookmarks)
            try data.write(to: url, options: [.atomic])
        } catch {
            debugPrint("[ChickenLibrary] Bookmarks save failed: \(error.localizedDescription)")
        }
    }

    private var bookmarksURL: URL {
        applicationSupportDirectory.appendingPathComponent("bookmarks.json")
    }

    var hasBooks: Bool { !books.isEmpty }
    var hasDiscoveredBooks: Bool { !discoveredBooks.isEmpty }

    func fileURL(for book: Book) -> URL {
        documentsDirectory.appendingPathComponent(book.storedFileName)
    }

    func coverURL(for book: Book) -> URL? {
        guard let coverImageName = book.coverImageName else { return nil }
        let url = coversDirectory.appendingPathComponent(coverImageName)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func scanWholeMacForBooks() {
        guard !scanState.isScanning else { return }
        scanTask?.cancel()
        scanState = .scanning(checked: 0, found: 0, currentFolder: "Preparing scan")
        discoveredBooks = []

        let supportedExtensions = supportedExtensions
        let importedFileNames = Set(books.map(\.originalFileName))

        scanTask = Task.detached(priority: .utility) { [fileManager] in
            let roots = Self.defaultScanRoots(fileManager: fileManager)
            var checked = 0
            var found: [DiscoveredBook] = []
            var seen = Set<String>()

            for root in roots {
                guard let enumerator = fileManager.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                    options: [.skipsPackageDescendants, .skipsHiddenFiles]
                ) else { continue }

                while let url = enumerator.nextObject() as? URL {
                    guard !Task.isCancelled else { return }
                    checked += 1

                    if checked % 250 == 0 {
                        let folder = url.deletingLastPathComponent().lastPathComponent
                        let checkedSnapshot = checked
                        let foundSnapshot = found.count
                        await MainActor.run {
                            self.scanState = .scanning(checked: checkedSnapshot, found: foundSnapshot, currentFolder: folder)
                        }
                    }

                    if Self.shouldSkip(url: url, fileManager: fileManager) {
                        enumerator.skipDescendants()
                        continue
                    }

                    let fileExtension = url.pathExtension.lowercased()
                    guard supportedExtensions.contains(fileExtension) else { continue }
                    guard !importedFileNames.contains(url.lastPathComponent) else { continue }
                    guard seen.insert(url.path).inserted else { continue }

                    let format = BookFormat(fileExtension: fileExtension)
                    let values = try? url.resourceValues(forKeys: [.fileSizeKey])
                    let fileSize = Int64(values?.fileSize ?? 0)
                    let score = Self.bookScore(
                        url: url,
                        format: format,
                        fileSize: fileSize,
                        metadata: .empty
                    )
                    found.append(
                        DiscoveredBook(
                            url: url,
                            title: Self.title(from: url),
                            format: format,
                            sourceFolder: url.deletingLastPathComponent().path,
                            fileSize: fileSize,
                            author: nil,
                            pageCount: nil,
                            publisher: nil,
                            language: nil,
                            summary: nil,
                            bookScore: score,
                            classification: Self.classification(for: score)
                        )
                    )
                }
            }

            let sorted = found.sorted {
                if $0.isLikelyBook != $1.isLikelyBook { return $0.isLikelyBook && !$1.isLikelyBook }
                if $0.bookScore != $1.bookScore { return $0.bookScore > $1.bookScore }
                if $0.format != $1.format { return $0.format.rawValue < $1.format.rawValue }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }

            await MainActor.run {
                self.discoveredBooks = sorted
                self.scanState = .finished(found: sorted.count)
            }

            let enriched = await Self.enrichedDiscoveredMetadata(sorted)
            await MainActor.run {
                self.applyEnrichedDiscovered(enriched)
            }
        }
    }

    nonisolated private static func enrichedDiscoveredMetadata(_ discovered: [DiscoveredBook]) async -> [DiscoveredBook] {
        let candidates = discovered.filter { $0.format == .pdf || $0.format == .epub }
        return await withTaskGroup(of: DiscoveredBook?.self) { group in
            var iterator = candidates.makeIterator()
            let workerCount = min(4, candidates.count)
            for _ in 0..<workerCount {
                if let item = iterator.next() {
                    group.addTask { enrichedDiscoveredBook(item) }
                }
            }

            var enriched: [DiscoveredBook] = []
            while let result = await group.next() {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return enriched
                }
                if let result { enriched.append(result) }
                if let next = iterator.next() {
                    group.addTask { enrichedDiscoveredBook(next) }
                }
            }
            return enriched
        }
    }

    nonisolated private static func enrichedDiscoveredBook(_ item: DiscoveredBook) -> DiscoveredBook? {
        guard !Task.isCancelled else { return nil }
        let metadata = Self.metadata(for: item.url, format: item.format)
        guard metadata.title != nil || metadata.author != nil || metadata.pageCount != nil || metadata.publisher != nil || metadata.language != nil else {
            return nil
        }

        let score = Self.bookScore(
            url: item.url,
            format: item.format,
            fileSize: item.fileSize,
            metadata: metadata
        )

        return DiscoveredBook(
            url: item.url,
            title: metadata.title ?? item.title,
            format: item.format,
            sourceFolder: item.sourceFolder,
            fileSize: item.fileSize,
            author: metadata.author,
            pageCount: metadata.pageCount,
            publisher: metadata.publisher,
            language: metadata.language,
            summary: metadata.summary,
            bookScore: score,
            classification: Self.classification(for: score)
        )
    }

    private func applyEnrichedDiscovered(_ enriched: [DiscoveredBook]) {
        guard !enriched.isEmpty else { return }
        var byID = Dictionary(uniqueKeysWithValues: discoveredBooks.map { ($0.id, $0) })
        for item in enriched {
            byID[item.id] = item
        }

        discoveredBooks = Array(byID.values).sorted {
            if $0.isLikelyBook != $1.isLikelyBook { return $0.isLikelyBook && !$1.isLikelyBook }
            if $0.bookScore != $1.bookScore { return $0.bookScore > $1.bookScore }
            if $0.format != $1.format { return $0.format.rawValue < $1.format.rawValue }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    func importBooks(from urls: [URL]) {
        guard importState == .idle else { return }
        importURLs(urls)
    }

    func importDiscovered(_ discovered: DiscoveredBook) {
        guard importState == .idle else { return }
        importDiscoveredBatch([discovered])
    }

    func importAllDiscovered() {
        guard importState == .idle else { return }
        let current = discoveredBooks.filter(\.isLikelyBook)
        guard !current.isEmpty else { return }

        importDiscoveredBatch(current)
    }

    func dismissDiscovered(_ discovered: DiscoveredBook) {
        discoveredBooks.removeAll { $0.id == discovered.id }
    }

    // MARK: Cover refresh

    /// Wipes the on-disk cover files, clears `coverImageName` on every book,
    /// invalidates the view-side cover cache, and re-runs the same extraction
    /// path used at import time. Books whose source no longer parses as a real
    /// cover (slide-deck PDFs, etc.) end up with `coverImageName == nil` again
    /// and the UI falls back to the stylized cover — that's intentional.
    func refreshAllCovers() {
        guard !coverRefreshState.isRefreshing else { return }

        let regenerable = books.filter { $0.format == .pdf || $0.format == .epub }
        let total = regenerable.count
        guard total > 0 else {
            coverRefreshState = .finished(refreshed: 0)
            scheduleClearOfRefreshState()
            return
        }

        // Clear cover names and delete existing cover files.
        let coversDir = coversDirectory
        let oldNames = books.compactMap(\.coverImageName)
        for index in books.indices { books[index].coverImageName = nil }
        save()
        for name in oldNames {
            try? fileManager.removeItem(at: coversDir.appendingPathComponent(name))
        }

        NotificationCenter.default.post(name: .chickenCoverCacheInvalidated, object: nil)

        coverRefreshState = .refreshing(completed: 0, total: total)

        let snapshot = regenerable
        let booksDirectory = documentsDirectory
        coverRefreshTask?.cancel()
        coverRefreshTask = Task.detached(priority: .utility) {
            var completed = 0
            var refreshedCount = 0
            await withTaskGroup(of: (UUID, String?).self) { group in
                var iterator = snapshot.makeIterator()
                let workerCount = min(3, snapshot.count)
                for _ in 0..<workerCount {
                    if let book = iterator.next() {
                        group.addTask {
                            let fileURL = booksDirectory.appendingPathComponent(book.storedFileName)
                            let coverName = Self.generateCover(
                                for: fileURL,
                                format: book.format,
                                id: book.id,
                                coversDirectory: coversDir
                            )
                            return (book.id, coverName)
                        }
                    }
                }

                while let (bookID, coverName) = await group.next() {
                    guard !Task.isCancelled else {
                        group.cancelAll()
                        return
                    }
                    completed += 1
                    if coverName != nil { refreshedCount += 1 }
                    let completedSnapshot = completed
                    await MainActor.run {
                        if let coverName,
                           let bookIndex = self.books.firstIndex(where: { $0.id == bookID }) {
                            self.books[bookIndex].coverImageName = coverName
                        }
                        self.coverRefreshState = .refreshing(completed: completedSnapshot, total: snapshot.count)
                    }
                    if let book = iterator.next() {
                        group.addTask {
                            let fileURL = booksDirectory.appendingPathComponent(book.storedFileName)
                            let coverName = Self.generateCover(
                                for: fileURL,
                                format: book.format,
                                id: book.id,
                                coversDirectory: coversDir
                            )
                            return (book.id, coverName)
                        }
                    }
                }
            }

            let finalCount = refreshedCount
            await MainActor.run {
                self.save()
                self.coverRefreshState = .finished(refreshed: finalCount)
                self.scheduleClearOfRefreshState()
            }
        }
    }

    private func scheduleClearOfRefreshState() {
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if case .finished = self.coverRefreshState {
                self.coverRefreshState = .idle
            }
        }
    }

    func markOpened(_ book: Book) {
        guard let index = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[index].lastOpenedAt = Date()
        save()
    }

    // MARK: Reading session tracking

    /// Call when the reader enters a window or becomes active. Idempotent —
    /// repeated calls extend the same session.
    func beginReadingSession() {
        if sessionStart == nil { sessionStart = Date() }
        sessionTimer?.invalidate()
        // Tick every 30s to commit partial time and keep `readingSecondsToday`
        // live in the library while a session is open.
        let timer = Timer(timeInterval: 30, repeats: true) { _ in
            Task { @MainActor [weak self] in
                self?.commitSession(continuing: true)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        sessionTimer = timer
        recomputeReadingDerived()
    }

    /// Call when the reader disappears, the window resigns key, or the app
    /// backgrounds. Commits any in-flight session time.
    func endReadingSession() {
        sessionTimer?.invalidate()
        sessionTimer = nil
        commitSession(continuing: false)
    }

    private func commitSession(continuing: Bool) {
        guard let start = sessionStart else { return }
        let now = Date()
        let elapsed = Int(now.timeIntervalSince(start))
        guard elapsed >= 1 else { return }

        // If the session straddles midnight, split it across the two day keys
        // so each day's count is honest.
        let cal = Calendar.current
        let startDayStart = cal.startOfDay(for: start)
        let endDayStart = cal.startOfDay(for: now)
        if startDayStart == endDayStart {
            readingLog[Self.dayKey(for: start), default: 0] += elapsed
        } else {
            let dayBoundary = cal.date(byAdding: .day, value: 1, to: startDayStart) ?? now
            let firstChunk = max(0, Int(dayBoundary.timeIntervalSince(start)))
            let secondChunk = max(0, elapsed - firstChunk)
            if firstChunk > 0 {
                readingLog[Self.dayKey(for: start), default: 0] += firstChunk
            }
            if secondChunk > 0 {
                readingLog[Self.dayKey(for: now), default: 0] += secondChunk
            }
        }

        sessionStart = continuing ? now : nil
        recomputeReadingDerived()
        scheduleReadingLogSave()
    }

    private func recomputeReadingDerived() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var partial = 0
        if let start = sessionStart {
            // Show in-flight time in the live counter, capped to today's
            // boundary so the label doesn't briefly read tomorrow's seconds.
            let upTo = max(start, today)
            partial = max(0, Int(Date().timeIntervalSince(upTo)))
        }
        readingSecondsToday = (readingLog[Self.dayKey(for: Date())] ?? 0) + partial

        var days: [DayReading] = []
        for offset in (0..<7).reversed() {  // oldest first
            guard let dayStart = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let seconds = readingLog[Self.dayKey(for: dayStart)] ?? 0
            let live = (offset == 0) ? partial : 0
            days.append(DayReading(dayStart: dayStart, seconds: seconds + live))
        }
        lastSevenDays = days
    }

    private nonisolated static func dayKey(for date: Date) -> String {
        dayKeyFormatter.string(from: date)
    }

    private nonisolated static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func loadReadingLog() {
        guard let data = try? Data(contentsOf: readingLogURL) else {
            readingLog = [:]
            recomputeReadingDerived()
            return
        }
        readingLog = (try? decoder.decode([String: Int].self, from: data)) ?? [:]
        recomputeReadingDerived()
    }

    private func scheduleReadingLogSave() {
        let snapshot = readingLog
        let url = readingLogURL
        saveReadingLogTask?.cancel()
        saveReadingLogTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            await Self.writeReadingLog(snapshot, to: url)
        }
    }

    nonisolated private static func writeReadingLog(_ log: [String: Int], to url: URL) async {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            let data = try encoder.encode(log)
            try data.write(to: url, options: [.atomic])
        } catch {
            debugPrint("[ChickenLibrary] Reading log save failed: \(error.localizedDescription)")
        }
    }

    private var readingLogURL: URL {
        applicationSupportDirectory.appendingPathComponent("reading-log.json")
    }

    private var readerPreferencesURL: URL {
        applicationSupportDirectory.appendingPathComponent("reader-preferences.json")
    }

    func updateProgress(for book: Book, progress: Double, location: String? = nil) {
        guard let index = books.firstIndex(where: { $0.id == book.id }) else { return }
        let clamped = min(max(progress, 0), 1)
        let wasFinished = books[index].progress >= 1
        let nowFinished = clamped >= 1
        let now = Date()
        let progressChanged = abs(books[index].progress - clamped) >= 0.001
        let locationChanged = location != nil && books[index].lastLocation != location
        let finishChanged = wasFinished != nowFinished
        let shouldRefreshOpenedAt = books[index].lastOpenedAt.map { now.timeIntervalSince($0) >= 60 } ?? true
        guard progressChanged || locationChanged || finishChanged || shouldRefreshOpenedAt else { return }

        books[index].progress = clamped
        if locationChanged { books[index].lastLocation = location }
        if shouldRefreshOpenedAt { books[index].lastOpenedAt = now }
        if nowFinished && !wasFinished {
            books[index].finishedAt = now
        } else if !nowFinished && wasFinished {
            books[index].finishedAt = nil
        }
        save()
    }

    // MARK: Reading goal

    /// Books the user has finished in the current calendar year, newest first.
    var booksFinishedThisYear: [Book] {
        let year = Calendar.current.component(.year, from: Date())
        return books
            .filter { book in
                guard let finishedAt = book.finishedAt else { return false }
                return Calendar.current.component(.year, from: finishedAt) == year
            }
            .sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
    }

    /// Backfills `finishedAt` for any book that was already at 100% before this
    /// field existed. Uses `lastOpenedAt` if available so the goal counter shows
    /// something on first launch instead of zero.
    private func backfillFinishedAt() {
        var changed = false
        for index in books.indices {
            if books[index].progress >= 1, books[index].finishedAt == nil {
                books[index].finishedAt = books[index].lastOpenedAt ?? books[index].importedAt
                changed = true
            }
        }
        if changed { save() }
    }

    func delete(_ book: Book) {
        books.removeAll { $0.id == book.id }
        let removedHighlights = highlights.contains { $0.bookID == book.id }
        let removedBookmarks = bookmarks.contains { $0.bookID == book.id }
        highlights.removeAll { $0.bookID == book.id }
        bookmarks.removeAll { $0.bookID == book.id }
        try? fileManager.removeItem(at: fileURL(for: book))
        if let coverURL = coverURL(for: book) {
            try? fileManager.removeItem(at: coverURL)
        }
        save()
        if removedHighlights { saveHighlights() }
        if removedBookmarks { saveBookmarks() }
    }

    func load() {
        guard let data = try? Data(contentsOf: catalogURL) else {
            books = []
            return
        }
        books = (try? decoder.decode([Book].self, from: data)) ?? []
    }

    func save() {
        let snapshot = books.sorted {
            if ($0.coverImageName == nil) != ($1.coverImageName == nil) {
                return $0.coverImageName == nil
            }
            if $0.format != $1.format {
                return $0.format == .epub
            }
            return ($0.lastOpenedAt ?? $0.importedAt) > ($1.lastOpenedAt ?? $1.importedAt)
        }
        let url = catalogURL
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            await Self.writeCatalog(snapshot, to: url)
        }
    }

    private func saveImmediately() {
        let snapshot = books
        let url = catalogURL
        Task {
            await Self.writeCatalog(snapshot, to: url)
        }
    }

    private func importURLs(_ urls: [URL]) {
        let candidates = urls.map { ($0, Optional<DocumentMetadata>.none, Optional<String>.none) }
        importCandidates(candidates)
    }

    private func importDiscoveredBatch(_ discovered: [DiscoveredBook]) {
        let candidates = discovered.map { ($0.url, Optional(Self.metadata(from: $0)), Optional($0.id)) }
        importCandidates(candidates)
    }

    private func importCandidates(_ candidates: [(URL, DocumentMetadata?, String?)]) {
        let documentsDirectory = documentsDirectory
        let supportedExtensions = supportedExtensions
        importState = .importing(completed: 0, total: candidates.count)

        Task.detached(priority: .utility) {
            var batch: [ImportedBookResult] = []
            var importedCount = 0

            for (index, candidate) in candidates.enumerated() {
                do {
                    let result = try Self.importBookFile(
                        from: candidate.0,
                        knownMetadata: candidate.1,
                        sourceID: candidate.2,
                        documentsDirectory: documentsDirectory,
                        supportedExtensions: supportedExtensions
                    )
                    batch.append(result)
                    importedCount += 1
                } catch {
                    debugPrint("[ChickenLibrary] Import failed: \(error.localizedDescription)")
                }

                if batch.count >= 8 || index == candidates.indices.last {
                    let completed = index + 1
                    let importedBatch = batch
                    batch.removeAll(keepingCapacity: true)
                    await MainActor.run {
                        self.applyImported(importedBatch, completed: completed, total: candidates.count)
                    }
                }
            }

            let finalImportedCount = importedCount
            await MainActor.run {
                self.importState = .finished(imported: finalImportedCount)
                self.saveImmediately()
            }

            try? await Task.sleep(for: .seconds(1.2))

            await MainActor.run {
                self.importState = .idle
            }
        }
    }

    private func applyImported(_ results: [ImportedBookResult], completed: Int, total: Int) {
        guard !results.isEmpty else {
            importState = .importing(completed: completed, total: total)
            return
        }

        let importedIds = Set(results.compactMap(\.sourceID))
        books.insert(contentsOf: results.map(\.book), at: 0)
        discoveredBooks.removeAll { importedIds.contains($0.id) }
        importState = .importing(completed: completed, total: total)
        save()
        scheduleDerivedDataRefresh()
    }

    nonisolated private static func importBookFile(
        from url: URL,
        knownMetadata: DocumentMetadata?,
        sourceID: String?,
        documentsDirectory: URL,
        supportedExtensions: Set<String>
    ) throws -> ImportedBookResult {
        let sourceExtension = url.pathExtension.lowercased()
        guard supportedExtensions.contains(sourceExtension) else {
            throw ChickenImportError.unsupportedFile(url)
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: documentsDirectory, withIntermediateDirectories: true)

        let id = UUID()
        let storedName = "\(id.uuidString).\(sourceExtension)"
        let destination = documentsDirectory.appendingPathComponent(storedName)

        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: url, to: destination)
        } catch {
            throw ChickenImportError.copyFailed(url)
        }

        let format = BookFormat(fileExtension: sourceExtension)
        guard Self.canOpenBookFile(destination, format: format) else {
            try? fileManager.removeItem(at: destination)
            throw ChickenImportError.unreadableFile(url)
        }

        let metadata: DocumentMetadata
        if format == .epub {
            let freshMetadata = Self.metadata(for: destination, format: format)
            metadata = freshMetadata.mergingFallbacks(from: knownMetadata)
        } else {
            metadata = knownMetadata ?? Self.metadata(for: destination, format: format)
        }

        return ImportedBookResult(
            book: Book(
                id: id,
                title: metadata.title ?? title(from: url),
                author: metadata.author,
                format: format,
                originalFileName: url.lastPathComponent,
                storedFileName: storedName,
                importedAt: Date(),
                lastOpenedAt: nil,
                progress: 0,
                pageCount: metadata.pageCount,
                publisher: metadata.publisher,
                language: metadata.language,
                summary: metadata.summary,
                coverImageName: nil,
                lastLocation: nil,
                finishedAt: nil
            ),
            sourceID: sourceID
        )
    }

    nonisolated private static func canOpenBookFile(_ url: URL, format: BookFormat) -> Bool {
        switch format {
        case .pdf:
            return PDFDocument(url: url) != nil
        case .epub:
            return epubPackagePath(from: unzipEntry("META-INF/container.xml", from: url) ?? Data()) != nil
        case .text, .document, .unknown:
            return true
        }
    }

    private func scheduleDerivedDataRefresh() {
        let snapshot = books
        let booksDirectory = documentsDirectory
        let coversDirectory = coversDirectory

        derivedDataTask?.cancel()
        derivedDataTask = Task.detached(priority: .utility) {
            var batch: [DerivedBookUpdate] = []

            for book in snapshot {
                guard !Task.isCancelled else { return }
                guard book.format == .pdf || book.format == .epub else { continue }

                let fileURL = booksDirectory.appendingPathComponent(book.storedFileName)
                var metadata = DocumentMetadata.empty
                if book.format == .epub || book.pageCount == nil {
                    metadata = Self.metadata(for: fileURL, format: book.format)
                }

                let coverName: String?
                if book.coverImageName == nil {
                    coverName = Self.generateCover(
                        for: fileURL,
                        format: book.format,
                        id: book.id,
                        coversDirectory: coversDirectory
                    )
                } else {
                    coverName = nil
                }

                let update = DerivedBookUpdate(
                    bookID: book.id,
                    title: book.format == .epub ? metadata.title : nil,
                    author: metadata.author,
                    pageCount: metadata.pageCount,
                    publisher: metadata.publisher,
                    language: metadata.language,
                    summary: metadata.summary,
                    coverImageName: coverName
                )

                if update.hasChanges {
                    batch.append(update)
                }

                if batch.count >= 6 {
                    let updates = batch
                    batch.removeAll(keepingCapacity: true)
                    await MainActor.run {
                        self.applyDerivedBookUpdates(updates)
                    }
                }
            }

            if !batch.isEmpty {
                let updates = batch
                await MainActor.run {
                    self.applyDerivedBookUpdates(updates)
                }
            }
        }
    }

    private func applyDerivedBookUpdates(_ updates: [DerivedBookUpdate]) {
        guard !updates.isEmpty else { return }
        var changed = false
        let updatesByID = Dictionary(uniqueKeysWithValues: updates.map { ($0.bookID, $0) })

        for index in books.indices {
            guard let update = updatesByID[books[index].id] else { continue }

            if let title = update.title, !title.isEmpty, books[index].title != title {
                books[index].title = title
                changed = true
            }
            if let author = update.author, books[index].author != author {
                books[index].author = author
                changed = true
            }
            if let pageCount = update.pageCount, books[index].pageCount != pageCount {
                books[index].pageCount = pageCount
                changed = true
            }
            if let publisher = update.publisher, books[index].publisher != publisher {
                books[index].publisher = publisher
                changed = true
            }
            if let language = update.language, books[index].language != language {
                books[index].language = language
                changed = true
            }
            if let summary = update.summary, books[index].summary != summary {
                books[index].summary = summary
                changed = true
            }
            if let coverImageName = update.coverImageName, books[index].coverImageName != coverImageName {
                books[index].coverImageName = coverImageName
                changed = true
            }
        }

        if changed {
            save()
        }
    }

    nonisolated private static func metadata(from discovered: DiscoveredBook) -> DocumentMetadata {
        DocumentMetadata(
            title: discovered.title,
            author: discovered.author,
            pageCount: discovered.pageCount,
            publisher: discovered.publisher,
            language: discovered.language,
            summary: discovered.summary
        )
    }

    nonisolated private static func writeCatalog(_ books: [Book], to url: URL) async {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            let data = try encoder.encode(books)
            try data.write(to: url, options: [.atomic])
        } catch {
            debugPrint("[ChickenLibrary] Save failed: \(error.localizedDescription)")
        }
    }

    private var applicationSupportDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Chicken", isDirectory: true)
    }

    private var documentsDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Books", isDirectory: true)
    }

    private var coversDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Covers", isDirectory: true)
    }

    private var catalogURL: URL {
        applicationSupportDirectory.appendingPathComponent("library.json")
    }

    nonisolated private static func generateCover(
        for url: URL,
        format: BookFormat,
        id: UUID,
        coversDirectory: URL
    ) -> String? {
        let coverName = "\(id.uuidString).jpg"
        let destination = coversDirectory.appendingPathComponent(coverName)

        let image: NSImage?
        switch format {
        case .pdf:
            image = Self.pdfCoverImage(for: url)
        case .epub:
            if let imageData = Self.epubCoverImageData(for: url),
               Self.writeJPEG(imageData: imageData, to: destination) {
                return coverName
            }
            image = nil
        default:
            image = nil
        }

        try? FileManager.default.createDirectory(at: coversDirectory, withIntermediateDirectories: true)
        guard let image, Self.writeJPEG(image, to: destination) else { return nil }
        return coverName
    }

    nonisolated private static func pdfCoverImage(for url: URL) -> NSImage? {
        if let quickLookImage = quickLookCoverImage(for: url) {
            return quickLookImage
        }

        guard
            let document = CGPDFDocument(url as CFURL),
            let page = document.page(at: 1)
        else {
            return nil
        }

        let pageBounds = page.getBoxRect(.cropBox)
        guard pageBounds.width > 0, pageBounds.height > 0 else { return nil }

        let targetWidth: CGFloat = 520
        let scale = targetWidth / max(pageBounds.width, 1)
        let targetHeight = min(max(pageBounds.height * scale, 1), 900)
        let targetRect = CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(targetWidth),
                pixelsHigh: Int(targetHeight),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ),
            let context = NSGraphicsContext(bitmapImageRep: bitmap)?.cgContext
        else {
            return nil
        }

        context.setFillColor(NSColor.white.cgColor)
        context.fill(targetRect)
        context.saveGState()
        context.translateBy(x: 0, y: targetRect.height)
        context.scaleBy(x: 1, y: -1)
        context.concatenate(page.getDrawingTransform(.cropBox, rect: targetRect, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        context.restoreGState()

        let image = NSImage(size: NSSize(width: targetWidth, height: targetHeight))
        image.addRepresentation(bitmap)
        return image
    }

    nonisolated private static func quickLookCoverImage(for url: URL) -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 520, height: 780),
            scale: 2,
            representationTypes: .thumbnail
        )
        let semaphore = DispatchSemaphore(value: 0)
        var image: NSImage?

        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            image = representation?.nsImage
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 8)
        return image
    }

    nonisolated private static func epubCoverImageData(for url: URL) -> Data? {
        guard
            let containerData = unzipEntry("META-INF/container.xml", from: url),
            let packagePath = epubPackagePath(from: containerData),
            let packageData = unzipEntry(packagePath, from: url),
            let packageXML = String(data: packageData, encoding: .utf8)
        else {
            return nil
        }

        if let coverPath = epubCoverPath(from: packageXML, packagePath: packagePath),
           let imageData = unzipEntry(coverPath, from: url) {
            return imageData
        }

        return bestEPUBCoverImageData(from: url)
    }

    nonisolated private static func epubCoverPath(from packageXML: String, packagePath: String) -> String? {
        let href: String?

        if let coverImageHref = firstXMLAttribute(
            "href",
            in: packageXML,
            elementContaining: #"properties\s*=\s*["'][^"']*cover-image[^"']*["']"#
        ) {
            href = coverImageHref
        } else if let coverID = firstXMLAttribute("content", in: packageXML, elementContaining: #"name\s*=\s*["']cover["']"#) {
            let pattern = #"<item\b(?=[^>]*\bid\s*=\s*["']\#(NSRegularExpression.escapedPattern(for: coverID))["'])(?=[^>]*\bhref\s*=\s*["']([^"']+)["'])[^>]*>"#
            href = firstRegexCapture(pattern: pattern, in: packageXML)
        } else if let idCoverHref = firstXMLAttribute("href", in: packageXML, elementContaining: #"\bid\s*=\s*["']cover["']"#) {
            href = idCoverHref
        } else {
            href = firstRegexCapture(
                pattern: #"<item\b(?=[^>]*\bhref\s*=\s*["']([^"']*(?:cover|front|title|ttlpg|[_-]cv[ti]?)[^"']*\.(?:jpg|jpeg|png|webp))["'])(?=[^>]*\bmedia-type\s*=\s*["']image/[^"']+["'])[^>]*>"#,
                in: packageXML
            )
        }

        guard let href else { return nil }

        let packageDirectory = (packagePath as NSString).deletingLastPathComponent
        if packageDirectory.isEmpty {
            return href.removingPercentEncoding ?? href
        }
        return (packageDirectory as NSString).appendingPathComponent(href.removingPercentEncoding ?? href)
    }

    nonisolated private static func bestEPUBCoverImageData(from archiveURL: URL) -> Data? {
        let imageEntries = unzipEntryNames(from: archiveURL)
            .filter { $0.range(of: #"\.(jpe?g|png|webp)$"#, options: .regularExpression) != nil }
            .prefix(48)

        var best: (score: Double, data: Data)?

        for entry in imageEntries {
            guard let data = unzipEntry(entry, from: archiveURL),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let widthNumber = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                  let heightNumber = properties[kCGImagePropertyPixelHeight] as? NSNumber,
                  let width = Optional(CGFloat(truncating: widthNumber)),
                  let height = Optional(CGFloat(truncating: heightNumber)),
                  width >= 80,
                  height >= 120
            else {
                continue
            }

            let aspect = height / max(width, 1)
            let portraitScore = aspect >= 1.15 && aspect <= 1.9 ? 2_000_000.0 : 0
            let lower = entry.lowercased()
            let nameScore: Double
            if lower.contains("cover") || lower.contains("_cv") || lower.contains("-cv") {
                nameScore = 3_000_000
            } else if lower.contains("cvi") || lower.contains("cvt") || lower.contains("front") || lower.contains("ttlpg") || lower.contains("title") {
                nameScore = 1_500_000
            } else {
                nameScore = 0
            }
            let areaScore = Double(width * height)
            let score = nameScore + portraitScore + min(areaScore, 2_000_000)

            if best == nil || score > best!.score {
                best = (score, data)
            }
        }

        return best?.data
    }

    nonisolated private static func writeJPEG(_ image: NSImage, to url: URL) -> Bool {
        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
        else {
            return false
        }

        do {
            try jpegData.write(to: url, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    nonisolated private static func writeJPEG(imageData: Data, to url: URL) -> Bool {
        guard
            let source = CGImageSourceCreateWithData(imageData as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            )
        else {
            return false
        }

        let options: CFDictionary = [
            kCGImageDestinationLossyCompressionQuality: 0.86
        ] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        return CGImageDestinationFinalize(destination)
    }

    nonisolated private static func title(from url: URL) -> String {
        let raw = url.deletingPathExtension().lastPathComponent
        return raw.replacingOccurrences(of: "_", with: " ")
    }

    nonisolated private static func metadata(for url: URL, format: BookFormat) -> DocumentMetadata {
        switch format {
        case .pdf:
            return pdfMetadata(for: url)
        case .epub:
            return epubMetadata(for: url)
        default:
            return .empty
        }
    }

    nonisolated private static func pdfMetadata(for url: URL) -> DocumentMetadata {
        guard let document = PDFDocument(url: url) else {
            return .empty
        }

        let attributes = document.documentAttributes
        let title = cleanMetadata(attributes?[PDFDocumentAttribute.titleAttribute] as? String)
        let author = cleanMetadata(attributes?[PDFDocumentAttribute.authorAttribute] as? String)

        return DocumentMetadata(
            title: title,
            author: author,
            pageCount: document.pageCount,
            publisher: nil,
            language: nil,
            summary: nil
        )
    }

    nonisolated private static func epubMetadata(for url: URL) -> DocumentMetadata {
        guard
            let containerData = unzipEntry("META-INF/container.xml", from: url),
            let packagePath = epubPackagePath(from: containerData),
            let packageData = unzipEntry(packagePath, from: url),
            let packageMetadata = epubPackageMetadata(from: packageData)
        else {
            return .empty
        }

        return DocumentMetadata(
            title: cleanMetadata(packageMetadata.title),
            author: cleanMetadata(packageMetadata.creator),
            pageCount: nil,
            publisher: cleanMetadata(packageMetadata.publisher),
            language: cleanMetadata(packageMetadata.language),
            summary: cleanMetadata(packageMetadata.description)
        )
    }

    nonisolated private static func unzipEntry(_ entry: String, from archiveURL: URL) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", archiveURL.path, entry]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return data.isEmpty ? nil : data
    }

    nonisolated private static func unzipEntryNames(from archiveURL: URL) -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-Z", "-1", archiveURL.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8)
        else {
            return []
        }

        return output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
    }

    nonisolated private static func epubPackagePath(from data: Data) -> String? {
        guard let xml = String(data: data, encoding: .utf8) else { return nil }
        return firstXMLAttribute("full-path", in: xml)
    }

    nonisolated private static func epubPackageMetadata(from data: Data) -> EPUBPackageMetadata? {
        guard let xml = String(data: data, encoding: .utf8) else { return nil }
        return EPUBPackageMetadata(
            title: firstXMLValue(["dc:title", "title"], in: xml),
            creator: firstXMLValue(["dc:creator", "creator"], in: xml),
            publisher: firstXMLValue(["dc:publisher", "publisher"], in: xml),
            language: firstXMLValue(["dc:language", "language"], in: xml),
            description: firstXMLValue(["dc:description", "description"], in: xml)
        )
    }

    nonisolated private static func firstXMLAttribute(_ name: String, in xml: String) -> String? {
        let pattern = #"\#(name)\s*=\s*["']([^"']+)["']"#
        return firstRegexCapture(pattern: pattern, in: xml)
    }

    nonisolated private static func firstXMLAttribute(
        _ name: String,
        in xml: String,
        elementContaining requiredPattern: String
    ) -> String? {
        let pattern = #"<[^>]*(?=[^>]*\#(requiredPattern))(?=[^>]*\#(name)\s*=\s*["']([^"']+)["'])[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        guard
            let match = regex.firstMatch(in: xml, range: range),
            match.numberOfRanges > 1,
            let captureRange = Range(match.range(at: match.numberOfRanges - 1), in: xml)
        else {
            return nil
        }
        return String(xml[captureRange])
    }

    nonisolated private static func firstXMLValue(_ elementNames: [String], in xml: String) -> String? {
        for elementName in elementNames {
            let escaped = NSRegularExpression.escapedPattern(for: elementName)
            let pattern = #"<\#(escaped)(?:\s[^>]*)?>([\s\S]*?)</\#(escaped)>"#
            if let value = firstRegexCapture(pattern: pattern, in: xml) {
                return value
                    .replacingOccurrences(of: #"<!\[CDATA\[(.*?)\]\]>"#, with: "$1", options: .regularExpression)
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .replacingOccurrences(of: "&lt;", with: "<")
                    .replacingOccurrences(of: "&gt;", with: ">")
                    .replacingOccurrences(of: "&quot;", with: "\"")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    nonisolated private static func firstRegexCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard
            let match = regex.firstMatch(in: text, range: range),
            match.numberOfRanges > 1,
            let captureRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return String(text[captureRange])
    }

    nonisolated private static func cleanMetadata(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    nonisolated private static func bookScore(
        url: URL,
        format: BookFormat,
        fileSize: Int64,
        metadata: DocumentMetadata
    ) -> Int {
        var score = 0
        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        let path = url.path.lowercased()

        switch format {
        case .epub:
            score += 95
        case .pdf:
            score += 34
        case .text:
            score += 20
        case .document:
            score += 10
        case .unknown:
            score += 0
        }

        if let pageCount = metadata.pageCount {
            if pageCount >= 80 { score += 45 }
            else if pageCount >= 35 { score += 28 }
            else if pageCount >= 15 { score += 12 }
            else { score -= 35 }
        }

        if metadata.author != nil { score += 18 }
        if metadata.title != nil { score += 12 }
        if metadata.publisher != nil { score += 6 }
        if metadata.language != nil { score += 4 }
        if fileSize > 2_000_000 { score += 12 }
        else if fileSize > 800_000 { score += 8 }
        if fileSize < 120_000 { score -= 20 }

        let positiveSignals = ["book", "ebook", "library", "novel", "edition", "press", "volume"]
        if positiveSignals.contains(where: { path.contains($0) }) { score += 18 }

        let negativeSignals = [
            "invoice", "receipt", "ticket", "boarding", "statement", "contract",
            "form", "slides", "deck", "pitch", "overview", "resume", "cv",
            "certificate", "assignment", "lecture", "report", "bank", "travel"
        ]
        if negativeSignals.contains(where: { name.contains($0) || path.contains("/\($0)") }) {
            score -= 45
        }

        return min(max(score, 0), 100)
    }

    nonisolated private static func classification(for score: Int) -> String {
        if score >= 70 { return "Very likely book" }
        if score >= 45 { return "Likely book" }
        if score >= 25 { return "Needs review" }
        return "Probably not a book"
    }

    nonisolated private static func defaultScanRoots(fileManager: FileManager) -> [URL] {
        var roots = [fileManager.homeDirectoryForCurrentUser]
        let volumesURL = URL(fileURLWithPath: "/Volumes", isDirectory: true)
        if let volumes = try? fileManager.contentsOfDirectory(at: volumesURL, includingPropertiesForKeys: nil) {
            roots.append(contentsOf: volumes)
        }
        return roots
    }

    nonisolated private static func shouldSkip(url: URL, fileManager: FileManager) -> Bool {
        let name = url.lastPathComponent
        let skippedFolders = Set([
            "Library",
            "Applications",
            "System",
            "Developer",
            "node_modules",
            ".git",
            "DerivedData",
            "Build",
            "Caches",
            "Containers",
            "Group Containers"
        ])

        guard skippedFolders.contains(name) else { return false }
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

private struct EPUBPackageMetadata {
    var title: String?
    var creator: String?
    var publisher: String?
    var language: String?
    var description: String?
}
