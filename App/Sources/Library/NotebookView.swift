import ChickenKit
import SwiftData
import SwiftUI

struct NotebookView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.palette) private var palette
    @Environment(\.openBook) private var openBook
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Highlight.createdAt, order: .reverse) private var highlights: [Highlight]

    @State private var color: HighlightColor?
    @State private var query = ""
    @State private var revisitOffset = 0

    private var gutter: CGFloat { sizeClass == .compact ? 20 : 40 }
    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var featuredHighlight: (highlight: Highlight, book: Book)? {
        guard highlights.count >= 4 else { return nil }
        let valid = highlights.compactMap { h -> (Highlight, Book)? in
            guard let book = h.book, h.text.count >= 24 else { return nil }
            return (h, book)
        }
        guard !valid.isEmpty else { return nil }
        let daySeed = ReadingLog.dayKey(for: Date()).stableChickenHash
        let index = (Int(daySeed % UInt64(valid.count)) + revisitOffset) % valid.count
        return valid[index]
    }

    private var filtered: [Highlight] {
        highlights.filter { item in
            if let color, item.color != color { return false }
            if !trimmedQuery.isEmpty {
                let inText = item.text.localizedStandardContains(trimmedQuery)
                let inNote = item.note.localizedStandardContains(trimmedQuery)
                let inBook = item.book?.displayTitle.localizedStandardContains(trimmedQuery) ?? false
                return inText || inNote || inBook
            }
            return true
        }
    }

    private var groups: [(book: Book, highlights: [Highlight])] {
        var order: [UUID] = []
        var byBook: [UUID: (Book, [Highlight])] = [:]
        for highlight in filtered {
            guard let book = highlight.book else { continue }
            if byBook[book.id] == nil {
                order.append(book.id)
                byBook[book.id] = (book, [])
            }
            byBook[book.id]?.1.append(highlight)
        }
        return order.compactMap { byBook[$0] }.map { (book: $0.0, highlights: $0.1) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                PageHeader(title: "Notebook")
                    .padding(.horizontal, gutter)
                    .padding(.bottom, 18)

                if highlights.isEmpty {
                    emptyState.padding(.horizontal, gutter)
                } else {
                    if trimmedQuery.isEmpty, color == nil, let featured = featuredHighlight {
                        RevisitPassageCard(
                            highlight: featured.highlight,
                            book: featured.book,
                            onJump: {
                                openBook(
                                    featured.book.id,
                                    jumpTo: JumpTarget(location: featured.highlight.location, chapterIndex: featured.highlight.chapterIndex)
                                )
                            },
                            onShare: {
                                router.presentSheet(.quoteCard(QuoteCardRequest(
                                    quote: featured.highlight.text,
                                    note: featured.highlight.note,
                                    bookTitle: featured.book.displayTitle,
                                    author: featured.book.displayAuthor,
                                    highlightColor: featured.highlight.color,
                                    coverTintIndex: featured.book.coverTintIndex
                                )))
                            },
                            onShuffle: {
                                Haptics.selection()
                                withAnimation(reduceMotion ? nil : ChickenMotion.snappy) {
                                    revisitOffset += 1
                                }
                            }
                        )
                        .padding(.horizontal, gutter)
                        .padding(.bottom, 18)
                    }

                    colorFilter
                        .padding(.bottom, 12)

                    if groups.isEmpty {
                        Text("No passages match your filter.")
                            .font(.chickenUI(14.5))
                            .foregroundStyle(palette.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 48)
                    } else {
                        ForEach(groups, id: \.book.id) { group in
                            NotebookBookSection(book: group.book, highlights: group.highlights)
                                .padding(.horizontal, gutter)
                                .padding(.top, 24)
                        }
                        .coverCollection("notebook", books: groups.map(\.book.id))
                    }
                }
            }
            .padding(.top, sizeClass == .compact ? 6 : 24)
            .padding(.bottom, 96)
            .frame(maxWidth: 820, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.hard, for: .top)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .background(palette.background.ignoresSafeArea())
        .pageTitle("Notebook")
        .searchable(text: $query, prompt: "Filter quotes, notes, or books")
        .toolbar { LibraryToolbar() }
    }

    private var colorFilter: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    colorPill(nil, label: "All", count: highlights.count)
                    ForEach(HighlightColor.allCases) { option in
                        let count = highlights.filter { $0.color == option }.count
                        if count > 0 { colorPill(option, label: option.label, count: count) }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .scrollIndicators(.never)
        .contentMargins(.horizontal, gutter, for: .scrollContent)
    }

    private func colorPill(_ option: HighlightColor?, label: String, count: Int) -> some View {
        let selected = color == option
        return Button {
            Haptics.selection()
            withAnimation(reduceMotion ? nil : ChickenMotion.snappy) { color = option }
        } label: {
            HStack(alignment: .center, spacing: 6) {
                if let option {
                    Circle().fill(option.bar).frame(width: 8, height: 8)
                }
                Text(label)
                    .font(.chickenUI(13, weight: selected ? .semibold : .medium))
                Text("\(count)")
                    .font(.chickenMono(11, weight: .medium))
                    .opacity(selected ? 0.78 : 0.6)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .chickenGlassPill(isSelected: selected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Self.sampleHighlight())
                .font(.chickenSerif(21))
                .foregroundStyle(palette.text)
                .lineSpacing(6)
            Text("Select any passage while reading to keep it in your commonplace book.")
                .font(.chickenUI(14.5))
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(palette.surface)
                .stroke(palette.border, lineWidth: 0.5)
        )
    }

    private static func sampleHighlight() -> AttributedString {
        var text = AttributedString("Select a passage you love, ")
        var marked = AttributedString("and keep it.")
        marked.backgroundColor = HighlightColor.amber.fill
        text.append(marked)
        return text
    }
}

