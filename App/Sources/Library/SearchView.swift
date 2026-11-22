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

    private var matchingBooks: [Book] {
        guard !trimmed.isEmpty else { return [] }
        return books.filter {
            $0.displayTitle.localizedStandardContains(trimmed)
                || $0.title.localizedStandardContains(trimmed)
                || $0.displayAuthor.localizedStandardContains(trimmed)
                || ($0.publisher?.localizedStandardContains(trimmed) ?? false)
                || $0.originalFileName.localizedStandardContains(trimmed)
        }
    }

    private var listedBooks: [Book] {
        trimmed.isEmpty ? Array(books.filter { $0.lastOpenedAt != nil }.prefix(6)) : Array(matchingBooks.prefix(60))
    }

    private var matchingHighlights: [Highlight] {
        guard !trimmed.isEmpty else { return [] }
        return highlights.filter { $0.text.localizedStandardContains(trimmed) || $0.note.localizedStandardContains(trimmed) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if trimmed.isEmpty {
                    suggestions
                } else if matchingBooks.isEmpty && matchingHighlights.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(palette.faint)
                        Text("Nothing matches \u{201C}\(trimmed)\u{201D}")
                            .font(.chickenUI(15.5))
                            .foregroundStyle(palette.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                } else {
                    if !matchingBooks.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionLabel(text: "Books", count: matchingBooks.count)
                            VStack(spacing: 0) {
                                ForEach(Array(matchingBooks.prefix(60).enumerated()), id: \.element.id) { index, book in
                                    SearchBookRow(book: book)
                                    if index < min(matchingBooks.count, 60) - 1 {
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
                    if !matchingHighlights.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionLabel(text: "In your highlights", count: matchingHighlights.count)
                            ForEach(matchingHighlights.prefix(40)) { highlight in
                                SearchHighlightCard(highlight: highlight)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, gutter)
            .padding(.top, sizeClass == .compact ? 2 : 12)
            .padding(.bottom, 96)
            .coverCollection("search", books: listedBooks.map(\.id))
            .frame(maxWidth: 820, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .background(palette.background.ignoresSafeArea())
        .pageTitle("Search")
        .searchable(text: $query, prompt: "Titles, authors, highlights")
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Search")
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
        if book.isFinished {
            parts.append("Finished")
        } else if book.progress > 0 {
            parts.append("\(Int((book.progress * 100).rounded()))% read")
        }
        if let pages = book.pageCount { parts.append("\(pages) pages") }
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
