import ChickenKit
import Foundation
import SwiftData

extension LibraryStore {
    static let currentCatalogEnrichVersion = 2

    func applyCatalogMatch(
        _ rawMatch: BookCatalogMatch,
        to book: Book,
        replaceCover: Bool,
        replaceExistingFields: Bool
    ) async {
        let token = CatalogTokenStore.loadHardcoverToken()
        let match = await BookCatalogClient.shared.hydrateDetails(for: rawMatch, hardcoverToken: token)
        let coversDirectory = paths.covers
        let shouldReplaceCover = (replaceCover || book.coverImageName == nil) && match.coverURL != nil

        var downloadedCoverName: String?
        var staleCoverFiles: [URL] = []
        if shouldReplaceCover, let coverURL = match.coverURL {
            if replaceCover, let existingName = book.coverImageName {
                staleCoverFiles = storedFiles(of: book).filter { $0.lastPathComponent == existingName }
            }
            if let data = await BookCatalogClient.shared.downloadCoverData(from: coverURL) {
                downloadedCoverName = await Self.encodeCoverData(data, bookID: book.id, directory: coversDirectory)
            }
        }

        if replaceExistingFields {
            if !match.title.isEmpty { book.title = match.title }
            if let author = match.authorLine { book.author = author }
            if let publisher = match.publisher { book.publisher = publisher }
            if let language = match.language { book.language = language }
            if let pageCount = match.pageCount { book.pageCount = pageCount }
            if let summary = match.summary { book.summary = summary }
            if let isbn = match.isbn { book.isbn = isbn }
            if let year = match.releaseYear { book.releaseYear = year }
            if let seriesName = match.seriesName { book.seriesName = seriesName }
            if let seriesPosition = match.seriesPosition { book.seriesPosition = seriesPosition }
            if !match.genres.isEmpty { book.genresCSV = match.genres.joined(separator: ",") }
            if !match.moods.isEmpty { book.moodsCSV = match.moods.joined(separator: ",") }
            if let rating = match.rating { book.catalogRating = rating }
            if let ratingsCount = match.ratingsCount { book.catalogRatingsCount = ratingsCount }
            if let url = match.catalogURL { book.catalogURLString = url.absoluteString }
            if let hcID = match.hardcoverBookID { book.hardcoverBookID = hcID }
        } else {
            _ = applyMissingCatalogFields(match, to: book)
        }

        if let downloadedCoverName {
            if !staleCoverFiles.isEmpty {
                await CloudFolders.removeAll(staleCoverFiles)
            }
            book.coverImageName = downloadedCoverName
            book.hasCatalogCover = true
            CoverImageCache.shared.invalidate()
            coversGeneration += 1
        }

        book.catalogChecked = true
        book.catalogEnrichVersion = Self.currentCatalogEnrichVersion
        save()
        moveFilesToICloud()
        publishWidgetSnapshot()
    }

    func scheduleCatalogEnrichmentIfNeeded() {
        guard preferences.autoEnrichMetadata, !catalogEnrichState.isEnriching else { return }
        let candidates = allBooks().filter {
            (!$0.catalogChecked || $0.catalogEnrichVersion < Self.currentCatalogEnrichVersion)
                && Self.needsCatalogEnrichment($0)
        }
        enqueueEnrichment(for: candidates, markChecked: true)
    }

    func enrichMissingMetadata() {
        let candidates = allBooks().filter(Self.needsCatalogEnrichment)
        enqueueEnrichment(for: candidates, markChecked: true)
    }

    func enrichBooksIfNeeded(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let idSet = Set(ids)
        let candidates = allBooks().filter { idSet.contains($0.id) && Self.needsCatalogEnrichment($0) }
        enqueueEnrichment(for: candidates, markChecked: true)
    }

    func nextInSeries(after book: Book) -> Book? {
        guard let series = book.seriesName?.trimmingCharacters(in: .whitespacesAndNewlines), !series.isEmpty else {
            return nil
        }
        let targetPos = book.seriesPosition ?? 0
        let candidates = allBooks().filter {
            $0.id != book.id
                && !$0.isFinished
                && ($0.seriesName ?? "").localizedCaseInsensitiveCompare(series) == .orderedSame
        }
        let ordered = candidates.sorted { lhs, rhs in
            let lp = lhs.seriesPosition ?? .greatestFiniteMagnitude
            let rp = rhs.seriesPosition ?? .greatestFiniteMagnitude
            if lp != rp { return lp < rp }
            return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
        }
        if let afterCurrent = ordered.first(where: { ($0.seriesPosition ?? 0) > targetPos }) {
            return afterCurrent
        }
        return ordered.first
    }

