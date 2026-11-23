import ChickenKit
import SwiftData
import SwiftUI

struct SearchView: View {
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: \Book.lastActivityAt, order: .reverse) private var books: [Book]
    @Query(sort: \Highlight.createdAt, order: .reverse) private var highlights: [Highlight]
    @State private var query = ""

    private var gutter: CGFloat { sizeClass == .compact ? 20 : 40 }
    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func matchingBooks(for term: String) -> [Book] {
        guard !term.isEmpty else { return [] }
        return books.filter {
            $0.displayTitle.localizedStandardContains(term)
                || $0.title.localizedStandardContains(term)
                || $0.displayAuthor.localizedStandardContains(term)
                || ($0.seriesName?.localizedStandardContains(term) ?? false)
                || $0.genres.contains { $0.localizedStandardContains(term) }
                || $0.moods.contains { $0.localizedStandardContains(term) }
                || ($0.summary?.localizedStandardContains(term) ?? false)
                || ($0.isbn?.localizedStandardContains(term) ?? false)
                || ($0.publisher?.localizedStandardContains(term) ?? false)
                || ($0.language?.localizedStandardContains(term) ?? false)
                || ($0.releaseYear.map(String.init) == term)
                || $0.originalFileName.localizedStandardContains(term)
        }
    }

    private var suggestedTags: [String] {
        var counts: [String: (label: String, count: Int)] = [:]
        for book in books {
            for tag in book.genres + book.moods {
                let key = tag.lowercased()
                let existing = counts[key]
                counts[key] = (existing?.label ?? tag, (existing?.count ?? 0) + 1)
            }
        }
        return counts.values
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.label < rhs.label
            }
            .prefix(8)
            .map(\.label)
    }

    private func matchingHighlights(for term: String) -> [Highlight] {
        guard !term.isEmpty else { return [] }
        return highlights.filter { $0.text.localizedStandardContains(term) || $0.note.localizedStandardContains(term) }
    }

    var body: some View {
        let term = trimmed
        let bookHits = matchingBooks(for: term)
        let highlightHits = matchingHighlights(for: term)
        let listed = term.isEmpty ? Array(books.filter { $0.lastOpenedAt != nil }.prefix(6)) : Array(bookHits.prefix(60))
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if term.isEmpty {
                    suggestions
                } else if bookHits.isEmpty && highlightHits.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(palette.faint)
                        Text("Nothing matches \u{201C}\(term)\u{201D}")
                            .font(.chickenUI(15.5))
                            .foregroundStyle(palette.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                } else {
                    if !bookHits.isEmpty {
                        let shownCount = min(bookHits.count, 60)
                        VStack(alignment: .leading, spacing: 12) {
                            SectionLabel(text: "Books", count: bookHits.count)
                            VStack(spacing: 0) {
                                ForEach(Array(bookHits.prefix(60).enumerated()), id: \.element.id) { index, book in
                                    SearchBookRow(book: book)
                                    if index < shownCount - 1 {
                                        Rectangle().fill(palette.border).frame(height: 0.5).padding(.leading, 74)
                                    }
                                }
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(palette.surface)
                                    .stroke(palette.border, lineWidth: 0.5)
                            )
                        }
                    }
                    if !highlightHits.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionLabel(text: "In your highlights", count: highlightHits.count)
                            ForEach(highlightHits.prefix(40)) { highlight in
                                SearchHighlightCard(highlight: highlight)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, gutter)
            .padding(.top, sizeClass == .compact ? 2 : 12)
            .padding(.bottom, 96)
            .coverCollection("search", books: listed.map(\.id))
            .frame(maxWidth: 820, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .background(palette.background.ignoresSafeArea())
        .pageTitle("Search")
        .searchable(text: $query, prompt: "Titles, authors, genres, highlights")
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Search")
            let tags = suggestedTags
            if !tags.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(tags, id: \.self) { tag in
                            Button {
                                Haptics.selection()
                                query = tag
                            } label: {
                                Text(tag)
                                    .font(.chickenUI(13, weight: .medium))
                                    .foregroundStyle(palette.text)
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 7)
                                    .background(palette.surface, in: Capsule())
                                    .overlay(Capsule().stroke(palette.border, lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.never)
            }
            let recent = books.filter { $0.lastOpenedAt != nil }.prefix(6)
            if !recent.isEmpty {
                SectionLabel(text: "Recently opened")
                    .padding(.top, 8)
                VStack(spacing: 0) {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { index, book in
                        SearchBookRow(book: book)
                        if index < recent.count - 1 {
                            Rectangle().fill(palette.border).frame(height: 0.5).padding(.leading, 74)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(palette.surface)
                        .stroke(palette.border, lineWidth: 0.5)
                )
            }
        }
    }
}

private struct SearchBookRow: View {
    @Environment(\.palette) private var palette
    @Environment(\.coverContext) private var coverContext
    @Environment(\.bookSequence) private var bookSequence
    @Environment(\.selectBook) private var selectBook
    let book: Book

    var body: some View {
        Button { selectBook(book.id, in: bookSequence, from: CoverSource(context: coverContext, bookID: book.id)) } label: {
            HStack(spacing: 16) {
                BookCover(book: book, style: .mini)
                    .frame(width: 40, height: 60)
                    .coverTransitionSource(book.id)
                    .shadow(color: palette.shadow, radius: 3, y: 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(book.displayTitle)
                        .font(.chickenUI(15, weight: .semibold))
                        .foregroundStyle(palette.text)
                        .lineLimit(2)
                    if let author = book.author, !author.isEmpty {
                        Text(author)
                            .font(.chickenUI(13))
                            .foregroundStyle(palette.muted)
                            .lineLimit(1)
                    }
                    if !meta.isEmpty {
                        Text(meta)
                            .font(.chickenMono(11))
                            .foregroundStyle(palette.faint)
                    }
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(TactilePressStyle(scale: 0.99))
        .bookContextMenu(book)
    }

    private var meta: String {
        var parts: [String] = []
        if let series = book.seriesBadgeText { parts.append(series) }
        if book.isFinished {
            parts.append("Finished")
        } else if book.progress > 0 {
            parts.append("\(Int((book.progress * 100).rounded()))% read")
        }
        if let year = book.releaseYear { parts.append(String(year)) }
        if let rating = book.formattedRating { parts.append("★ \(rating)") }
        if let pages = book.pageCount, pages > 0 { parts.append("\(pages) pages") }
        return parts.joined(separator: " · ")
    }
}

private struct SearchHighlightCard: View {
    @Environment(\.palette) private var palette
    @Environment(\.openBook) private var openBook
    let highlight: Highlight

    var body: some View {
        Button {
            guard let book = highlight.book else { return }
            openBook(book.id, jumpTo: JumpTarget(location: highlight.location, chapterIndex: highlight.chapterIndex))
        } label: {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text({
                        var text = AttributedString(highlight.text)
                        text.backgroundColor = highlight.color.fill
                        return text
                    }())
                    .font(.chickenSerif(16))
                    .foregroundStyle(palette.text)
                    .lineSpacing(5)
                    .multilineTextAlignment(.leading)
                    Text(highlight.book?.displayTitle ?? "")
                        .font(.chickenUI(12.5, weight: .medium))
                        .foregroundStyle(palette.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(palette.surface)
                    .stroke(palette.border, lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(TactilePressStyle(scale: 0.99))
    }
}
