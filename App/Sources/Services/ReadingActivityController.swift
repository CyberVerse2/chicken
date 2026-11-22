#if os(iOS)
import ActivityKit
import ChickenKit
import os
import ImageIO
import SwiftUI

final class ReadingActivityController {
    static let shared = ReadingActivityController()

    private struct Session {
        let activity: Activity<ReadingActivityAttributes>
        weak var book: Book?
        weak var library: LibraryStore?
        var isReadingAloud = false
        var lastState: ReadingActivityAttributes.ContentState
        var pendingUpdate: Task<Void, Never>?
        var coverTask: Task<Void, Never>?
    }

    private var session: Session?

    private init() {}

    func begin(book: Book, library: LibraryStore) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        for existing in Activity<ReadingActivityAttributes>.activities where existing.attributes.bookID != book.id {
            nonisolated(unsafe) let stale = existing
            Task { await stale.end(nil, dismissalPolicy: .immediate) }
        }

        let initialState = Self.state(book: book, library: library, isReadingAloud: false)
        if let existing = Activity<ReadingActivityAttributes>.activities.first(where: { $0.attributes.bookID == book.id }) {
            session = Session(activity: existing, book: book, library: library, lastState: initialState)
            refresh()
            return
        }

        let coverTask = startWritingCover(for: book, library: library)
        let attributes = ReadingActivityAttributes(
            bookID: book.id,
            title: book.displayTitle,
            author: book.displayAuthor,
            coverTintIndex: book.coverTintIndex,
            theme: library.preferences.theme.rawValue
        )
        do {
            let activity = try Activity.request(attributes: attributes, content: ActivityContent(state: initialState, staleDate: nil))
            session = Session(
                activity: activity,
                book: book,
                library: library,
                lastState: initialState,
                coverTask: coverTask
            )
        } catch {
            coverTask?.cancel()
            ChickenLog.widgets.error("Failed to start Live Activity: \(error.localizedDescription, privacy: .public)")
        }
    }

    func refresh() {
        guard session != nil else { return }
        session?.pendingUpdate?.cancel()
        session?.pendingUpdate = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self, let current = self.session else { return }
            nonisolated(unsafe) let activity = current.activity
            let nextState = Self.state(book: current.book, library: current.library, isReadingAloud: current.isReadingAloud)
            guard nextState != current.lastState else { return }
            let goalJustMet = current.lastState.goalFraction < 1 && nextState.goalFraction >= 1
            self.session?.lastState = nextState
            let alert = goalJustMet
                ? AlertConfiguration(title: "Today's reading is done", body: "\(nextState.goalMinutes) minutes read.", sound: .default)
                : nil
            await activity.update(ActivityContent(state: nextState, staleDate: nil), alertConfiguration: alert)
        }
    }

    func setReadingAloud(_ reading: Bool) {
        guard let current = session, current.isReadingAloud != reading else { return }
        session?.isReadingAloud = reading
        refresh()
    }

    func end() {
        guard let current = session else { return }
        session = nil
        current.pendingUpdate?.cancel()
        current.coverTask?.cancel()
        let finalState = Self.state(book: current.book, library: current.library, isReadingAloud: false)
        let bookID = current.activity.attributes.bookID
        nonisolated(unsafe) let finished = current.activity
        Task {
            await current.coverTask?.value
            await finished.end(ActivityContent(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
            if let url = ReadingActivityAttributes.coverURL(for: bookID) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private static func state(book: Book?, library: LibraryStore?, isReadingAloud: Bool) -> ReadingActivityAttributes.ContentState {
        ReadingActivityAttributes.ContentState(
            chapter: book?.lastChapterTitle,
            progress: book?.progress ?? 0,
            minutesToday: (library?.readingSecondsToday ?? 0) / 60,
            goalMinutes: library?.preferences.dailyGoalMinutes ?? 0,
            isReadingAloud: isReadingAloud
        )
    }

    private func startWritingCover(for book: Book, library: LibraryStore) -> Task<Void, Never>? {
        guard let destination = ReadingActivityAttributes.coverURL(for: book.id) else { return nil }
        guard let source = library.coverURL(for: book) else {
            try? FileManager.default.removeItem(at: destination)
            return nil
        }
        let isPDF = book.format == .pdf
        return Task {
            await Self.writeCoverFile(source: source, destination: destination, isPDF: isPDF)
        }
    }

    @concurrent
    private static func writeCoverFile(source: URL, destination: URL, isPDF: Bool) async {
        guard !Task.isCancelled else { return }
        if isPDF,
           let image = CGImageSourceCreateWithURL(source as CFURL, nil).flatMap({ CGImageSourceCreateImageAtIndex($0, 0, nil) }),
           CoverRenderer.looksLikeTextPage(image) {
            try? FileManager.default.removeItem(at: destination)
            return
        }
        guard !Task.isCancelled else { return }
        if let data = CoverRenderer.thumbnailJPEG(from: source, maxPixelSize: 180) {
            guard !Task.isCancelled else { return }
            try? data.write(to: destination, options: .atomic)
        }
    }
}

extension View {
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
