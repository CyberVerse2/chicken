import ChickenKit
import Foundation
import WidgetKit

extension LibraryStore {
    /// Writes the widget snapshot and asks WidgetKit to reload. Debounced,
    /// because reading progress changes continuously while a book is open.
    func publishWidgetSnapshot() {
        widgetTask?.cancel()
        widgetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            let book = self.continueReadingBook()
            let coverURL = book.flatMap { self.coverURL(for: $0) }
            let snapshot = WidgetSnapshot(
                currentBook: book.map {
                    WidgetSnapshot.CurrentBook(
                        id: $0.id,
                        title: $0.displayTitle,
                        author: $0.displayAuthor,
                        progress: $0.progress,
                        coverTintIndex: $0.coverTintIndex,
                        hasCover: coverURL != nil
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
            guard snapshot != self.lastPublishedSnapshot else { return }
            self.lastPublishedSnapshot = snapshot

            await Task.detached(priority: .utility) {
                snapshot.save(coverJPEG: coverURL.flatMap { CoverRenderer.thumbnailJPEG(from: $0) })
            }.value
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
