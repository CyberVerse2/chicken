import ChickenKit
import Foundation
import Observation

/// Flow of the reading surface. Stored by raw value in `ReaderPreferences`.
enum ReadingMode: String, CaseIterable, Identifiable {
    case scroll
    case paged
    case spread

    var id: String { rawValue }

    var label: String {
        switch self {
        case .scroll: return "Scroll"
        case .paged: return "Pages"
        case .spread: return "Spread"
        }
    }

    var systemImage: String {
        switch self {
        case .scroll: return "scroll"
        case .paged: return "book.pages"
        case .spread: return "book"
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

/// Text the reader has selected, waiting for a highlight color.
struct ReaderSelection: Equatable {
    let text: String
    let chapterIndex: Int
    let location: String?
}

/// What a format-specific reader (PDF, EPUB, text) must do on request. The
/// model holds the engine weakly; engines register themselves when created.
@MainActor
protocol ReaderEngine: AnyObject {
    func goToChapter(_ index: Int)
    func seek(to progress: Double)
    func jump(to location: String?, chapterIndex: Int)
    func turnPage(_ direction: Int)
    func search(_ query: String, backwards: Bool)
    func clearSelection()
    func refreshHighlights()
    /// Flush the precise current position before the reader closes.
    func captureLocation()

    /// Text to read aloud: a batch of passages starting at what's on
    /// screen, or just after the passage `after`. Empty at the end.
    func readAloudPassages(after: String?) async -> [SpokenPassage]
    /// Brings a passage into view as it starts being read.
    func revealPassage(_ id: String)
    func endReadingAloud()
}

/// A stretch of the book read aloud as one utterance, usually a paragraph.
struct SpokenPassage: Equatable {
    let id: String
    let text: String
}

/// State for one open book: navigation, typography, and what the engine
/// reports back. Views observe it; engines update it.
@Observable
final class ReaderModel {
    let book: Book
    @ObservationIgnored let library: LibraryStore
    @ObservationIgnored weak var engine: ReaderEngine?
    /// Reads the book aloud from the paragraph on screen.
    @ObservationIgnored private(set) lazy var readAloud = ReadAloudController(model: self)

    // Structure and position, reported by the engine.
    var chapters: [ReaderChapter] = [] {
        didSet { recordChapterTitle() }
    }
    var chapterIndex: Int {
        didSet { recordChapterTitle() }
    }
    var totalPages: Int?
    var currentPage: Int?
    var chapterProgress: Double?
    var chapterPage: Int?
    var chapterPageCount: Int?
    var error: String?
    var selection: ReaderSelection?
    var currentLocation: String?
    /// The last progress the engine reported in this session.
    @ObservationIgnored var reportedProgress: Double?

    // Typography and flow.
    var fontSize: Double
    var lineHeight: Double
    var columnWidth: Double
    var typeface: ReaderTypeface
    var readingMode: ReadingMode
    var isZen: Bool

    /// Chapter changes the engine reported itself; avoids echoing a
    /// navigation request back to the engine that caused it.
    @ObservationIgnored private var engineReportedChapter: Int?

    init(book: Book, library: LibraryStore, defaultMode: ReadingMode) {
        self.book = book
        self.library = library
        let preferences = book.preferences
        fontSize = preferences?.fontSize ?? ReaderPreferences.default.fontSize
        lineHeight = preferences?.lineHeight ?? ReaderPreferences.default.lineHeight
        columnWidth = preferences?.columnWidth ?? ReaderPreferences.default.columnWidth
        typeface = preferences?.typeface.flatMap(ReaderTypeface.init(rawValue:)) ?? .default
        readingMode = preferences.flatMap { ReadingMode(rawValue: $0.readingMode) } ?? defaultMode
        // A Focus set to hide the controls opens every book that way.
        isZen = (preferences?.zenMode ?? false) || ReadingFocus.hidesControls
        chapterIndex = EPUBLocation.decode(book.lastLocation)?.spineIndex
            ?? PDFLocation.decode(book.lastLocation)?.chapterIndex
            ?? 0
    }

    // MARK: Requests from the UI

    func selectChapter(_ index: Int) {
        guard chapters.indices.contains(index) else { return }
        selection = nil
        chapterIndex = index
        engine?.goToChapter(index)
    }

    func seek(to progress: Double) {
        engine?.seek(to: min(max(progress, 0), 1))
    }

    func jump(toHighlight highlight: Highlight) {
        selection = nil
        engine?.jump(to: highlight.location, chapterIndex: highlight.chapterIndex)
    }

    /// Where another device got to.
    func jump(to position: ReadingPosition) {
        selection = nil
        engine?.jump(to: position.location, chapterIndex: position.chapterIndex)
    }

    func jump(toBookmark bookmark: Bookmark) {
        selection = nil
        engine?.jump(to: bookmark.location, chapterIndex: bookmark.chapterIndex)
    }

    func addHighlight(color: HighlightColor) {
        guard let selection else { return }
        library.addHighlight(to: book, chapterIndex: selection.chapterIndex, text: selection.text, color: color, location: selection.location ?? currentLocation)
        self.selection = nil
        engine?.clearSelection()
        engine?.refreshHighlights()
    }

    func removeHighlight(_ highlight: Highlight) {
        library.removeHighlight(highlight)
        engine?.refreshHighlights()
    }

    func toggleBookmark() {
        library.toggleBookmark(in: book, chapterIndex: chapterIndex, title: chapterTitle, location: currentLocation ?? book.lastLocation)
    }

    var isBookmarked: Bool { library.bookmark(in: book, chapterIndex: chapterIndex) != nil }

    func resetTypography() {
        fontSize = ReaderPreferences.default.fontSize
        lineHeight = ReaderPreferences.default.lineHeight
        columnWidth = ReaderPreferences.default.columnWidth
        typeface = .default
    }

    func savePreferences() {
        library.setPreferences(
            ReaderPreferences(
                theme: library.preferences.theme.rawValue,
                fontSize: fontSize,
                lineHeight: lineHeight,
                columnWidth: columnWidth,
                readingMode: readingMode.rawValue,
                zenMode: isZen,
                typeface: typeface == .default ? nil : typeface.rawValue
            ),
            for: book
        )
    }

    // MARK: Reports from the engine

    func engineDidChangeChapter(_ index: Int) {
        guard index != chapterIndex else { return }
        engineReportedChapter = index
        chapterIndex = index
    }

    /// True when `chapterIndex` changed because the engine said so.
    func consumeEngineChapterChange(_ index: Int) -> Bool {
        guard engineReportedChapter == index else { return false }
        engineReportedChapter = nil
        return true
    }

    func reportProgress(_ progress: Double, location: String?) {
        reportedProgress = progress
        if let location { currentLocation = location }
        // Updates the Live Activity too, once the progress is written.
        library.updateProgress(for: book, progress: progress, location: location)
    }

    /// Remembers the chapter you're in, so Home can name it.
    private func recordChapterTitle() {
        guard chapters.indices.contains(chapterIndex) else { return }
        let title = chapters[chapterIndex].title
        guard book.lastChapterTitle != title else { return }
        book.lastChapterTitle = title
        library.save()
        #if os(iOS)
        ReadingActivityController.shared.refresh()
        #endif
    }

    func resetPosition() {
        totalPages = nil
        currentPage = nil
        chapterProgress = nil
        chapterPage = nil
        chapterPageCount = nil
    }

    // MARK: Readouts

    var chapterTitle: String {
        chapters.indices.contains(chapterIndex) ? chapters[chapterIndex].title : book.displayTitle
    }

    var overallProgress: Double {
        if let totalPages, totalPages > 0, let currentPage {
            return min(1, max(0, Double(currentPage) / Double(totalPages)))
        }
        if chapters.isEmpty { return book.progress }
        return Double(chapterIndex + 1) / Double(chapters.count)
    }

    var isOnLastPage: Bool {
        guard let totalPages, totalPages > 0, let currentPage else { return false }
        return currentPage >= totalPages
    }

    var pageReadout: String {
        if let totalPages, totalPages > 0, let currentPage {
            return currentPage >= totalPages ? "the last page" : "page \(currentPage) of \(totalPages)"
        }
        guard !chapters.isEmpty else { return "" }
        return "section \(chapterIndex + 1) of \(chapters.count)"
    }

    /// Time left in the book, or in the chapter when the book's length isn't known.
    var timeReadout: String {
        if let totalPages, totalPages > 0, let currentPage {
            return "\(ReadingEstimate.duration(forPages: max(0, totalPages - currentPage))) left"
        }
        if let pages = chapterPagesRemaining {
            return "\(ReadingEstimate.duration(forPages: pages)) left in chapter"
        }
        return ""
    }

    private var chapterPagesRemaining: Int? {
        if let chapterPage, let chapterPageCount, chapterPageCount > 0 {
            return max(0, chapterPageCount - chapterPage)
        }
        if let chapterPageCount, chapterPageCount > 0, let chapterProgress {
            return max(0, Int((Double(chapterPageCount) * (1 - min(1, max(0, chapterProgress)))).rounded(.up)))
        }
        return nil
    }
}
