import ChickenKit
import SwiftUI

struct BookGrid: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let books: [Book]

    private var spacing: CGFloat { sizeClass == .compact ? 18 : 32 }

    private var columns: [GridItem] {
        sizeClass == .compact
            ? [GridItem(.adaptive(minimum: 100, maximum: 150), spacing: spacing, alignment: .top)]
            : [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: spacing, alignment: .top)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: sizeClass == .compact ? 34 : 46) {
            ForEach(books) { book in
                BookTile(book: book, ledgeOverhang: spacing / 2)
            }
        }
    }
}

private struct BookTile: View {
    @Environment(\.palette) private var palette
    @Environment(\.openBook) private var openBook
    @Environment(\.horizontalSizeClass) private var sizeClass
    let book: Book
    /// Each tile's ledge reaches halfway into the gap on either side, so a
    /// row of tiles reads as one continuous shelf.
    let ledgeOverhang: CGFloat
    @State private var hovering = false

    private var inProgress: Bool { book.progress > 0 && !book.isFinished }

    var body: some View {
        Button { openBook(book.id) } label: {
            VStack(alignment: .leading, spacing: 14) {
                BookCover(book: book, style: .tile)
                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
                    .shadow(color: palette.shadow, radius: hovering ? 10 : 3, x: 1, y: hovering ? 6 : 2)
                    .offset(y: hovering ? -6 : 0)
                    .background(alignment: .bottom) {
                        ShelfLedge()
                            .padding(.horizontal, -ledgeOverhang)
                            .alignmentGuide(.bottom) { $0[.top] }
                    }
                    .coverRibbon(inProgress)

                VStack(alignment: .leading, spacing: 3) {
                    Text(book.title)
                        .font(.chickenSerif(sizeClass == .compact ? 13.5 : 15, weight: .semibold))
                        .foregroundStyle(palette.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let author = book.author, !author.isEmpty {
                        Text(author)
                            .font(.chickenSerif(sizeClass == .compact ? 12.5 : 13.5, italic: true))
                            .foregroundStyle(palette.muted)
                            .lineLimit(1)
                    }
                    status.padding(.top, 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.25), value: hovering)
        .bookContextMenu(book)
        .accessibilityLabel("\(book.title) by \(book.displayAuthor)")
        .accessibilityValue(statusText)
    }

    private var statusText: String {
        if book.isFinished { return "Finished" }
        if book.progress > 0 { return "\(Int((book.progress * 100).rounded())) percent read" }
        return "Unread"
    }

    private var status: some View {
        HStack(spacing: 8) {
            if book.isFinished {
                Label("Read", systemImage: "checkmark")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(palette.muted)
            } else if book.progress > 0 {
                Text("\(Int((book.progress * 100).rounded()))%")
                    .fontWeight(.semibold)
                    .foregroundStyle(palette.ribbon)
            } else {
                Text(book.format.label)
            }
            if book.highlightCount > 0 {
                Label("\(book.highlightCount)", systemImage: "highlighter")
                    .labelStyle(.titleAndIcon)
            }
            Spacer(minLength: 0)
        }
        .font(.chickenMono(10.5, weight: .medium))
        .foregroundStyle(palette.faint)
    }
}

// MARK: - Context menu

extension View {
    /// Open, details, and remove: the same actions wherever a book appears.
    func bookContextMenu(_ book: Book) -> some View {
        modifier(BookContextMenu(book: book))
    }
}

private struct BookContextMenu: ViewModifier {
    @Environment(LibraryStore.self) private var library
    @Environment(AppRouter.self) private var router
    @Environment(\.openBook) private var openBook
    let book: Book
    @State private var confirmingRemoval = false

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button("Open", systemImage: "book") { openBook(book.id) }
                Button("Details", systemImage: "info.circle") { router.detailBookID = book.id }
                Divider()
                if book.progress > 0 {
                    Button(book.isFinished ? "Mark as Unread" : "Mark as Finished", systemImage: book.isFinished ? "arrow.uturn.backward" : "checkmark.circle") {
                        library.setFinished(!book.isFinished, for: book)
                    }
                } else {
                    Button("Mark as Finished", systemImage: "checkmark.circle") { library.setFinished(true, for: book) }
                }
                Divider()
                Button("Remove from Library…", systemImage: "trash", role: .destructive) { confirmingRemoval = true }
            } preview: {
                BookCover(book: book, style: .hero)
                    .frame(width: 220, height: 330)
                    .readingTheme(.paper)
            }
            .confirmationDialog("Remove \u{201C}\(book.title)\u{201D}?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
                Button("Remove", role: .destructive) { library.delete(book) }
            } message: {
                Text("Chicken's copy, highlights, and bookmarks for this book will be deleted. The original file is not affected.")
            }
    }
}