    func seriesBooks(for book: Book) -> [Book] {
        guard let series = book.seriesName?.trimmingCharacters(in: .whitespacesAndNewlines), !series.isEmpty else {
            return []
        }
        return allBooks()
            .filter { ($0.seriesName ?? "").localizedCaseInsensitiveCompare(series) == .orderedSame }
            .sorted { lhs, rhs in
                let lp = lhs.seriesPosition ?? .greatestFiniteMagnitude
                let rp = rhs.seriesPosition ?? .greatestFiniteMagnitude
                if lp != rp { return lp < rp }
                let ly = lhs.releaseYear ?? Int.max
                let ry = rhs.releaseYear ?? Int.max
                if ly != ry { return ly < ry }
                return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
            }
    }

    func otherBooksByAuthor(of book: Book) -> [Book] {
        guard let author = book.author?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty else {
            return []
        }
        let seriesIDs = Set(seriesBooks(for: book).map(\.id))
        return allBooks()
            .filter {
                $0.id != book.id
                    && !seriesIDs.contains($0.id)
                    && ($0.author ?? "").localizedCaseInsensitiveCompare(author) == .orderedSame
            }
            .sorted { lhs, rhs in
                let ly = lhs.releaseYear ?? Int.max
                let ry = rhs.releaseYear ?? Int.max
                if ly != ry { return ly < ry }
                return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
            }
    }

