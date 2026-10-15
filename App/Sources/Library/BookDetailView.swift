import ChickenKit
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Details for a run of books, one per page: swipe sideways to the next
/// book on the shelf, as in a printed catalogue.
struct BookDetailPager: View {
    /// `.pages`: one book per screen (the Mac's sheet). `.cards`: a centered
    /// card with the books on either side peeking in (iPhone and iPad).
    enum Style { case pages, cards }

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.coverNamespace) private var coverNamespace
    @Environment(\.horizontalSizeClass) private var sizeClass
    let ids: [UUID]
    var style: Style = .pages
    @State private var current: UUID?
    /// The book being read from this card, and the cover it zoomed from.
    @State private var reading: ReaderRequest?

    private struct ReaderRequest: Identifiable {
        let id: UUID
        let source: CoverSource?
    }

    init(ids: [UUID], start: UUID, style: Style = .pages) {
        self.ids = ids.contains(start) ? ids : [start]
        self.style = style
        _current = State(initialValue: start)
    }

    var body: some View {
        Group {
            switch style {
            case .pages:
                NavigationStack {
                    pages
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close", systemImage: "xmark") { dismiss() }
                            }
                        }
                }
            case .cards:
                // No bar of its own: each card is the surface, with its
                // close button in the corner.
                cards
            }
        }
        .coverCollection("detail", books: ids)
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 640, minHeight: 600, idealHeight: 720)
        #else
        .presentationDetents([.large])
        .presentationBackground(style == .cards ? Color.clear : palette.background)
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

extension BookDetailPager {
    private var pages: some View {
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
    }

    /// Full-height cards, each filled with its book's colour, the current
    /// one centred and its neighbours showing as strips at the edges.
    private var cards: some View {
        GeometryReader { geometry in
            let compact = sizeClass == .compact
            let gap: CGFloat = compact ? 8 : 16
            let peek: CGFloat = compact ? 16 : 0
            let cardWidth = compact ? geometry.size.width - 2 * (gap + peek) : min(geometry.size.width * 0.66, 620)
            let radius: CGFloat = 34
            ScrollView(.horizontal) {
                LazyHStack(spacing: gap) {
                    ForEach(ids, id: \.self) { id in
                        BookDetailView(bookID: id, inCard: true)
                            .overlay(alignment: .topLeading) {
                                Button("Close", systemImage: "xmark") { dismiss() }
                                    .labelStyle(.iconOnly)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(palette.text)
                                    .buttonStyle(.glass)
                                    .buttonBorderShape(.circle)
                                    .controlSize(.large)
                                    .padding(16)
                            }
                            // Rounded at the top only: cards run off the bottom.
                            .clipShape(UnevenRoundedRectangle(
                                topLeadingRadius: radius, bottomLeadingRadius: 0,
                                bottomTrailingRadius: 0, topTrailingRadius: radius,
                                style: .continuous
                            ))
                            .shadow(color: .black.opacity(0.25), radius: 20, y: 6)
                            .frame(width: cardWidth)
                            .padding(.top, 8)
                    }
                }
                .scrollTargetLayout()
            }
            // A card centres when there are books on both sides; the first
            // and last stay against the edges instead of leaving a gap.
            .contentMargins(.horizontal, compact ? 12 : 24, for: .scrollContent)
            .scrollTargetBehavior(CardSnapping(cardWidth: cardWidth, gap: gap, count: ids.count))
            .scrollPosition(id: $current, anchor: .center)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            // Tapping a peeking neighbour slides it into the middle.
            .simultaneousGesture(SpatialTapGesture().onEnded { tap in
                tapNeighbour(at: tap.location.x, width: geometry.size.width, cardWidth: cardWidth, gap: gap, margin: compact ? 12 : 24)
            })
            // The cards run past the bottom of the screen.
            .ignoresSafeArea(edges: .bottom)
        }
        // The library shows through behind the cards, dimmed.
        .background(Color.black.opacity(0.4).ignoresSafeArea())
    }
}

extension BookDetailPager {
    /// Brings the previous or next book to the middle when the tap lands on
    /// its card at the edge rather than on the card in the middle.
    fileprivate func tapNeighbour(at x: CGFloat, width: CGFloat, cardWidth: CGFloat, gap: CGFloat, margin: CGFloat) {
        guard let current, let index = ids.firstIndex(of: current) else { return }
        let left: CGFloat
        if index == 0 {
            left = margin
        } else if index == ids.count - 1 {
            left = width - margin - cardWidth
        } else {
            left = (width - cardWidth) / 2
        }
        let target: Int
        if x < left - gap / 2 {
            target = index - 1
        } else if x > left + cardWidth + gap / 2 {
            target = index + 1
        } else {
            return
        }
        guard ids.indices.contains(target) else { return }
        withAnimation(.smooth(duration: 0.4)) { self.current = ids[target] }
    }
}

