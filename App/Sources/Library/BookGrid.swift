import ChickenKit
import SwiftUI

struct BookGrid: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let books: [Book]

    private var columns: [GridItem] {
        sizeClass == .compact
            ? [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 18, alignment: .top)]
            : [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 32, alignment: .top)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: sizeClass == .compact ? 26 : 36) {
            ForEach(books) { book in
                BookTile(book: book)
            }
        }
    }
}

private struct BookTile: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.palette) private var palette
    @Environment(\.openBook) private var openBook
    let book: Book
    @State private var hovering = false
    @State private var confirmingRemoval = false

    var body: some View {
        Button { openBook(book.id) } label: {
            VStack(alignment: .leading, spacing: 12) {
                BookCover(book: book, style: .tile)
                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
                    .shadow(color: palette.shadow, radius: hovering ? 10 : 3, y: hovering ? 7 : 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(book.title)
                        .font(.chickenSerif(15, weight: .medium))
                        .foregroundStyle(palette.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(book.displayAuthor)
                        .font(.chickenSerif(13, italic: true))
                        .foregroundStyle(palette.muted)
                        .lineLimit(1)
                }
                status
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(y: hovering ? -3 : 0)
        .animation(.easeOut(duration: 0.2), value: hovering)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Open", systemImage: "book") { openBook(book.id) }
            Divider()
            Button("Remove from Library…", systemImage: "trash", role: .destructive) { confirmingRemoval = true }
        }
        .confirmationDialog("Remove \u{201C}\(book.title)\u{201D}?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { library.delete(book) }
        } message: {
            Text("Chicken's copy, highlights, and bookmarks for this book will be deleted. The original file is not affected.")
        }
        .accessibilityLabel("\(book.title) by \(book.displayAuthor)")
        .accessibilityValue(statusText)
    }

    private var statusText: String {
        if book.isFinished { return "Read" }
        if book.progress > 0 { return "\(Int((book.progress * 100).rounded())) percent read" }
        return "Unread"
    }

    private var status: some View {
        HStack(spacing: 10) {
            if book.isFinished {
                Label("Read", systemImage: "checkmark")
                    .font(.chickenUI(11))
                    .foregroundStyle(palette.faint)
            } else if book.progress > 0 {
                ProgressLine(progress: book.progress)
                    .frame(maxWidth: 90)
                Text("\(Int((book.progress * 100).rounded()))%")
                    .font(.chickenMono(11))
                    .foregroundStyle(palette.faint)
            } else {
                Text("Unread")
                    .font(.chickenUI(11))
                    .foregroundStyle(palette.faint)
            }
            Spacer(minLength: 0)
            if book.highlightCount > 0 {
                Label("\(book.highlightCount)", systemImage: "highlighter")
                    .font(.chickenMono(11))
                    .foregroundStyle(palette.faint)
            }
        }
    }
}