    func duplicateEdition(of book: Book) -> Book? {
        let isbn = (book.isbn ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let hcID = book.hardcoverBookID
        let catalogURL = (book.catalogURLString ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isbn.isEmpty || hcID != nil || !catalogURL.isEmpty else { return nil }
        return allBooks().first { other in
            guard other.id != book.id else { return false }
            if !isbn.isEmpty, other.isbn == isbn { return true }
            if let hcID, other.hardcoverBookID == hcID { return true }
            if !catalogURL.isEmpty, other.catalogURLString == catalogURL { return true }
            return false
        }
    }

    func syncHardcoverStatusIfEnabled(for book: Book, statusID: Int) {
        guard preferences.syncHardcoverStatus,
              let hcID = book.hardcoverBookID,
              hcID > 0,
              let token = CatalogTokenStore.loadHardcoverToken()
        else { return }
        Task.detached(priority: .utility) {
            _ = await BookCatalogClient.shared.syncHardcoverStatus(bookID: hcID, statusID: statusID, token: token)
        }
    }

    private func enqueueEnrichment(for candidates: [Book], markChecked: Bool) {
        guard !candidates.isEmpty, !catalogEnrichState.isEnriching else { return }
        let items = candidates.map { book in
            let localURL: URL? = {
                guard !book.isPhysical, (book.isbn ?? "").isEmpty else { return nil }
                let url = fileURL(for: book)
                return CloudFolders.isDownloaded(url) ? url : nil
            }()
            return EnrichmentWork(
                id: book.id,
                query: BookCatalogQuery(title: book.displayTitle, author: book.author, isbn: book.isbn),
                needsCover: !book.hasCatalogCover || book.coverImageName == nil,
                hadExistingCover: book.coverImageName != nil,
                fileURL: localURL,
                format: book.format
            )
        }
        let token = CatalogTokenStore.loadHardcoverToken()
        let coversDirectory = paths.covers
        catalogEnrichState = .enriching(completed: 0, total: items.count)

        catalogEnrichTask?.cancel()
        catalogEnrichTask = Task { [weak self] in
            var completed = 0
            var updated = 0
            var unsavedUpdates = 0
            for (index, item) in items.enumerated() {
                if Task.isCancelled { return }
                if index > 0 {
                    try? await Task.sleep(for: .milliseconds(400))
                    if Task.isCancelled { return }
                }
                let result = await Self.fetchEnrichment(item: item, token: token, coversDirectory: coversDirectory)
                guard !Task.isCancelled, let self else { return }
                completed += 1
                var staleFilesToRemove: [URL] = []
                if let book = self.book(id: item.id) {
                    var didUpdate = false
                    if let extractedISBN = result.extractedISBN, (book.isbn ?? "").isEmpty {
                        book.isbn = extractedISBN
                        didUpdate = true
                    }
                    if let match = result.match {
                        if self.applyMissingCatalogFields(match, to: book) {
                            didUpdate = true
                        }
                        if let coverName = result.coverImageName {
                            if let existingName = book.coverImageName, existingName != coverName {
                                staleFilesToRemove = self.storedFiles(of: book).filter { $0.lastPathComponent == existingName }
                            }
                            book.coverImageName = coverName
                            book.hasCatalogCover = true
                            CoverImageCache.shared.invalidate()
                            self.coversGeneration += 1
                            didUpdate = true
                        }
                    }
                    if markChecked {
                        book.catalogChecked = true
                        book.catalogEnrichVersion = Self.currentCatalogEnrichVersion
                    }
                    if didUpdate {
                        updated += 1
                        unsavedUpdates += 1
                        if unsavedUpdates >= 3 {
                            unsavedUpdates = 0
                            self.save()
                        }
                    }
                }
                if !staleFilesToRemove.isEmpty {
                    await CloudFolders.removeAll(staleFilesToRemove)
                }
                self.catalogEnrichState = .enriching(completed: completed, total: items.count)
            }
            guard !Task.isCancelled, let self else { return }
            if unsavedUpdates > 0 || markChecked {
                self.save()
            }
            if updated > 0 {
                self.moveFilesToICloud()
                self.publishWidgetSnapshot()
            }
            self.catalogEnrichState = .finished(updated: updated)
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            if case .finished = self.catalogEnrichState { self.catalogEnrichState = .idle }
        }
    }

    private func applyMissingCatalogFields(_ match: BookCatalogMatch, to book: Book) -> Bool {
        var didUpdate = false
        if let author = match.authorLine, (book.author ?? "").isEmpty {
            book.author = author
            didUpdate = true
        }
        if let publisher = match.publisher, (book.publisher ?? "").isEmpty {
            book.publisher = publisher
            didUpdate = true
        }
        if let language = match.language, (book.language ?? "").isEmpty {
            book.language = language
            didUpdate = true
        }
        if let pageCount = match.pageCount, (book.pageCount ?? 0) <= 0 {
            book.pageCount = pageCount
            didUpdate = true
        }
        if let summary = match.summary, (book.summary ?? "").isEmpty {
            book.summary = summary
            didUpdate = true
        }
        if let isbn = match.isbn, (book.isbn ?? "").isEmpty {
            book.isbn = isbn
            didUpdate = true
        }
        if let year = match.releaseYear, book.releaseYear == nil {
            book.releaseYear = year
            didUpdate = true
        }
        if let seriesName = match.seriesName, (book.seriesName ?? "").isEmpty {
            book.seriesName = seriesName
            didUpdate = true
        }
        if let seriesPosition = match.seriesPosition, book.seriesPosition == nil {
            book.seriesPosition = seriesPosition
            didUpdate = true
        }
        if !match.genres.isEmpty, (book.genresCSV ?? "").isEmpty {
            book.genresCSV = match.genres.joined(separator: ",")
            didUpdate = true
        }
        if !match.moods.isEmpty, (book.moodsCSV ?? "").isEmpty {
            book.moodsCSV = match.moods.joined(separator: ",")
            didUpdate = true
        }
        if let rating = match.rating, book.catalogRating == nil {
            book.catalogRating = rating
            didUpdate = true
        }
        if let ratingsCount = match.ratingsCount, book.catalogRatingsCount == nil {
            book.catalogRatingsCount = ratingsCount
            didUpdate = true
        }
        if let url = match.catalogURL, (book.catalogURLString ?? "").isEmpty {
            book.catalogURLString = url.absoluteString
            didUpdate = true
        }
        if let hcID = match.hardcoverBookID, book.hardcoverBookID == nil {
            book.hardcoverBookID = hcID
            didUpdate = true
        }
        return didUpdate
    }

    private static func needsCatalogEnrichment(_ book: Book) -> Bool {
        (book.summary ?? "").isEmpty
            || (book.author ?? "").isEmpty
            || (book.publisher ?? "").isEmpty
            || (book.pageCount ?? 0) <= 0
            || book.coverImageName == nil
            || !book.hasCatalogCover
            || book.releaseYear == nil
            || book.genres.isEmpty
    }

    @concurrent
    private static func encodeCoverData(_ data: Data, bookID: UUID, directory: URL) async -> String? {
        CoverRenderer.saveCover(from: data, id: bookID, in: directory)
    }

    @concurrent
    private static func fetchEnrichment(
        item: EnrichmentWork,
        token: String?,
        coversDirectory: URL
    ) async -> (match: BookCatalogMatch?, coverImageName: String?, extractedISBN: String?) {
        var query = item.query
        var extractedISBN: String?
        if query.isbn == nil, let url = item.fileURL {
            extractedISBN = DocumentMetadataReader.metadata(for: url, format: item.format).isbn
            query.isbn = extractedISBN
        }
        guard let match = await BookCatalogClient.shared.bestMatch(for: query, hardcoverToken: token) else {
            return (nil, nil, extractedISBN)
        }
        var coverName: String?
        if item.needsCover, let coverURL = match.coverURL,
           let data = await BookCatalogClient.shared.downloadCoverData(from: coverURL) {
            coverName = CoverRenderer.saveCover(
                from: data,
                id: item.id,
                in: coversDirectory,
                minWidth: item.hadExistingCover ? 200 : 80,
                minHeight: item.hadExistingCover ? 260 : 80
            )
        }
        return (match, coverName, extractedISBN)
    }

    @discardableResult
    func addPhysicalBook(
        from rawMatch: BookCatalogMatch,
        initialStatus: PhysicalBookStatus = .reading,
        currentPage: Int? = nil
    ) async -> Book {
        let now = Date()
        let title = rawMatch.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let book = Book(
            title: title.isEmpty ? "Untitled Book" : title,
            format: .physical,
            originalFileName: "",
            storedFileName: ""
        )
        book.importedAt = now
        book.lastActivityAt = now
        context.insert(book)

        await applyCatalogMatch(rawMatch, to: book, replaceCover: true, replaceExistingFields: true)

        applyInitialPhysicalStatus(initialStatus, currentPage: currentPage, to: book, at: now)
        save()
        syncHardcoverStatusIfEnabled(for: book, statusID: initialStatus.hardcoverStatusID)
        publishWidgetSnapshot()
        return book
    }

    @discardableResult
    func addManualPhysicalBook(
        title: String,
        author: String?,
        isbn: String?,
        pageCount: Int?,
        releaseYear: Int?,
        publisher: String?,
        initialStatus: PhysicalBookStatus = .reading,
        currentPage: Int? = nil
    ) -> Book {
        let now = Date()
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let book = Book(
            title: cleanTitle.isEmpty ? "Untitled Book" : cleanTitle,
            format: .physical,
            originalFileName: "",
            storedFileName: ""
        )
        book.importedAt = now
        book.lastActivityAt = now
        let cleanAuthor = author?.trimmingCharacters(in: .whitespacesAndNewlines)
        book.author = (cleanAuthor?.isEmpty == false) ? cleanAuthor : nil
        let cleanISBN = isbn.flatMap(ISBNExtractor.normalize) ?? isbn?.trimmingCharacters(in: .whitespacesAndNewlines)
        book.isbn = (cleanISBN?.isEmpty == false) ? cleanISBN : nil
        if let pageCount, pageCount > 0 { book.pageCount = pageCount }
        book.releaseYear = releaseYear
        let cleanPublisher = publisher?.trimmingCharacters(in: .whitespacesAndNewlines)
        book.publisher = (cleanPublisher?.isEmpty == false) ? cleanPublisher : nil
        book.catalogChecked = false
        context.insert(book)

        applyInitialPhysicalStatus(initialStatus, currentPage: currentPage, to: book, at: now)
        save()
        publishWidgetSnapshot()
        if book.author != nil || book.isbn != nil {
            enrichBooksIfNeeded(ids: [book.id])
        }
        return book
    }

    @discardableResult
    func logPhysicalProgress(
        for book: Book,
        currentPage: Int?,
        totalPages: Int?,
        percent: Double?,
        durationSeconds: Int,
        quoteText: String?,
        quoteNote: String?,
        quoteColor: HighlightColor = .amber
    ) -> Bool {
        let now = Date()
        let wasFinished = book.isFinished
        let hadStarted = book.progress > 0 || book.lastOpenedAt != nil
        let previousPage = book.currentPageNumber

        if let totalPages, totalPages > 0 {
            book.pageCount = totalPages
        }

        var nextProgress = book.progress
        var locationLabel = book.lastLocation

        if let currentPage, let knownTotal = book.pageCount, knownTotal > 0 {
            let clampedPage = min(max(currentPage, 0), knownTotal)
            nextProgress = Double(clampedPage) / Double(knownTotal)
            locationLabel = "Page \(clampedPage) of \(knownTotal)"
        } else if let currentPage, currentPage >= 0 {
            if let percent {
                nextProgress = min(max(percent, 0), 1)
            }
            locationLabel = "Page \(currentPage)"
        } else if let percent {
            nextProgress = min(max(percent, 0), 1)
            locationLabel = "\(Int((nextProgress * 100).rounded()))%"
        }

        book.progress = min(max(nextProgress, 0), 1)
        if let locationLabel {
            book.lastLocation = locationLabel
        }
        book.recordOpen(at: now)

        if book.progress >= 1 {
            book.markFinished(at: now)
            if !wasFinished {
                syncHardcoverStatusIfEnabled(for: book, statusID: 3)
            }
        } else {
            book.finishedAt = nil
            if !wasFinished && !hadStarted && book.progress > 0 {
                syncHardcoverStatusIfEnabled(for: book, statusID: 2)
            }
        }

        if durationSeconds > 0 {
            addReadingSeconds(durationSeconds, toDay: ReadingLog.dayKey(for: now))
            if let prev = previousPage, let currentPage, currentPage > prev {
                recordReadingPace(pagesRead: Double(currentPage - prev), elapsedSeconds: Double(durationSeconds))
            }
        }

        if let quoteText,
           let highlight = addHighlight(
               to: book,
               chapterIndex: max(0, currentPage ?? 0),
               text: quoteText,
               color: quoteColor,
               location: locationLabel
           ) {
            let trimmedNote = quoteNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmedNote.isEmpty {
                updateNote(trimmedNote, on: highlight)
            }
        }

        save()
        recomputeReadingStats()
        publishWidgetSnapshot()
        return book.isFinished && !wasFinished
    }

    private func applyInitialPhysicalStatus(
        _ status: PhysicalBookStatus,
        currentPage: Int?,
        to book: Book,
        at date: Date
    ) {
        switch status {
        case .wantToRead:
            book.progress = 0
            book.finishedAt = nil
            book.lastOpenedAt = nil
        case .reading:
            book.finishedAt = nil
            book.lastOpenedAt = date
            if let currentPage, currentPage > 0 {
                if let total = book.pageCount, total > 0 {
                    let clamped = min(currentPage, total)
                    book.progress = min(0.999, Double(clamped) / Double(total))
                    book.lastLocation = "Page \(clamped) of \(total)"
                } else {
                    book.progress = 0.05
                    book.lastLocation = "Page \(currentPage)"
                }
            }
        case .finished:
            book.markFinished(at: date)
            book.lastOpenedAt = date
            if let total = book.pageCount, total > 0 {
                book.lastLocation = "Page \(total) of \(total)"
            }
        }
    }
}

enum PhysicalBookStatus: String, CaseIterable, Identifiable {
    case reading
    case wantToRead
    case finished

    var id: String { rawValue }

    var label: String {
        switch self {
        case .reading: "Reading Now"
        case .wantToRead: "Want to Read"
        case .finished: "Finished"
        }
    }

    var hardcoverStatusID: Int {
        switch self {
        case .wantToRead: 1
        case .reading: 2
        case .finished: 3
        }
    }
}

nonisolated private struct EnrichmentWork: Sendable {
    let id: UUID
    let query: BookCatalogQuery
    let needsCover: Bool
    let hadExistingCover: Bool
    let fileURL: URL?
    let format: BookFormat
}