/// Snaps one card at a time: each card is centred in the view, clamped so
/// the first and last sit at the edges, and a flick moves at most one card.
private struct CardSnapping: ScrollTargetBehavior {
    let cardWidth: CGFloat
    let gap: CGFloat
    let count: Int

    // Offsets and sizes here exclude the content margins: offset 0 puts the
    // first card at the leading margin, and `containerSize` is the width
    // between the margins.
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let viewport = context.containerSize.width
        let unit = cardWidth + gap
        guard count > 0, unit > 0 else { return }

        func index(atOffset offset: CGFloat) -> Int {
            Int(((offset + viewport / 2 - cardWidth / 2) / unit).rounded())
        }
        let current = index(atOffset: context.originalTarget.rect.minX)
        var next = index(atOffset: target.rect.minX)
        next = min(max(next, current - 1), current + 1)
        next = min(max(next, 0), count - 1)

        let centered = CGFloat(next) * unit + cardWidth / 2 - viewport / 2
        let maxOffset = max(0, context.contentSize.width - viewport)
        target.rect.origin.x = min(max(0, centered), maxOffset)
    }
}

/// Buttons on the Mac card's colour band: a white capsule for the main
/// action, a translucent one beside it.
private struct BandButtonStyle: ButtonStyle {
    let prominent: Bool
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(prominent ? Color.black.opacity(0.85) : Color.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(prominent ? Color.white.opacity(hovering ? 0.9 : 1) : Color.white.opacity(hovering ? 0.24 : 0.16)))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
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
    /// On an iPhone or iPad card: room above the cover, inside the card's edge.
    var inCard = false
    /// The Mac's card: cover on the left, title and actions beside it.
    var wide = false
    @State private var summaryExpanded = false
    @State private var confirmingRemoval = false
    /// The Mac card's header colour, from the book's cover.
    @State private var coverHue: CoverHue?

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
                if isPage {
                    content(book)
                        .background(palette.background.ignoresSafeArea())
                } else if wide {
                    // The Mac card: colour band on top, plain surface below,
                    // and the book's actions pinned in the top-right corner.
                    content(book)
                        .background(palette.surface)
                        .overlay(alignment: .topTrailing) { moreMenu(book) }
                } else {
                    // A card takes its colour from the book's cover.
                    content(book)
                        .modifier(CoverTintModifier(book: book))
                }
            } else {
                ContentUnavailableView("Book Unavailable", systemImage: "book.closed")
                    .background(palette.background.ignoresSafeArea())
            }
        }
    }

    private func content(_ book: Book) -> some View {
        ScrollView {
            if wide {
                // The Mac card: a band of the cover's colour holding the
                // cover and actions, then the rest on a plain surface.
                VStack(spacing: 0) {
                    wideHero(book)
                        .padding(.horizontal, 64)
                        .padding(.top, 72)
                        .padding(.bottom, 40)
                        .frame(maxWidth: .infinity)
                        .background(coverHue?.band ?? palette.surfaceAlt)
                        .animation(.easeInOut(duration: 0.3), value: coverHue)
                    sections(book)
                        .padding(.horizontal, 64)
                        .padding(.top, 32)
                        .padding(.bottom, 44)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(spacing: 28) {
                    hero(book)
                    actions(book)
                    sections(book)
                }
                .padding(.horizontal, sizeClass == .compact ? 20 : 36)
                .padding(.bottom, 40)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
        .task(id: wide ? book.id : nil) {
            guard wide else { return }
            coverHue = await CoverTintModifier.hue(for: book, library: library)
        }
        .confirmationDialog("Remove \u{201C}\(book.title)\u{201D}?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if !wide { dismiss() }
                library.delete(book)
            }
        } message: {
            Text("Chicken's copy, highlights, and bookmarks for this book will be deleted. The original file is not affected.")
        }
    }

    /// Opens the book from this page. On iPhone and iPad the reader zooms
    /// out of the cover above and the card waits underneath; on the Mac the
    /// book gets its own window and the card stays put.
    private func read(_ book: Book) {
        openBook(book.id, from: CoverSource(context: coverContext, bookID: book.id))
    }

    private func hero(_ book: Book) -> some View {
        VStack(spacing: 18) {
            Button { read(book) } label: {
                BookCover(book: book, style: .hero)
                    .frame(width: 168, height: 252)
                    .coverTransitionSource(book.id)
                    .shadow(color: palette.shadow, radius: 2, x: 1, y: 1)
                    .shadow(color: palette.shadow, radius: 22, x: 4, y: 16)
                    .coverRibbon(book.progress > 0 && !book.isFinished, length: 26, width: 12)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Read \(book.title)")
            .padding(.top, isPage ? 36 : (inCard ? 76 : 12))
            .padding(.bottom, 10)
            VStack(spacing: 8) {
                Text(book.title)
                    .font(.chickenDisplay(sizeClass == .compact ? 25 : 32))
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

    @ViewBuilder
    private func sections(_ book: Book) -> some View {
        VStack(spacing: 28) {
            if let summary = book.summary, !summary.isEmpty {
                summarySection(summary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            details(book)
            if book.highlightCount > 0 {
                highlights(book)
            }
        }
    }

    /// The Mac card's header, on the cover-coloured band: the cover on the
    /// left; title and author at its top, and an inset panel with where you
    /// are and how to read at its foot, as in Books on the Mac.
    private func wideHero(_ book: Book) -> some View {
        HStack(alignment: .top, spacing: 40) {
            Button { read(book) } label: {
                BookCover(book: book, style: .hero)
                    .frame(width: 200, height: 300)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 1, y: 1)
                    .shadow(color: .black.opacity(0.35), radius: 22, x: 4, y: 16)
                    .coverRibbon(book.progress > 0 && !book.isFinished, length: 30, width: 13)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Read \(book.title)")

            VStack(alignment: .leading, spacing: 8) {
                Text(book.title)
                    .font(.chickenDisplay(32))
                    .tracking(-0.5)
                    .foregroundStyle(Self.bandText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(book.displayAuthor)
                    .font(.chickenSerif(18, italic: true))
                    .foregroundStyle(Self.bandText.opacity(0.75))
                Spacer(minLength: 24)
                readingPanel(book)
            }
            .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
        }
    }

    /// Light text on the Mac card's colour band, in every theme.
    private static let bandText = Color.hex(0xF7F1E6)

    /// The inset panel on the band answers "where was I?": the chapter
    /// you're in and what's left, then one way back in. Marking a book
    /// finished happens by reaching the end, or from the ••• menu.
    private func readingPanel(_ book: Book) -> some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(panelHeadline(book))
                    .font(.chickenSerif(17, weight: .medium))
                    .foregroundStyle(Self.bandText)
                    .lineLimit(1)
                if let detail = panelDetail(book) {
                    Text(detail)
                        .font(.chickenUI(13))
                        .foregroundStyle(Self.bandText.opacity(0.7))
                        .monospacedDigit()
                }
                if book.progress > 0 && !book.isFinished {
                    // Light on the band whatever the cover's colour; the
                    // app's ProgressLine track is a dark theme colour here.
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Self.bandText.opacity(0.2))
                            Capsule().fill(Self.bandText)
                                .frame(width: max(3, geometry.size.width * min(book.progress, 1)))
                        }
                    }
                    .frame(maxWidth: 240)
                    .frame(height: 3)
                    .padding(.top, 6)
                    .accessibilityHidden(true)
                }
            }
            Spacer(minLength: 12)
            Button { read(book) } label: {
                Text(book.isFinished ? "Read again" : (book.progress > 0 ? "Continue reading" : "Begin reading"))
                    .font(.chickenUI(14, weight: .semibold))
                    .frame(minWidth: 160)
            }
            .buttonStyle(BandButtonStyle(prominent: true))
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.1)))
    }

    /// Where you are: the chapter, or the book's state when there's none.
    private func panelHeadline(_ book: Book) -> String {
        if book.isFinished { return "Finished" }
        if book.progress == 0 { return "Not started" }
        if let chapter = book.lastChapterTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !chapter.isEmpty {
            return chapter
        }
        return "\(Int((book.progress * 100).rounded()))% read"
    }

    /// How far and how much is left, the book's length before you start,
    /// or when you finished it. Nothing when there's nothing real to say.
    private func panelDetail(_ book: Book) -> String? {
        if book.isFinished {
            return book.finishedAt.map { $0.formatted(.dateTime.month(.wide).day().year()) }
        }
        if book.progress == 0 {
            guard let pages = book.pageCount, pages > 0 else { return nil }
            return "\(pages) pages · about \(ReadingEstimate.duration(forPages: pages))"
        }
        var parts: [String] = []
        if book.lastChapterTitle?.isEmpty == false { parts.append("\(Int((book.progress * 100).rounded()))% read") }
        if let left = book.estimatedPagesLeft { parts.append("\(ReadingEstimate.duration(forPages: left)) left") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The Mac card's top-right menu: the book's other actions.
    private func moreMenu(_ book: Book) -> some View {
        Menu {
            Button("Read", systemImage: "book") { read(book) }
            Button(book.isFinished ? "Mark as Unread" : "Mark as Finished", systemImage: book.isFinished ? "arrow.uturn.backward" : "checkmark.circle") {
                library.setFinished(!book.isFinished, for: book)
            }
            #if os(macOS)
            Button("Show in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([library.fileURL(for: book)])
            }
            #endif
            Divider()
            Button("Remove from Library…", systemImage: "trash", role: .destructive) { confirmingRemoval = true }
        } label: {
            Label("More", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Self.bandText)
                .frame(width: 22, height: 22)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.extraLarge)
        .padding(18)
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
