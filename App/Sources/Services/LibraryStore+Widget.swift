import ChickenKit
import Foundation
import WidgetKit

extension LibraryStore {
    /// Writes the widget snapshot and asks WidgetKit to reload. Debounced,
    /// because reading progress changes continuously while a book is open.
    func publishWidgetSnapshot() {
        widgetTask?.cancel()
        widgetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self else { return }
            let book = self.continueReadingBook()
            let coverURL = book.flatMap { self.coverURL(for: $0) }
            let previewFallbackData = coverURL == nil ? book?.coverPreviewData : nil
            let hasWidgetCover = coverURL != nil || previewFallbackData != nil
            let snapshot = WidgetSnapshot(
                currentBook: book.map {
                    WidgetSnapshot.CurrentBook(
                        id: $0.id,
                        title: $0.displayTitle,
                        author: $0.displayAuthor,
                        progress: ($0.progress * 100).rounded() / 100,
                        coverTintIndex: $0.coverTintIndex,
                        hasCover: hasWidgetCover,
                        coverAspectRatio: $0.coverAspectRatio
                    )
                },
                secondsToday: self.readingSecondsToday,
                dailyGoalMinutes: self.preferences.dailyGoalMinutes,
                theme: self.preferences.theme.rawValue,
                lastSevenDays: self.lastSevenDays.map(\.seconds),
                finishedThisYear: self.booksFinished().count,
                annualGoal: self.preferences.annualBookGoal,
                chapter: book?.lastChapterTitle,
                day: Calendar.current.startOfDay(for: .now)
            )
            let coverChanged = coverURL != self.lastPublishedWidgetCoverURL || (coverURL == nil && previewFallbackData != nil)
            guard snapshot != self.lastPublishedSnapshot || coverChanged else { return }
            await Self.writeWidgetSnapshot(
                snapshot,
                coverURL: coverChanged ? coverURL : nil,
                previewData: previewFallbackData,
                keepExistingCover: !coverChanged && hasWidgetCover
            )
            guard !Task.isCancelled else { return }
            self.lastPublishedSnapshot = snapshot
            self.lastPublishedWidgetCoverURL = coverURL
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    @concurrent
    private static func writeWidgetSnapshot(
        _ snapshot: WidgetSnapshot,
        coverURL: URL?,
        previewData: Data?,
        keepExistingCover: Bool
    ) async {
        let jpeg = coverURL.flatMap { CoverRenderer.thumbnailJPEG(from: $0) } ?? previewData
        snapshot.save(coverJPEG: jpeg, keepExistingCover: keepExistingCover)
    }
}
