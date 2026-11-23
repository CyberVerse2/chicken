import ChickenKit
import SwiftData
import SwiftUI

struct LibrarySearchView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppRouter.self) private var router
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.openBook) private var openBook
    @Query(sort: \Book.lastActivityAt, order: .reverse) private var books: [Book]
    @Query(sort: \Highlight.createdAt, order: .reverse) private var allHighlights: [Highlight]

    @State private var searchQuery = ""

    private var gutter: CGFloat { sizeClass == .compact ? 20 : 40 }
    private var trimmedQuery: String { searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var matchedBooks: [Book] {
        let q = trimmedQuery
        guard !q.isEmpty else { return [] }
        return books.filter { bookMatches($0, query: q) }
    }

    private var matchReasons: [UUID: String] {
        let q = trimmedQuery
        guard !q.isEmpty else { return [:] }
        var reasons: [UUID: String] = [:]
        for book in matchedBooks {
            if let reason = matchReason(for: book, query: q) {
                reasons[book.id] = reason
            }
        }
        return reasons
    }

    private var matchedHighlights: [(highlight: Highlight, book: Book)] {
        let q = trimmedQuery
        guard !q.isEmpty else { return [] }
        return allHighlights.compactMap { highlight in
            guard let book = highlight.book else { return nil }
            let hit = highlight.text.localizedStandardContains(q)
                || highlight.note.localizedStandardContains(q)
                || book.displayTitle.localizedStandardContains(q)
            return hit ? (highlight, book) : nil
        }
        .prefix(20)
        .map { $0 }
    }

    private var topGenres: [(name: String, count: Int)] {
        var counts: [String: (name: String, count: Int)] = [:]
        for book in books {
            for genre in book.genres {
                let key = genre.lowercased()
                let existing = counts[key]
                counts[key] = (existing?.name ?? genre, (existing?.count ?? 0) + 1)
            }
        }
        return counts.values
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.name < rhs.name
            }
            .prefix(10)
            .map { $0 }
    }

    private var recentlyAdded: [Book] {
        Array(books.sorted { $0.importedAt > $1.importedAt }.prefix(12))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if trimmedQuery.isEmpty {
                    ChickenScreenHeader(title: "Search")
                        .padding(.horizontal, gutter)

                    if books.isEmpty {
                        EmptyLibraryView()
                            .padding(.horizontal, gutter)
                    } else {
                        quickFiltersSection
                        if !topGenres.isEmpty {
                            genresSection
                        }
                        if !recentlyAdded.isEmpty {
                            BookShelf(title: "Recently Added", books: recentlyAdded, gutter: gutter)
                        }
                    }
                } else if matchedBooks.isEmpty && matchedHighlights.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(palette.faint)
                        Text("No matches for \u{201C}\(trimmedQuery)\u{201D}")
                            .font(.chickenDisplay(20))
                            .foregroundStyle(palette.text)
                        Text("Try a title, author, series, genre, or word from a highlight.")
                            .font(.chickenUI(13.5))
                            .foregroundStyle(palette.muted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 72)
                    .padding(.horizontal, gutter)
                } else {
                    if !matchedBooks.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            ShelfSectionHeader(title: "Books", count: matchedBooks.count)
                            BookGrid(books: matchedBooks, matchReasons: matchReasons)
                        }
                        .padding(.horizontal, gutter)
                    }

                    if !matchedHighlights.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            ShelfSectionHeader(title: "Highlights", count: matchedHighlights.count)
                            LazyVStack(spacing: 10) {
                                ForEach(matchedHighlights, id: \.highlight.id) { item in
                                    Button {
                                        openBook(item.book.id, jumpTo: JumpTarget(location: item.highlight.location, chapterIndex: item.highlight.chapterIndex))
                                    } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(item.highlight.text)
                                                .font(.chickenSerif(15))
                                                .foregroundStyle(palette.text)
                                                .lineLimit(3)
                                                .multilineTextAlignment(.leading)
                                            Text(item.book.displayTitle)
                                                .font(.chickenUI(12, weight: .medium))
                                                .foregroundStyle(palette.muted)
                                                .lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(14)
                                        .background(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .fill(palette.surface)
                                                .stroke(palette.border, lineWidth: 0.5)
                                        )
                                    }
                                    .buttonStyle(TactilePressStyle(scale: 0.99))
                                }
                            }
                        }
                        .padding(.horizontal, gutter)
                    }
                }
            }
            .padding(.top, sizeClass == .compact ? 6 : 20)
            .padding(.bottom, 96)
            .frame(maxWidth: 1180, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .background(palette.background.ignoresSafeArea())
        .pageTitle("Search")
        .searchable(text: $searchQuery, prompt: "Books, authors, series, genres, or notes")
    }

    private var quickFiltersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ShelfSectionHeader(title: "Browse by Shelf")
                .padding(.horizontal, gutter)

            let items: [(title: String, icon: String, action: () -> Void)] = [
                ("Reading Now", "book", { router.openLibrary(scope: .reading) }),
                ("Unread", "books.vertical", { router.openLibrary(scope: .unread) }),
                ("Finished", "checkmark.circle", { router.openLibrary(scope: .finished) }),
                ("Collections", "rectangle.stack", { router.openLibrary(scope: .collections) }),
                ("Quick Reads", "bolt", { router.openLibrary(scope: .all, secondaryFilter: .quickReads) }),
                ("EPUBs", "doc.richtext", { router.openLibrary(scope: .all, secondaryFilter: .epub) }),
                ("PDFs", "doc.text", { router.openLibrary(scope: .all, secondaryFilter: .pdf) }),
                ("Print", "book.closed", { router.openLibrary(scope: .all, secondaryFilter: .physical) }),
            ]

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 146, maximum: 220), spacing: 10)],
                spacing: 10
            ) {
                ForEach(items, id: \.title) { item in
                    Button {
                        Haptics.selection()
                        item.action()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(palette.ribbon)
                                .frame(width: 24)
                            Text(item.title)
                                .font(.chickenUI(14, weight: .semibold))
                                .foregroundStyle(palette.text)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.faint)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(palette.surface)
                                .stroke(palette.border, lineWidth: 0.5)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(TactilePressStyle(scale: 0.98))
                }
            }
            .padding(.horizontal, gutter)
        }
    }

    private var genresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ShelfSectionHeader(title: "Genres")
                .padding(.horizontal, gutter)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(topGenres, id: \.name) { genre in
                        Button {
                            Haptics.selection()
                            router.openLibrary(scope: .all, facet: .genre(genre.name))
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text(genre.name)
                                    .font(.chickenUI(13.5, weight: .medium))
                                Text("\(genre.count)")
                                    .font(.chickenMono(11, weight: .medium))
                                    .foregroundStyle(palette.muted)
                            }
                            .foregroundStyle(palette.text)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(palette.surface, in: Capsule())
                            .overlay(Capsule().stroke(palette.border, lineWidth: 0.5))
                        }
                        .buttonStyle(TactilePressStyle(scale: 0.97))
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.never)
            .contentMargins(.horizontal, gutter, for: .scrollContent)
        }
    }

    private func bookMatches(_ book: Book, query q: String) -> Bool {
        if book.displayTitle.localizedStandardContains(q) || book.title.localizedStandardContains(q) { return true }
        if (book.author ?? "").localizedStandardContains(q) { return true }
        if (book.seriesName ?? "").localizedStandardContains(q) { return true }
        if (book.summary ?? "").localizedStandardContains(q) { return true }
        if (book.publisher ?? "").localizedStandardContains(q) { return true }
        if (book.isbn ?? "").localizedStandardContains(q) { return true }
        if let year = book.releaseYear, String(year).contains(q) { return true }
        if book.genres.contains(where: { $0.localizedStandardContains(q) }) { return true }
        if book.moods.contains(where: { $0.localizedStandardContains(q) }) { return true }
        return false
    }

    private func matchReason(for book: Book, query q: String) -> String? {
        if book.displayTitle.localizedStandardContains(q) || book.title.localizedStandardContains(q) {
            return nil
        }
        if (book.author ?? "").localizedStandardContains(q) { return "Author" }
        if (book.seriesName ?? "").localizedStandardContains(q) { return "Series" }
        if book.genres.contains(where: { $0.localizedStandardContains(q) }) { return "Genre" }
        if book.moods.contains(where: { $0.localizedStandardContains(q) }) { return "Mood" }
        if let year = book.releaseYear, String(year).contains(q) { return String(year) }
        if (book.publisher ?? "").localizedStandardContains(q) { return "Publisher" }
        if (book.isbn ?? "").localizedStandardContains(q) { return "ISBN" }
        if (book.summary ?? "").localizedStandardContains(q) { return "Synopsis" }
        return nil
    }
}
