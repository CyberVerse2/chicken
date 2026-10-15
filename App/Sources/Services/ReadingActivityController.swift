#if os(iOS)
import ActivityKit
import ChickenKit
import ImageIO
import SwiftUI

/// Runs the reading session in the Dynamic Island and on the Lock Screen.
/// It starts when a book opens, follows your chapter, progress, and today's
/// minutes, and ends when the book closes. The island is only visible while
/// Chicken itself isn't on screen, so it's how the book you're in stays a
/// tap away when you step out to another app.
@MainActor
final class ReadingActivityController {
    static let shared = ReadingActivityController()

    private var activity: Activity<ReadingActivityAttributes>?
    private weak var book: Book?
    private weak var library: LibraryStore?
    private var isReadingAloud = false
    private var pendingUpdate: Task<Void, Never>?
    private var lastState: ReadingActivityAttributes.ContentState?

    private init() {}

    /// A book opened in the reader.
    func begin(book: Book, library: LibraryStore) {
        self.book = book
        self.library = library
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // One session at a time; leftovers from a previous launch go too.
        for existing in Activity<ReadingActivityAttributes>.activities where existing.attributes.bookID != book.id {
            // `Activity` isn't Sendable; ActivityKit allows calling it from any task.
            nonisolated(unsafe) let stale = existing
            Task { await stale.end(nil, dismissalPolicy: .immediate) }
        }
        if let existing = Activity<ReadingActivityAttributes>.activities.first(where: { $0.attributes.bookID == book.id }) {
            activity = existing
            refresh()
            return
        }

        writeCover(for: book, library: library)
        let attributes = ReadingActivityAttributes(
            bookID: book.id,
            title: book.displayTitle,
            author: book.displayAuthor,
            coverTintIndex: book.coverTintIndex,
            theme: library.preferences.theme.rawValue
        )
        let state = currentState()
        lastState = state
        activity = try? Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: nil))
    }

    /// Reading state changed: chapter, progress, or today's minutes.
    /// Updates are coalesced so a flurry of page turns sends one.
    func refresh() {
        guard activity != nil else { return }
        pendingUpdate?.cancel()
        pendingUpdate = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self, let current = self.activity else { return }
            nonisolated(unsafe) let activity = current
            let state = self.currentState()
            guard state != self.lastState else { return }
            let goalJustMet = (self.lastState?.goalFraction ?? 0) < 1 && state.goalFraction >= 1
            self.lastState = state
            let alert = goalJustMet
                ? AlertConfiguration(title: "Today's reading is done", body: "\(state.goalMinutes) minutes read.", sound: .default)
                : nil
            await activity.update(ActivityContent(state: state, staleDate: nil), alertConfiguration: alert)
        }
    }

    func setReadingAloud(_ reading: Bool) {
        guard isReadingAloud != reading else { return }
        isReadingAloud = reading
        refresh()
    }

    /// The book closed.
    func end() {
        pendingUpdate?.cancel()
        isReadingAloud = false
        guard let current = activity else { return }
        self.activity = nil
        let state = currentState()
        let bookID = current.attributes.bookID
        nonisolated(unsafe) let finished = current
        Task { await finished.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate) }
        if let url = ReadingActivityAttributes.coverURL(for: bookID) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func currentState() -> ReadingActivityAttributes.ContentState {
        ReadingActivityAttributes.ContentState(
            chapter: book?.lastChapterTitle,
            progress: book?.progress ?? 0,
            minutesToday: (library?.readingSecondsToday ?? 0) / 60,
            goalMinutes: library?.preferences.dailyGoalMinutes ?? 0,
            isReadingAloud: isReadingAloud
        )
    }

    /// Puts a small copy of the cover where the extension can read it. A PDF
    /// that opens on a page of text gets none, and the island shows its
    /// cloth colour instead.
    private func writeCover(for book: Book, library: LibraryStore) {
        guard let destination = ReadingActivityAttributes.coverURL(for: book.id) else { return }
        guard let source = library.coverURL(for: book) else {
            try? FileManager.default.removeItem(at: destination)
            return
        }
        let isPDF = book.format == .pdf
        Task.detached(priority: .utility) {
            if isPDF,
               let image = CGImageSourceCreateWithURL(source as CFURL, nil).flatMap({ CGImageSourceCreateImageAtIndex($0, 0, nil) }),
               CoverRenderer.looksLikeTextPage(image) {
                try? FileManager.default.removeItem(at: destination)
                return
            }
            if let data = CoverRenderer.thumbnailJPEG(from: source, maxPixelSize: 180) {
                try? data.write(to: destination, options: .atomic)
            }
        }
    }
}

extension View {
    /// Keeps the Dynamic Island's reading session open while this book is.
    func readingActivity(for book: Book, library: LibraryStore) -> some View {
        onAppear { ReadingActivityController.shared.begin(book: book, library: library) }
            .onDisappear { ReadingActivityController.shared.end() }
    }
}
#else
import SwiftUI

extension View {
    func readingActivity(for book: Book, library: LibraryStore) -> some View { self }
}
#endif
