#if DEBUG
import ChickenKit
import Foundation
import SwiftData

extension LibraryStore {
    /// `CHICKEN_DEBUG_SEED=<folder>` fills an empty debug library with the
    /// books in that folder, then gives them believable reading state
    /// (progress, finished dates, highlights, a week of reading time) so
    /// every screen can be checked with real content.
    func seedDebugLibraryIfRequested() {
        guard let folder = ProcessInfo.processInfo.environment["CHICKEN_DEBUG_SEED"], !folder.isEmpty else { return }
        if !allBooks().isEmpty {
            applyDebugReadingState()
            return
        }
        let root = URL(fileURLWithPath: folder)
        let files = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        importFiles(files.filter { !$0.lastPathComponent.hasPrefix(".") })
        Task { @MainActor [weak self] in
            while let self, self.importState.isImporting {
                try? await Task.sleep(for: .milliseconds(200))
            }
            self?.applyDebugReadingState()
        }
    }

    private func applyDebugReadingState() {
        let books = allBooks()
        guard !books.contains(where: { $0.lastOpenedAt != nil }) else { return }
        let now = Date()
        func ago(days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }
        func book(_ file: String) -> Book? { books.first { $0.originalFileName == file } }

        let reading: [(String, Double, Double)] = [
            ("pride-and-prejudice.epub", 0.42, 0.04),
            ("moby-dick.epub", 0.18, 2),
            ("middlemarch.epub", 0.63, 5),
            ("attention-in-long-form-reading.pdf", 0.27, 9),
        ]
        for (file, progress, days) in reading {
            guard let book = book(file) else { continue }
            book.progress = progress
            book.lastOpenedAt = ago(days: days)
            book.lastActivityAt = ago(days: days)
        }

        let finished: [(String, Double)] = [
            ("walden.epub", 30), ("frankenstein.epub", 80), ("meditations.epub", 150), ("the-wind-in-the-willows.epub", 210),
        ]
        for (file, days) in finished {
            guard let book = book(file) else { continue }
            book.progress = 1
            book.finishedAt = ago(days: days)
            book.lastOpenedAt = ago(days: days)
            book.lastActivityAt = ago(days: days)
        }

        let marks: [(String, Int, HighlightColor, String, String)] = [
            ("pride-and-prejudice.epub", 0, .amber, "It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.", "The whole novel in one ironic sentence."),
            ("pride-and-prejudice.epub", 0, .purple, "However little known the feelings or views of such a man may be on his first entering a neighbourhood, this truth is so well fixed in the minds of the surrounding families.", ""),
            ("walden.epub", 1, .green, "I went to the woods because I wished to live deliberately, to front only the essential facts of life, and see if I could not learn what it had to teach.", "Read this again in spring."),
            ("walden.epub", 0, .amber, "I lived alone, in the woods, a mile from any neighbor, in a house which I had built myself.", ""),
            ("moby-dick.epub", 0, .coral, "Whenever I find myself growing grim about the mouth; whenever it is a damp, drizzly November in my soul; then, I account it high time to get to sea as soon as I can.", ""),
            ("middlemarch.epub", 0, .amber, "Miss Brooke had that kind of beauty which seems to be thrown into relief by poor dress.", ""),
            ("meditations.epub", 1, .green, "Begin the morning by saying to thyself, I shall meet with the busy-body, the ungrateful, arrogant, deceitful, envious, unsocial.", "Every morning."),
        ]
        for (index, mark) in marks.enumerated() {
            guard let book = book(mark.0),
                  let highlight = addHighlight(to: book, chapterIndex: mark.1, text: mark.3, color: mark.2, location: nil)
            else { continue }
            highlight.note = mark.4
            highlight.createdAt = ago(days: Double(index) * 3 + 1)
        }

        let minutes = [34, 12, 0, 41, 26, 18, 22]
        for (offset, value) in minutes.enumerated() where value > 0 {
            addReadingSeconds(value * 60, toDay: ReadingLog.dayKey(for: ago(days: Double(6 - offset))))
        }
        save()
        recomputeReadingStats()
        publishWidgetSnapshot()
    }
}
#endif

#if DEBUG
extension LibraryStore {
    /// `CHICKEN_DEBUG_FURTHER=continue` pretends an iPad read the book you're
    /// reading a chapter and 15% further a minute ago, to check the reader's
    /// offer to jump there.
    func addDebugFurtherPositionIfRequested() {
        guard ProcessInfo.processInfo.environment["CHICKEN_DEBUG_FURTHER"] == "continue",
              let book = continueReadingBook() else { return }
        for position in book.positions ?? [] where position.device == "debug-ipad" {
            context.delete(position)
        }
        let position = ReadingPosition(device: "debug-ipad", deviceKind: "iPad")
        position.book = book
        position.progress = min(1, book.progress + 0.15)
        // The start of the next chapter, as a real EPUB position when there is one.
        let current = EPUBLocation.decode(book.lastLocation)
        let next = (current?.spineIndex ?? 0) + 1
        position.location = EPUBLocation(href: current?.href ?? "", spineIndex: next, progression: 0, globalProgression: position.progress).encoded
        position.chapterIndex = next
        position.updatedAt = Date().addingTimeInterval(-60)
        context.insert(position)
        save()
    }
}
#endif
