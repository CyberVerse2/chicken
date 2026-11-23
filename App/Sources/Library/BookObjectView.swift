import ChickenKit
import SwiftUI

struct BeginBookSelectionAction {
    let handler: (UUID) -> Void
    func callAsFunction(_ bookID: UUID) {
        handler(bookID)
    }
}

extension EnvironmentValues {
    @Entry var beginBookSelection: BeginBookSelectionAction? = nil
}

enum BookSurface {
    case grid
    case shelf
}

struct BookObjectView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.coverContext) private var coverContext
    @Environment(\.bookSequence) private var bookSequence
    @Environment(\.selectBook) private var selectBook
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let book: Book
    let surface: BookSurface
    var shelfHeight: CGFloat? = nil
    var showsProgressOverlay: Bool = true
    var selection: Binding<Set<UUID>>? = nil
    var matchReason: String? = nil
    var onSelect: (() -> Void)? = nil

    @State private var hovering = false

    private var isSelected: Bool { selection?.wrappedValue.contains(book.id) ?? false }
    private var inProgress: Bool { book.progress > 0 && !book.isFinished }
    private var showsCaptionBelow: Bool { library.preferences.showCoverTitles || typeSize.isAccessibilitySize }

    private var shelfWidth: CGFloat? {
        guard let shelfHeight else { return nil }
        return (shelfHeight * book.resolvedAspectRatio).rounded()
    }

    private func tapped() {
        if let selection {
            Haptics.selection()
            if isSelected { selection.wrappedValue.remove(book.id) } else { selection.wrappedValue.insert(book.id) }
            return
        }
        if let onSelect {
            onSelect()
            return
        }
        if surface == .shelf {
            Haptics.selection()
        }
        selectBook(book.id, in: bookSequence, from: CoverSource(context: coverContext, bookID: book.id))
    }

    var body: some View {
        Button(action: tapped) {
            VStack(alignment: showsCaptionBelow ? .leading : .center, spacing: 8) {
                coverBody
                if showsCaptionBelow {
                    captionFooter
                }
            }
            .frame(width: shelfWidth, alignment: showsCaptionBelow ? .leading : .center)
            .frame(maxWidth: shelfWidth == nil ? .infinity : nil, alignment: showsCaptionBelow ? .leading : .center)
            .contentShape(Rectangle())
        }
        .buttonStyle(TactilePressStyle())
        #if os(macOS)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : ChickenMotion.micro, value: hovering)
        .help("\(book.displayTitle) — \(book.displayAuthor)")
        #endif
        .bookContextMenu(book)
        .accessibilityLabel("\(book.displayTitle) by \(book.displayAuthor)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(statusText)
    }

    @ViewBuilder
    private var coverBody: some View {
        let cornerRadius = BookCoverStyle.tile.cornerRadius
        let baseCover = BookCover(book: book, style: .tile)
            .overlay(alignment: .bottom) {
                if showsProgressOverlay && inProgress {
                    progressScrim
                }
            }
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: cornerRadius * 0.45,
                bottomLeadingRadius: cornerRadius * 0.45,
                bottomTrailingRadius: cornerRadius,
                topTrailingRadius: cornerRadius,
                style: .continuous
            ))
            .overlay(alignment: .bottomTrailing) {
                if showsProgressOverlay && book.isFinished {
                    finishedBadge
                }
            }
            .overlay(alignment: .topLeading) {
                if selection == nil, let matchReason, !matchReason.isEmpty {
                    matchPill(matchReason)
                }
            }
            .overlay(alignment: .bottom) {
                #if os(macOS)
                if hovering && selection == nil && !showsCaptionBelow {
                    hoverIdentityOverlay
                        .transition(.opacity)
                }
                #endif
            }
            .downloadBadge(book, alignment: .bottomLeading)
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
            .coverTransitionSource(book.id)
            .shadow(color: palette.shadow, radius: hovering ? 14 : 6, x: 0, y: hovering ? 8 : 4)
            #if os(macOS)
            .offset(y: hovering && !reduceMotion ? -4 : 0)
            #endif
            .coverRibbon(showsProgressOverlay && inProgress)

        if let shelfHeight, let shelfWidth {
            baseCover.frame(width: shelfWidth, height: shelfHeight)
        } else {
            baseCover
                .frame(maxWidth: .infinity)
                .aspectRatio(book.resolvedAspectRatio, contentMode: .fit)
        }
    }

    private var progressScrim: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.clear, .black.opacity(0.45)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 16)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle().fill(.black.opacity(0.38))
                    Rectangle()
                        .fill(palette.ribbon)
                        .frame(width: max(4, geometry.size.width * min(max(book.progress, 0), 1)))
                }
            }
            .frame(height: 3)
        }
        .allowsHitTesting(false)
    }

    private var finishedBadge: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(palette.ribbon)
            .frame(width: 19, height: 19)
            .background(palette.surface.opacity(0.92), in: .circle)
            .overlay(Circle().stroke(palette.border, lineWidth: 0.5))
            .shadow(color: palette.shadow, radius: 2, y: 1)
            .padding(6)
            .allowsHitTesting(false)
    }

    private func matchPill(_ reason: String) -> some View {
        Text(reason)
            .font(.chickenMono(9.5, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.black.opacity(0.72), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 0.5))
            .padding(6)
            .allowsHitTesting(false)
    }

    #if os(macOS)
    private var hoverIdentityOverlay: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(book.displayTitle)
                .font(.chickenUI(11.5, weight: .semibold))
                .foregroundStyle(palette.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            HStack(spacing: 4) {
                if let author = book.author, !author.isEmpty {
                    Text(author)
                        .lineLimit(1)
                }
                if inProgress {
                    if let author = book.author, !author.isEmpty {
                        Text("·")
                    }
                    Text("\(Int((book.progress * 100).rounded()))%")
                        .foregroundStyle(palette.ribbon)
                        .fontWeight(.semibold)
                }
            }
            .font(.chickenUI(10))
            .foregroundStyle(palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.surface.opacity(0.94))
                .stroke(palette.border, lineWidth: 0.5)
        )
        .shadow(color: palette.shadow, radius: 6, y: 2)
        .padding(6)
        .allowsHitTesting(false)
    }
    #endif

    private var captionFooter: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(book.displayTitle)
                .font(.chickenUI(sizeClass == .compact ? 13 : 14, weight: .semibold))
                .foregroundStyle(palette.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let author = book.author, !author.isEmpty {
                Text(author)
                    .font(.chickenUI(sizeClass == .compact ? 11.5 : 12.5))
                    .foregroundStyle(palette.muted)
                    .lineLimit(1)
            }
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
                .padding(.top, 2)
            }
        }
    }

    private var statusText: String {
        if book.isFinished { return "Finished" }
        if book.progress > 0 { return "\(Int((book.progress * 100).rounded())) percent read" }
        return "Unread"
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
    @Environment(\.palette) private var palette
    @Environment(\.openBook) private var openBook
    @Environment(\.coverContext) private var coverContext
    @Environment(\.bookSequence) private var bookSequence
    @Environment(\.beginBookSelection) private var beginBookSelection

    let book: Book
    @State private var confirmingRemoval = false
    @State private var showingMetadataMatch = false
    @State private var showingChangeCover = false

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
                Button("Change Cover…", systemImage: "photo.on.rectangle.angled") {
                    showingChangeCover = true
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
                if let beginBookSelection {
                    Divider()
                    Button("Select Books", systemImage: "checkmark.circle") {
                        beginBookSelection(book.id)
                    }
                }
                Divider()
                Button("Remove from Library…", systemImage: "trash", role: .destructive) { confirmingRemoval = true }
            } preview: {
                let previewHeight: CGFloat = 320
                let previewWidth = (previewHeight * book.resolvedAspectRatio).rounded()
                VStack(alignment: .leading, spacing: 10) {
                    BookCover(book: book, style: .hero)
                        .frame(width: previewWidth, height: previewHeight)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(book.displayTitle)
                            .font(.chickenDisplay(16))
                            .foregroundStyle(palette.text)
                            .lineLimit(2)
                        if let author = book.author, !author.isEmpty {
                            Text(author)
                                .font(.chickenSerif(13, italic: true))
                                .foregroundStyle(palette.muted)
                                .lineLimit(1)
                        }
                        if book.progress > 0 && !book.isFinished {
                            Text("\(Int((book.progress * 100).rounded()))% read")
                                .font(.chickenMono(11, weight: .semibold))
                                .foregroundStyle(palette.ribbon)
                        } else if book.isFinished {
                            Text("Finished")
                                .font(.chickenMono(11, weight: .medium))
                                .foregroundStyle(palette.muted)
                        }
                    }
                    .frame(width: previewWidth, alignment: .leading)
                }
                .padding(14)
                .background(palette.surface)
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
            .sheet(isPresented: $showingChangeCover) {
                NavigationStack {
                    ChangeCoverSheet(book: book)
                        .environment(library)
                }
                .readingTheme(library.preferences.theme)
            }
    }
}
