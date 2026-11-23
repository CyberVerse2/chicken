import ChickenKit
import SwiftUI

struct BookGrid: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    let books: [Book]
    var selection: Binding<Set<UUID>>?

    private var spacing: CGFloat { sizeClass == .compact ? 16 : 28 }

    private var columns: [GridItem] {
        let large = typeSize.isAccessibilitySize
        return sizeClass == .compact
            ? [GridItem(.adaptive(minimum: large ? 150 : 104, maximum: large ? 220 : 156), spacing: spacing, alignment: .top)]
            : [GridItem(.adaptive(minimum: large ? 200 : 142, maximum: large ? 260 : 184), spacing: spacing, alignment: .top)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: sizeClass == .compact ? 26 : 36) {
            ForEach(books) { book in
                BookTile(book: book, selection: selection)
                    .id(book.id)
            }
        }
        .coverCollection("grid", books: books.map(\.id))
    }
}

private struct BookTile: View {
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.coverContext) private var coverContext
    @Environment(\.bookSequence) private var bookSequence
    @Environment(\.selectBook) private var selectBook
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let book: Book
    var selection: Binding<Set<UUID>>?
    @State private var hovering = false

    private var isSelected: Bool { selection?.wrappedValue.contains(book.id) ?? false }

    private func tapped() {
        guard let selection else {
            selectBook(book.id, in: bookSequence, from: CoverSource(context: coverContext, bookID: book.id))
            return
        }
        if isSelected { selection.wrappedValue.remove(book.id) } else { selection.wrappedValue.insert(book.id) }
    }

    private var inProgress: Bool { book.progress > 0 && !book.isFinished }

    var body: some View {
        Button(action: tapped) {
            VStack(alignment: .leading, spacing: 10) {
                BookCover(book: book, style: .tile)
                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
                    .coverTransitionSource(book.id)
                    .downloadBadge(book)
                    .overlay(alignment: .topTrailing) {
                        if selection != nil {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(isSelected ? palette.ribbon : palette.muted)
                                .background(palette.surface.opacity(0.92), in: .circle)
                                .padding(6)
                                .transition(.opacity)
                        }
                    }
                    .shadow(color: palette.shadow, radius: hovering ? 14 : 6, x: 0, y: hovering ? 8 : 4)
                    #if os(macOS)
                    .offset(y: hovering && !reduceMotion ? -4 : 0)
                    #endif
                    .coverRibbon(inProgress)

                if book.coverImageName == nil || book.isFinished || book.progress > 0 {
                    VStack(alignment: .leading, spacing: 2) {
                        if book.coverImageName == nil {
                            Text(book.displayTitle)
                                .font(.chickenUI(sizeClass == .compact ? 13.5 : 14.5, weight: .semibold))
                                .foregroundStyle(palette.text)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            if let author = book.author, !author.isEmpty {
                                Text(author)
                                    .font(.chickenUI(sizeClass == .compact ? 12 : 13))
                                    .foregroundStyle(palette.muted)
                                    .lineLimit(1)
                            }
                        }
                        status
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(TactilePressStyle())
        #if os(macOS)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : ChickenMotion.micro, value: hovering)
        #endif
        .bookContextMenu(book)
        .accessibilityLabel("\(book.displayTitle) by \(book.displayAuthor)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(statusText)
    }

    private var statusText: String {
        if book.isFinished { return "Finished" }
        if book.progress > 0 { return "\(Int((book.progress * 100).rounded())) percent read" }
        return "Unread"
    }

    @ViewBuilder
    private var status: some View {
        if book.isFinished {
            Label("Read", systemImage: "checkmark")
                .labelStyle(.titleAndIcon)
                .font(.chickenMono(10.5, weight: .medium))
                .foregroundStyle(palette.muted)
                .padding(.top, 2)
        } else if book.progress > 0 {
            HStack(spacing: 6) {
                ProgressLine(progress: book.progress, height: 2.5)
                Text("\(Int((book.progress * 100).rounded()))%")
                    .font(.chickenMono(10.5, weight: .semibold))
                    .foregroundStyle(palette.ribbon)
                    .fixedSize()
            }
            .padding(.top, 3)
        }
    }
}

extension View {
    func bookContextMenu(_ book: Book) -> some View {
        modifier(BookContextMenu(book: book))
    }
}

private struct BookContextMenu: ViewModifier {
    @Environment(LibraryStore.self) private var library
    @Environment(AppRouter.self) private var router
    @Environment(\.openBook) private var openBook
    @Environment(\.coverContext) private var coverContext
    @Environment(\.bookSequence) private var bookSequence
    let book: Book
    @State private var confirmingRemoval = false
    @State private var showingMetadataMatch = false

    private var source: CoverSource { CoverSource(context: coverContext, bookID: book.id) }

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button(
                    book.isPhysical ? "Log Progress" : "Open",
                    systemImage: book.isPhysical ? "book.closed" : "book"
                ) {
                    openBook(book.id, from: source)
                }
                Button("Details", systemImage: "info.circle") {
                    router.showDetails(book.id, in: bookSequence, from: source)
                }
                Button("Match Metadata…", systemImage: "text.magnifyingglass") {
                    showingMetadataMatch = true
                }
                Divider()
                if book.progress > 0 {
                    Button(book.isFinished ? "Mark as Unread" : "Mark as Finished", systemImage: book.isFinished ? "arrow.uturn.backward" : "checkmark.circle") {
                        library.setFinished(!book.isFinished, for: book)
                    }
                } else {
                    Button("Mark as Finished", systemImage: "checkmark.circle") { library.setFinished(true, for: book) }
                }
                CollectionMenuItem(book: book)
                if !book.isPhysical {
                    DownloadMenuItems(book: book)
                }
                Divider()
                Button("Remove from Library…", systemImage: "trash", role: .destructive) { confirmingRemoval = true }
            } preview: {
                BookCover(book: book, style: .hero)
                    .frame(width: 220, height: 330)
                    .environment(library)
                    .readingTheme(library.preferences.theme)
            }
            .confirmationDialog("Remove \u{201C}\(book.displayTitle)\u{201D}?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
                Button("Remove", role: .destructive) { library.delete(book) }
            } message: {
                Text("Chicken's copy, highlights, and bookmarks for this book will be deleted. The original file is not affected.")
            }
            .sheet(isPresented: $showingMetadataMatch) {
                NavigationStack {
                    BookMetadataMatchSheet(book: book)
                        .environment(library)
                }
                .readingTheme(library.preferences.theme)
            }
    }
}
