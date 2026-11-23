import ChickenKit
import Foundation
import Observation

enum ReadingMode: String, CaseIterable, Identifiable {
    case scroll
    case paged
    case spread

    var id: String { rawValue }

    var label: String {
        switch self {
        case .scroll: "Scroll"
        case .paged: "Pages"
        case .spread: "Spread"
        }
    }

    var systemImage: String {
        switch self {
        case .scroll: "scroll"
        case .paged: "book.pages"
        case .spread: "book"
        }
    }

    var isHorizontal: Bool { self != .scroll }
}

struct ReaderChapter: Identifiable, Hashable {
    let id: Int
    let title: String
    var subtitle: String?
    var level: Int = 0
}

struct ReaderSelection: Equatable {
    let text: String
    let chapterIndex: Int
    let location: String?
}

struct ReaderFootnote: Equatable, Identifiable {
    let id = UUID()
    let label: String
    let text: String
    let chapterIndex: Int?
    let fragment: String?
}

struct ReaderImagePreview: Equatable, Identifiable {
    let id = UUID()
    let url: URL
    let alt: String
}

struct ReaderPosition: Equatable {
    var totalPages: Int?
    var currentPage: Int?
    var chapterProgress: Double?
    var chapterPage: Int?
    var chapterPageCount: Int?
}

enum ReaderLoadStatus: Equatable {
    case loading
    case ready
    case failed(String)

    var errorMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

protocol ReaderEngine: AnyObject {
    func goToChapter(_ index: Int)
    func seek(to progress: Double)
    func jump(to location: String?, chapterIndex: Int)
    func search(_ query: String, backwards: Bool)
    func clearSelection()
    func refreshHighlights()
    func captureLocation()

    func readAloudPassages(after: String?) async -> [SpokenPassage]
    func revealPassage(_ id: String)
    func endReadingAloud()
}

struct SpokenPassage: Equatable {
    let id: String
    let text: String
}

@Observable
final class ReaderModel {
    let book: Book
    @ObservationIgnored let library: LibraryStore
    @ObservationIgnored weak var engine: (any ReaderEngine)?
    @ObservationIgnored private(set) lazy var readAloud = ReadAloudController(model: self)
    @ObservationIgnored var initialJumpTarget: JumpTarget?
    @ObservationIgnored private var wasAlreadyFinishedOnOpen: Bool
    @ObservationIgnored private var paceAnchorPage: Int?
    @ObservationIgnored private var paceAnchorDate: Date?
    @ObservationIgnored private var savePreferencesTask: Task<Void, Never>?
    @ObservationIgnored let sessionOpenedAt = Date()

    var chapters: [ReaderChapter] = [] {
        didSet { recordChapterTitle() }
    }
    var chapterIndex: Int {
        didSet { recordChapterTitle() }
    }
    var position = ReaderPosition()
    var loadStatus: ReaderLoadStatus = .loading
    var selection: ReaderSelection?
    var activeFootnote: ReaderFootnote?
    var activeImage: ReaderImagePreview?
    var currentLocation: String?
    var searchMatchSummary: String?
    var showingFinishedRitual = false
    @ObservationIgnored var reportedProgress: Double?

    var fontSize: Double
    var lineHeight: Double
    var columnWidth: Double
    var typeface: ReaderTypeface
    var readingMode: ReadingMode
    var isZen: Bool
    var darkModePDF: Bool

    var error: String? { loadStatus.errorMessage }
    var totalPages: Int? {
        get { position.totalPages }
        set { position.totalPages = newValue }
    }
    var currentPage: Int? {
        get { position.currentPage }
        set {
            position.currentPage = newValue
            recordPageForPace(newValue)
        }
    }
    var chapterProgress: Double? {
        get { position.chapterProgress }
        set { position.chapterProgress = newValue }
    }
    var chapterPage: Int? {
        get { position.chapterPage }
        set { position.chapterPage = newValue }
    }
    var chapterPageCount: Int? {
        get { position.chapterPageCount }
        set { position.chapterPageCount = newValue }
    }

