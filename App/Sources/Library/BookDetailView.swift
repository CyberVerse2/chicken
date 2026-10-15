import ChickenKit
import SwiftUI

/// Details for a run of books, one per page: swipe sideways to the next
/// book on the shelf, as in a printed catalogue.
struct BookDetailPager: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.coverNamespace) private var coverNamespace
    let ids: [UUID]
    @State private var current: UUID?
    /// The book being read from this card, and the cover it zoomed from.
    @State private var reading: ReaderRequest?

    private struct ReaderRequest: Identifiable {
        let id: UUID
        let source: CoverSource?
    }

    init(ids: [UUID], start: UUID) {
        self.ids = ids.contains(start) ? ids : [start]
        _current = State(initialValue: start)
    }

    var body: some View {
        NavigationStack {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(ids, id: \.self) { id in
                        BookDetailView(bookID: id)
                            .containerRelativeFrame(.horizontal)
                            // Neighbors sit slightly back, so a swipe reads as
                            // sliding one book off the pile and the next on.
                            .scrollTransition(.interactive, axis: .horizontal) { page, phase in
                                page
                                    .scaleEffect(1 - abs(phase.value) * 0.07)
                                    .opacity(1 - abs(phase.value) * 0.35)
                            }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $current)
            .scrollIndicators(.hidden)
            .background(palette.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
                if ids.count > 1, let current, let index = ids.firstIndex(of: current) {
                    ToolbarItem(placement: .principal) {
                        Text("\(index + 1) of \(ids.count)")
                            .font(.chickenMono(12, weight: .medium))
                            .foregroundStyle(palette.muted)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: index)
                    }
                }
            }
        }
        .coverCollection("detail", books: ids)
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 640, minHeight: 600, idealHeight: 720)
        #else
        .presentationDetents([.large])
        .environment(\.openBook, OpenBookAction { id, source in
            reading = ReaderRequest(id: id, source: source)
        })
        .fullScreenCover(item: $reading) { request in
            if let coverNamespace {
                ReaderLoader(bookID: request.id)
                    .zoomTransition(from: request.source, in: coverNamespace)
            } else {
                ReaderLoader(bookID: request.id)
            }
        }
        #endif
    }
}