private struct RevisitPassageCard: View {
    @Environment(\.palette) private var palette
    let highlight: Highlight
    let book: Book
    let onJump: () -> Void
    let onShare: () -> Void
    let onShuffle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text("Passage to revisit")
                    .chickenEyebrow(palette, color: palette.ribbon)
                Spacer()
                Button(action: onShuffle) {
                    Image(systemName: "arrow.trianglehead.2.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.muted)
                        .frame(width: 26, height: 26)
                        .contentShape(Circle())
                }
                .buttonStyle(TactilePressStyle(scale: 0.92))
                .accessibilityLabel("Show another passage")

                Button(action: onShare) {
                    Label("Quote Card", systemImage: "square.and.arrow.up")
                        .font(.chickenUI(12, weight: .semibold))
                        .foregroundStyle(palette.muted)
                }
                .buttonStyle(TactilePressStyle(scale: 0.96))
            }

            Button(action: onJump) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\u{201C}\(highlight.text)\u{201D}")
                        .font(.chickenSerif(19.5))
                        .foregroundStyle(palette.text)
                        .lineSpacing(6.5)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if !highlight.note.isEmpty {
                        Text(highlight.note)
                            .font(.chickenSerif(14.5, italic: true))
                            .foregroundStyle(palette.muted)
                            .multilineTextAlignment(.leading)
                    }

                    HStack(spacing: 10) {
                        BookCover(book: book, style: .mini)
                            .frame(width: 22, height: 33)
                            .shadow(color: palette.shadow, radius: 2, y: 1)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(book.displayTitle)
                                .font(.chickenUI(13, weight: .semibold))
                                .foregroundStyle(palette.text)
                                .lineLimit(1)
                            if let author = book.author, !author.isEmpty {
                                Text(author)
                                    .font(.chickenUI(11.5))
                                    .foregroundStyle(palette.muted)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(palette.faint)
                    }
                    .padding(.top, 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(TactilePressStyle(scale: 0.99))
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(palette.surface)
                .stroke(palette.border, lineWidth: 0.5)
        )
    }
}

private struct NotebookBookSection: View {
    @Environment(\.palette) private var palette
    @Environment(\.coverContext) private var coverContext
    @Environment(\.bookSequence) private var bookSequence
    @Environment(\.selectBook) private var selectBook
    let book: Book
    let highlights: [Highlight]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { selectBook(book.id, in: bookSequence, from: CoverSource(context: coverContext, bookID: book.id)) } label: {
                HStack(alignment: .center, spacing: 12) {
                    BookCover(book: book, style: .mini)
                        .frame(width: 30, height: 45)
                        .shadow(color: palette.shadow, radius: 3, x: 0, y: 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(book.displayTitle)
                            .font(.chickenDisplay(16.5))
                            .tracking(-0.3)
                            .foregroundStyle(palette.text)
                            .lineLimit(2)
                        if let author = book.author, !author.isEmpty {
                            Text(author)
                                .font(.chickenUI(12.5))
                                .foregroundStyle(palette.muted)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.faint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(highlights) { highlight in
                    NotebookHighlightCard(book: book, highlight: highlight)
                }
            }
            .chickenSwipeActionsContainer()
        }
    }
}

private struct NotebookHighlightCard: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppRouter.self) private var router
    @Environment(\.palette) private var palette
    @Environment(\.openBook) private var openBook
    let book: Book
    let highlight: Highlight

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: openAtHighlight) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(marked)
                        .font(.chickenSerif(16.5))
                        .foregroundStyle(palette.text)
                        .lineSpacing(6)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if !highlight.note.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Rectangle().fill(highlight.color.bar).frame(width: 10, height: 1.5)
                                .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 5 }
                            Text(highlight.note)
                                .font(.chickenSerif(14, italic: true))
                                .foregroundStyle(palette.muted)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 12) {
                Text(highlight.createdAt.shortRelativeDescription)
                    .font(.chickenUI(11))
                    .foregroundStyle(palette.faint)
                Spacer(minLength: 8)
                Button(action: shareQuoteCard) {
                    Label("Quote Card", systemImage: "square.and.arrow.up")
                        .font(.chickenUI(11.5, weight: .medium))
                        .foregroundStyle(palette.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(palette.surface)
                .stroke(palette.border, lineWidth: 0.5)
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Remove", systemImage: "trash", role: .destructive) {
                library.removeHighlight(highlight)
            }
            Button("Quote Card", systemImage: "square.and.arrow.up") {
                shareQuoteCard()
            }
            .tint(palette.ribbon)
        }
        .contextMenu {
            Button("Open at This Passage", systemImage: "book") { openAtHighlight() }
            Button("Share Quote Card…", systemImage: "square.and.arrow.up") { shareQuoteCard() }
            Button("Copy", systemImage: "doc.on.doc") { Clipboard.copy(highlight.text) }
            Divider()
            Button("Remove Highlight", systemImage: "trash", role: .destructive) { library.removeHighlight(highlight) }
        }
    }

    private var marked: AttributedString {
        var text = AttributedString(highlight.text)
        text.backgroundColor = highlight.color.fill
        return text
    }

    private func openAtHighlight() {
        openBook(book.id, jumpTo: JumpTarget(location: highlight.location, chapterIndex: highlight.chapterIndex))
    }

    private func shareQuoteCard() {
        router.presentSheet(.quoteCard(QuoteCardRequest(
            quote: highlight.text,
            note: highlight.note,
            bookTitle: book.displayTitle,
            author: book.displayAuthor,
            highlightColor: highlight.color,
            coverTintIndex: book.coverTintIndex
        )))
    }
}