    init(book: Book, library: LibraryStore, defaultMode: ReadingMode, initialJump: JumpTarget? = nil) {
        self.book = book
        self.library = library
        self.initialJumpTarget = initialJump
        self.wasAlreadyFinishedOnOpen = book.isFinished
        let preferences = book.preferences
        fontSize = preferences?.fontSize ?? ReaderPreferences.default.fontSize
        lineHeight = preferences?.lineHeight ?? ReaderPreferences.default.lineHeight
        columnWidth = preferences?.columnWidth ?? ReaderPreferences.default.columnWidth
        typeface = preferences?.typeface.flatMap(ReaderTypeface.init(rawValue:)) ?? .default
        readingMode = preferences.flatMap { ReadingMode(rawValue: $0.readingMode) } ?? defaultMode
        isZen = (preferences?.zenMode ?? false) || ReadingFocus.hidesControls
        darkModePDF = preferences?.darkModePDF ?? true
        if let initialJump {
            chapterIndex = initialJump.chapterIndex
        } else {
            chapterIndex = EPUBLocation.decode(book.lastLocation)?.spineIndex
                ?? PDFLocation.decode(book.lastLocation)?.chapterIndex
                ?? 0
        }
    }

    var preferredStartLocation: String? {
        initialJumpTarget?.location ?? book.lastLocation
    }

    func selectChapter(_ index: Int) {
        guard chapters.indices.contains(index) else { return }
        selection = nil
        activeFootnote = nil
        chapterIndex = index
        engine?.goToChapter(index)
    }

    func seek(to progress: Double) {
        engine?.seek(to: min(max(progress, 0), 1))
    }

    func jump(toHighlight highlight: Highlight) {
        selection = nil
        activeFootnote = nil
        engine?.jump(to: highlight.location, chapterIndex: highlight.chapterIndex)
    }

    func jump(to position: ReadingPosition) {
        selection = nil
        activeFootnote = nil
        engine?.jump(to: position.location, chapterIndex: position.chapterIndex)
    }

    func jump(toBookmark bookmark: Bookmark) {
        selection = nil
        activeFootnote = nil
        engine?.jump(to: bookmark.location, chapterIndex: bookmark.chapterIndex)
    }

    func jumpToFootnote(_ footnote: ReaderFootnote) {
        activeFootnote = nil
        if let chapter = footnote.chapterIndex {
            selectChapter(chapter)
        }
    }

    func applyExternalJump(_ target: JumpTarget) {
        selection = nil
        activeFootnote = nil
        if let engine {
            engine.jump(to: target.location, chapterIndex: target.chapterIndex)
        } else {
            initialJumpTarget = target
            chapterIndex = target.chapterIndex
        }
    }

    func addHighlight(color: HighlightColor) {
        guard let selection else { return }
        library.addHighlight(to: book, chapterIndex: selection.chapterIndex, text: selection.text, color: color, location: selection.location ?? currentLocation)
        self.selection = nil
        Haptics.impact(.light)
        engine?.clearSelection()
        engine?.refreshHighlights()
    }

    func removeHighlight(_ highlight: Highlight) {
        library.removeHighlight(highlight)
        engine?.refreshHighlights()
    }

    func toggleBookmark() {
        library.toggleBookmark(in: book, chapterIndex: chapterIndex, title: chapterTitle, location: currentLocation ?? book.lastLocation)
        Haptics.impact(.medium)
    }

    func completeBookAndCelebrate() {
        if !book.isFinished {
            library.setFinished(true, for: book)
        }
        wasAlreadyFinishedOnOpen = true
        Haptics.success()
        showingFinishedRitual = true
    }

    var isBookmarked: Bool { library.bookmark(in: book, chapterIndex: chapterIndex) != nil }

    func resetTypography() {
        fontSize = ReaderPreferences.default.fontSize
        lineHeight = ReaderPreferences.default.lineHeight
        columnWidth = ReaderPreferences.default.columnWidth
        typeface = .default
    }

    func savePreferences() {
        savePreferencesTask?.cancel()
        savePreferencesTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            self?.flushPreferences()
        }
    }

    func flushPreferences() {
        savePreferencesTask?.cancel()
        savePreferencesTask = nil
        library.setPreferences(
            ReaderPreferences(
                theme: library.preferences.theme.rawValue,
                fontSize: fontSize,
                lineHeight: lineHeight,
                columnWidth: columnWidth,
                readingMode: readingMode.rawValue,
                zenMode: isZen,
                typeface: typeface == .default ? nil : typeface.rawValue,
                darkModePDF: darkModePDF
            ),
            for: book
        )
    }

    func engineDidFail(fileURL: URL, detail: String) {
        chapters = []
        resetPosition()
        let message = FileManager.default.fileExists(atPath: fileURL.path)
            ? detail
            : "This book's file is missing from Chicken's library folder."
        loadStatus = .failed(message)
    }

