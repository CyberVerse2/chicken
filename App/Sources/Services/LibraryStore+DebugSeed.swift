#if DEBUG
import ChickenKit
import Foundation
import SwiftData

extension LibraryStore {
    func seedDebugLibraryIfRequested() {
        guard let mode = ProcessInfo.processInfo.environment["CHICKEN_DEBUG_SEED"], !mode.isEmpty else { return }
        if mode == "worstcase" {
            seedWorstCaseLibrary()
            return
        }
        if mode == "sample" {
            seedSampleLibrary()
            return
        }
        if !allBooks().isEmpty {
            applyDebugReadingState()
            return
        }
        let root = URL(fileURLWithPath: mode)
        let files = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        importFiles(files.filter { !$0.lastPathComponent.hasPrefix(".") })
        Task { @MainActor [weak self] in
            while let self, self.importState.isImporting {
                try? await Task.sleep(for: .milliseconds(200))
            }
            self?.applyDebugReadingState()
        }
    }

    private func seedSampleLibrary() {
        guard allBooks().isEmpty else { return }
        let now = Date()
        func ago(days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

        let fixtures: [(title: String, author: String?, format: BookFormat, progress: Double, daysAgo: Double?, finished: Bool, pages: Int, chapter: String?, summary: String?)] = [
            ("Pride and Prejudice", "Jane Austen", .epub, 0.42, 0.04, false, 368, "Chapter XXIII — Rosings Park", "Since its immediate success in 1813, Pride and Prejudice has remained one of the most popular novels in the English language."),
            ("Moby-Dick", "Herman Melville", .epub, 0.18, 1.5, false, 624, "Chapter IX — The Sermon", "Call me Ishmael. The saga of Captain Ahab and his relentless pursuit of the great white whale."),
            ("Middlemarch", "George Eliot", .epub, 0.63, 4, false, 780, "Book V — The Dead Hand", nil),
            ("Attention in Long-Form Reading", nil, .pdf, 0.27, 6, false, 48, "Section 3 — Cognitive Endurance", nil),
            ("The Left Hand of Darkness", "Ursula K. Le Guin", .epub, 0.0, nil, false, 304, nil, "A lone human emissary is sent to Winter, an icy alien world where the inhabitants have no fixed gender."),
            ("Walden", "Henry David Thoreau", .epub, 1.0, 22, true, 352, nil, nil),
            ("Frankenstein", "Mary Shelley", .epub, 1.0, 64, true, 280, nil, nil),
            ("Meditations", "Marcus Aurelius", .epub, 1.0, 120, true, 254, nil, nil),
            ("The Wind in the Willows", "Kenneth Grahame", .epub, 1.0, 180, true, 240, nil, nil),
            ("Notes on Typography.md", "Robert Bringhurst", .text, 0.0, nil, false, 18, nil, nil),
        ]

        var inserted: [Book] = []
        for item in fixtures {
            let ext = item.format == .epub ? "epub" : (item.format == .pdf ? "pdf" : "md")
            let stored = "\(UUID().uuidString).\(ext)"
            let fileURL = paths.bookFile(named: stored)
            if item.format == .text {
                let sampleMarkdown = """
                # \(item.title)

                Typography exists to honor content. Good design is as little design as possible.

                > Letters are things, not pictures of things.

                - Measure line length carefully
                - Give prose room to breathe
                - Keep **chrome quiet** and *prose crisp*

                ```
                line-height: 1.72;
                ```
                """
                try? sampleMarkdown.write(to: fileURL, atomically: true, encoding: .utf8)
            }
            let book = Book(
                title: item.title,
                format: item.format,
                originalFileName: "\(item.title).\(ext)",
                storedFileName: stored
            )
            book.author = item.author
            book.fileSize = 420_000
            book.pageCount = item.pages
            book.progress = item.progress
            book.lastChapterTitle = item.chapter
            book.summary = item.summary
            book.derivedDataChecked = true
            if let daysAgo = item.daysAgo {
                book.lastOpenedAt = ago(days: daysAgo)
                book.lastActivityAt = ago(days: daysAgo)
                if item.finished { book.finishedAt = ago(days: daysAgo) }
            }
            context.insert(book)
            inserted.append(book)
        }

        if let pride = inserted.first {
            let h1 = addHighlight(
                to: pride,
                chapterIndex: 0,
                text: "It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.",
                color: .amber,
                location: nil
            )
            h1?.note = "The whole novel in one ironic sentence."
            _ = addHighlight(
                to: pride,
                chapterIndex: 2,
                text: "There is a stubbornness about me that never can bear to be frightened at the will of others.",
                color: .purple,
                location: nil
            )
        }
        if inserted.count > 5 {
            let walden = inserted[5]
            let h = addHighlight(
                to: walden,
                chapterIndex: 1,
                text: "I went to the woods because I wished to live deliberately, to front only the essential facts of life.",
                color: .green,
                location: nil
            )
            h?.note = "Read this again in spring."
        }

        let classics = createCollection(named: "Classics", with: Array(inserted.prefix(3)))
        _ = classics
        _ = createCollection(named: "Essays", with: Array(inserted.suffix(2)))

        let minutes = [34, 12, 0, 41, 26, 18, 22]
        for (offset, value) in minutes.enumerated() where value > 0 {
            addReadingSeconds(value * 60, toDay: ReadingLog.dayKey(for: ago(days: Double(6 - offset))))
        }
        save()
        recomputeReadingStats()
        publishWidgetSnapshot()
        if ProcessInfo.processInfo.environment["CHICKEN_DEBUG_OPEN"] == "markdown",
           let markdownBook = inserted.first(where: { $0.format == .text }) {
            AppRouter.shared.pendingDestination = .book(markdownBook.id)
        }
    }

    private func seedWorstCaseLibrary() {
        for book in allBooks() {
            context.delete(book)
        }
        let now = Date()
        func ago(days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

        let worstCases: [(title: String, author: String?, format: BookFormat, progress: Double, daysAgo: Double?, finished: Bool, pages: Int?, chapter: String?)] = [
            (
                "An Unusually Long Academic Monograph on Distributed Consensus Protocols, Byzantine Fault Tolerance, and Asynchronous State Machine Replication in Adversarial Networks (Fourth Revised Centennial Edition)",
                "Dr. Alexandrina Konstantinopolis-Vandenberghe-Smythe III, PhD, FRSA",
                .pdf,
                0.73,
                0.01,
                false,
                14820,
                "Appendix XIV-B: Proof of Liveness Under Unbounded Network Partitions and Adversarial Clock Drift",
            ),
            ("Q", nil, .epub, 0.08, 1, false, 12, "I"),
            ("源氏物語・完全版：紫式部による長編物語文学の金字塔", "紫式部", .epub, 0.51, 2, false, 1280, "第十二帖 須磨"),
            ("ألف ليلة وليلة — النسخة الكاملة المحققة", "مؤلف مجهول", .epub, 0.34, 3, false, 940, "الليلة السابعة والعشرون"),
            ("SupercalifragilisticexpialidociousUnbreakableIdentifierWithoutAnySpacesWhatsoever2026_FINAL_v9_revised.pdf", nil, .pdf, 0.99, 4, false, 999, nil),
            ("🧭 Field Manual for Polar Cartography & Cold-Weather Celestial Navigation ❄️", "S. Lindqvist", .text, 0.0, nil, false, 64, nil),
            ("Finished Classic", "Author Name", .epub, 1.0, 10, true, 410, nil),
        ]

        var inserted: [Book] = []
        for item in worstCases {
            let ext = item.format == .epub ? "epub" : (item.format == .pdf ? "pdf" : "txt")
            let stored = "\(UUID().uuidString).\(ext)"
            let book = Book(
                title: item.title,
                format: item.format,
                originalFileName: "\(item.title).\(ext)",
                storedFileName: stored
            )
            book.author = item.author
            book.fileSize = 98_400_000
            book.pageCount = item.pages
            book.progress = item.progress
            book.lastChapterTitle = item.chapter
            book.derivedDataChecked = true
            if let daysAgo = item.daysAgo {
                book.lastOpenedAt = ago(days: daysAgo)
                book.lastActivityAt = ago(days: daysAgo)
                if item.finished { book.finishedAt = ago(days: daysAgo) }
            }
            context.insert(book)
            inserted.append(book)
        }

        if let first = inserted.first {
            let h = addHighlight(
                to: first,
                chapterIndex: 0,
                text: "In an asynchronous distributed system with even a single unannounced process crash, no deterministic consensus protocol can guarantee termination in finite time across all admissible executions, yet practical systems circumvent this barrier via partial synchrony assumptions and randomized leader election.",
                color: .amber,
                location: nil
            )
            h?.note = "Cross-reference with FLP impossibility theorem (Fischer, Lynch, Paterson 1985) and HotStuff pipelining."
        }

        _ = createCollection(named: "Super Long Collection Name That Tests Horizontal Filter Chip Layout", with: Array(inserted.prefix(3)))
        _ = createCollection(named: "Empty Collection", with: [])
        _ = createCollection(named: "日本語", with: [inserted[2]])

        let minutes = [145, 0, 92, 180, 5, 240, 128]
        for (offset, value) in minutes.enumerated() where value > 0 {
            addReadingSeconds(value * 60, toDay: ReadingLog.dayKey(for: ago(days: Double(6 - offset))))
        }
        save()
        recomputeReadingStats()
        publishWidgetSnapshot()
        if ProcessInfo.processInfo.environment["CHICKEN_DEBUG_OPEN"] == "markdown",
           let markdownBook = inserted.first(where: { $0.format == .text }) {
            AppRouter.shared.pendingDestination = .book(markdownBook.id)
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

    func addDebugFurtherPositionIfRequested() {
        guard ProcessInfo.processInfo.environment["CHICKEN_DEBUG_FURTHER"] == "continue",
              let book = continueReadingBook() else { return }
        for position in book.positions ?? [] where position.device == "debug-ipad" {
            context.delete(position)
        }
        let position = ReadingPosition(device: "debug-ipad", deviceKind: "iPad")
        position.book = book
        position.progress = min(1, book.progress + 0.15)
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