/// About a book: cover, description, where you are, and what's in it.
/// One page of `BookDetailPager`, or a page of its own when a book is
/// picked in the Mac sidebar.
struct BookDetailView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.palette) private var palette
    @Environment(\.openBook) private var openBook
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.coverContext) private var coverContext
    let bookID: UUID
    var isPage = false
    /// In the Mac's details panel: narrower, and nothing to dismiss.
    var inInspector = false
    @State private var summaryExpanded = false
    @State private var confirmingRemoval = false

    var body: some View {
        if isPage {
            page
                .pageTitle(library.book(id: bookID)?.title ?? "Book")
                .toolbar { LibraryToolbar() }
        } else {
            page
        }
    }

    private var page: some View {
        Group {
            if let book = library.book(id: bookID) {
                content(book)
            } else {
                ContentUnavailableView("Book Unavailable", systemImage: "book.closed")
            }
        }
        .background(palette.background.ignoresSafeArea())
    }

    private func content(_ book: Book) -> some View {
        ScrollView {
            VStack(spacing: 28) {
                hero(book)
                actions(book)
                if let summary = book.summary, !summary.isEmpty {
                    summarySection(summary)
                }
                details(book)
                if book.highlightCount > 0 {
                    highlights(book)
                }
            }
            .padding(.horizontal, sizeClass == .compact || inInspector ? 20 : 36)
            .padding(.bottom, 40)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .confirmationDialog("Remove \u{201C}\(book.title)\u{201D}?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if !inInspector { dismiss() }
                library.delete(book)
            }
        } message: {
            Text("Chicken's copy, highlights, and bookmarks for this book will be deleted. The original file is not affected.")
        }
    }

    /// Opens the book from this page. On iPhone and iPad the reader zooms
    /// out of the cover above and the card waits underneath; on the Mac the
    /// sheet closes and the book gets its window.
    private func read(_ book: Book) {
        #if os(macOS)
        if !inInspector && !isPage { dismiss() }
        #endif
        openBook(book.id, from: CoverSource(context: coverContext, bookID: book.id))
    }

    private func hero(_ book: Book) -> some View {
        VStack(spacing: 18) {
            Button { read(book) } label: {
                BookCover(book: book, style: .hero)
                    .frame(width: inInspector ? 150 : 168, height: inInspector ? 225 : 252)
                    .coverTransitionSource(book.id)
                    .shadow(color: palette.shadow, radius: 2, x: 1, y: 1)
                    .shadow(color: palette.shadow, radius: 22, x: 4, y: 16)
                    .coverRibbon(book.progress > 0 && !book.isFinished, length: 26, width: 12)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Read \(book.title)")
            .padding(.top, isPage || inInspector ? 36 : 12)
            .padding(.bottom, 10)
            VStack(spacing: 8) {
                Text(book.title)
                    .font(.chickenDisplay(sizeClass == .compact || inInspector ? 25 : 32))
                    .tracking(-0.5)
                    .foregroundStyle(palette.text)
                    .multilineTextAlignment(.center)
                Text(book.displayAuthor)
                    .font(.chickenSerif(18, italic: true))
                    .foregroundStyle(palette.muted)
            }
            VStack(spacing: 9) {
                if book.progress > 0 && !book.isFinished {
                    ProgressLine(progress: book.progress, height: 3)
                        .frame(maxWidth: 260)
                }
                Text(progressText(book))
                    .font(.chickenMono(12, weight: .medium))
                    .foregroundStyle(book.progress > 0 && !book.isFinished ? palette.ribbon : palette.muted)
            }
        }
    }

    private func actions(_ book: Book) -> some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                PrimaryActionButton(title: book.isFinished ? "Read again" : (book.progress > 0 ? "Continue reading" : "Begin reading"), systemImage: "arrow.right") {
                    read(book)
                }
                Menu {
                    Button(book.isFinished ? "Mark as Unread" : "Mark as Finished", systemImage: book.isFinished ? "arrow.uturn.backward" : "checkmark.circle") {
                        library.setFinished(!book.isFinished, for: book)
                    }
                    Divider()
                    Button("Remove from Library…", systemImage: "trash", role: .destructive) { confirmingRemoval = true }
                } label: {
                    Label("More", systemImage: "ellipsis")
                        .labelStyle(.iconOnly)
                        .frame(width: 22, height: 22)
                }
                .menuIndicator(.hidden)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
            }
        }
    }

    private func summarySection(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "About this book")
            Text(summary)
                .font(.chickenSerif(16.5))
                .foregroundStyle(palette.text)
                .lineSpacing(6)
                .lineLimit(summaryExpanded ? nil : 6)
            if summary.count > 360 {
                Button(summaryExpanded ? "Less" : "More") {
                    withAnimation(.smooth) { summaryExpanded.toggle() }
                }
                .font(.chickenUI(13, weight: .semibold))
                .foregroundStyle(palette.muted)
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func details(_ book: Book) -> some View {
        let rows: [(String, String)] = [
            ("Format", book.format.label),
            ("Pages", book.pageCount.map { "\($0)" } ?? ""),
            ("Publisher", book.publisher ?? ""),
            ("Language", book.language.flatMap { Locale.current.localizedString(forLanguageCode: $0) } ?? book.language ?? ""),
            ("Added", book.importedAt.formatted(date: .long, time: .omitted)),
            ("Finished", book.finishedAt?.formatted(date: .long, time: .omitted) ?? ""),
        ].filter { !$0.1.isEmpty }

        return ChickenSection("Details") {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                ChickenRow(isLast: index == rows.count - 1) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.0)
                            .font(.chickenUI(13))
                            .foregroundStyle(palette.muted)
                        Spacer(minLength: 16)
                        Text(row.1)
                            .font(.chickenSerif(14))
                            .foregroundStyle(palette.text)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                }
            }
        }
    }

    private func highlights(_ book: Book) -> some View {
        ChickenSection("Highlights", count: book.highlightCount) {
            ForEach(Array(book.sortedHighlights.prefix(5).enumerated()), id: \.element.id) { index, highlight in
                ChickenRow(isLast: index == min(book.highlightCount, 5) - 1) {
                    Text({
                        var text = AttributedString(highlight.text)
                        text.backgroundColor = highlight.color.fill
                        return text
                    }())
                    .font(.chickenSerif(15))
                    .foregroundStyle(palette.text)
                    .lineSpacing(5)
                    .lineLimit(5)
                }
            }
        }
    }

    private func progressText(_ book: Book) -> String {
        if book.isFinished {
            return book.finishedAt.map { "Finished \($0.formatted(.dateTime.month(.wide).day().year()))" } ?? "Finished"
        }
        if book.progress == 0 { return "Not started" }
        var text = "\(Int((book.progress * 100).rounded()))% read"
        if let left = book.estimatedPagesLeft { text += " · \(ReadingEstimate.duration(forPages: left)) left" }
        return text
    }
}