    func engineDidBecomeReady() {
        loadStatus = .ready
    }

    func engineDidChangeChapter(_ index: Int) {
        guard index != chapterIndex else { return }
        if loadStatus == .ready { Haptics.selection() }
        chapterIndex = index
    }

    func reportProgress(_ progress: Double, location: String?) {
        reportedProgress = progress
        if let location { currentLocation = location }
        if loadStatus == .loading { loadStatus = .ready }
        if initialJumpTarget != nil {
            initialJumpTarget = nil
            return
        }
        let wasFinished = book.isFinished
        library.updateProgress(for: book, progress: progress, location: location)
        if !wasAlreadyFinishedOnOpen && !wasFinished && book.isFinished {
            wasAlreadyFinishedOnOpen = true
            Haptics.success()
            showingFinishedRitual = true
        }
    }

    private func recordPageForPace(_ page: Int?) {
        guard let page, loadStatus == .ready else { return }
        let now = Date()
        guard let anchorPage = paceAnchorPage, let anchorDate = paceAnchorDate else {
            paceAnchorPage = page
            paceAnchorDate = now
            return
        }
        let deltaPages = page - anchorPage
        let elapsed = now.timeIntervalSince(anchorDate)
        if deltaPages < 0 || deltaPages > 12 || elapsed > 1200 {
            paceAnchorPage = page
            paceAnchorDate = now
            return
        }
        if deltaPages >= 2 && elapsed >= 30 {
            library.recordReadingPace(pagesRead: Double(deltaPages), elapsedSeconds: elapsed)
            paceAnchorPage = page
            paceAnchorDate = now
        }
    }

    private func recordChapterTitle() {
        guard chapters.indices.contains(chapterIndex) else { return }
        let title = chapters[chapterIndex].title
        guard book.lastChapterTitle != title else { return }
        book.lastChapterTitle = title
        #if os(iOS)
        ReadingActivityController.shared.refresh()
        #endif
    }

    func resetPosition() {
        position = ReaderPosition()
    }

    var chapterTitle: String {
        chapters.indices.contains(chapterIndex) ? chapters[chapterIndex].title : book.displayTitle
    }

    var overallProgress: Double {
        if let totalPages = position.totalPages, totalPages > 0, let currentPage = position.currentPage {
            return min(1, max(0, Double(currentPage) / Double(totalPages)))
        }
        if chapters.isEmpty { return book.progress }
        if chapters.count == 1 {
            return min(1, max(0, position.chapterProgress ?? book.progress))
        }
        let withinChapter = min(1, max(0, position.chapterProgress ?? 0))
        return min(1, max(0, (Double(chapterIndex) + withinChapter) / Double(chapters.count)))
    }

    var isOnLastPage: Bool {
        if let totalPages = position.totalPages, totalPages > 0, let currentPage = position.currentPage {
            return currentPage >= totalPages
        }
        return overallProgress >= 0.98
    }

    var pageReadout: String {
        if let totalPages = position.totalPages, totalPages > 0, let currentPage = position.currentPage {
            return currentPage >= totalPages ? "Last page" : "\(currentPage) of \(totalPages)"
        }
        guard chapters.count > 1 else { return "" }
        return "Ch. \(chapterIndex + 1) of \(chapters.count)"
    }

    var timeReadout: String {
        let pace = library.preferences.minutesPerPage
        if let totalPages = position.totalPages, totalPages > 0, let currentPage = position.currentPage {
            return "\(ReadingEstimate.duration(forPages: max(0, totalPages - currentPage), minutesPerPage: pace)) left"
        }
        if let pages = chapterPagesRemaining {
            return "\(ReadingEstimate.duration(forPages: pages, minutesPerPage: pace)) left in chapter"
        }
        return ""
    }

    private var chapterPagesRemaining: Int? {
        if let chapterPage = position.chapterPage, let chapterPageCount = position.chapterPageCount, chapterPageCount > 0 {
            return max(0, chapterPageCount - chapterPage)
        }
        if let chapterPageCount = position.chapterPageCount, chapterPageCount > 0, let chapterProgress = position.chapterProgress {
            return max(0, Int((Double(chapterPageCount) * (1 - min(1, max(0, chapterProgress)))).rounded(.up)))
        }
        return nil
    }
}
