import ChickenKit
import SwiftUI

// On the Mac a click selects a book and the details panel follows the
// selection; double-click or Return opens it, Space previews it, and the
// arrow keys move through the shelf or grid. iPhone and iPad are untouched.

extension View {
    /// Arrow keys, Return, Space, and Escape for the selected book. Put on
    /// a page's scroll view; it takes keyboard focus when a book is clicked.
    func bookSelectionKeys() -> some View {
        #if os(macOS)
        modifier(BookSelectionKeys())
        #else
        self
        #endif
    }

    /// The ochre outline around a cover while its book is selected (Mac only).
    func selectionRing(for bookID: UUID, gap: CGFloat = 5) -> some View {
        #if os(macOS)
        modifier(SelectionRing(bookID: bookID, gap: gap))
        #else
        self
        #endif
    }

    /// Keeps the selected book in view when the arrow keys move past the
    /// edge of this scroll view (Mac only). Covers need `.id(book.id)`.
    func followsSelection(in context: String, proxy: ScrollViewProxy) -> some View {
        #if os(macOS)
        modifier(FollowsSelection(context: context, proxy: proxy))
        #else
        self
        #endif
    }

    /// Double-click opens the book (Mac only); a single click still selects.
    func openOnDoubleClick(_ bookID: UUID) -> some View {
        #if os(macOS)
        modifier(OpenOnDoubleClick(bookID: bookID))
        #else
        self
        #endif
    }
}

#if os(macOS)
private struct BookSelectionKeys: ViewModifier {
    @Environment(AppRouter.self) private var router
    @Environment(\.openBook) private var openBook
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onChange(of: router.selectedBookID) { _, id in
                if id != nil { focused = true }
            }
            .onMoveCommand { direction in
                switch direction {
                case .left: router.moveSelection(by: -1, vertical: false)
                case .right: router.moveSelection(by: 1, vertical: false)
                case .up: router.moveSelection(by: -1, vertical: true)
                case .down: router.moveSelection(by: 1, vertical: true)
                @unknown default: break
                }
            }
            .onKeyPress(.return) {
                guard let id = router.selectedBookID else { return .ignored }
                router.previewingBookID = nil
                openBook(id)
                return .handled
            }
            .onKeyPress(.space) {
                guard let id = router.selectedBookID else { return .ignored }
                router.previewingBookID = router.previewingBookID == nil ? id : nil
                return .handled
            }
            .onExitCommand {
                if router.previewingBookID != nil {
                    router.previewingBookID = nil
                } else {
                    router.selectedBookID = nil
                }
            }
    }
}

private struct SelectionRing: ViewModifier {
    @Environment(\.palette) private var palette
    @Environment(AppRouter.self) private var router
    let bookID: UUID
    let gap: CGFloat

    private var selected: Bool { router.selectedBookID == bookID }

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: 3 + gap, style: .continuous)
                    .strokeBorder(palette.ribbon, lineWidth: gap > 3 ? 2.5 : 2)
                    .padding(-gap)
                    .opacity(selected ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .animation(.easeOut(duration: 0.15), value: selected)
    }
}

private struct FollowsSelection: ViewModifier {
    @Environment(AppRouter.self) private var router
    let context: String
    let proxy: ScrollViewProxy

    func body(content: Content) -> some View {
        content.onChange(of: router.selectedBookID) { _, id in
            guard let id, router.selectionContext == context else { return }
            withAnimation(.smooth(duration: 0.25)) { proxy.scrollTo(id) }
        }
    }
}

private struct OpenOnDoubleClick: ViewModifier {
    @Environment(\.openBook) private var openBook
    let bookID: UUID

    func body(content: Content) -> some View {
        content.simultaneousGesture(TapGesture(count: 2).onEnded { openBook(bookID) })
    }
}

/// The right-hand panel: the selected book's details, or a quiet prompt.
struct BookInspector: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppRouter.self) private var router
    @Environment(\.palette) private var palette

    var body: some View {
        Group {
            if let id = router.selectedBookID, library.book(id: id) != nil {
                BookDetailView(bookID: id, inInspector: true)
                    .id(id)
                    .transition(.opacity)
            } else {
                VStack(spacing: 14) {
                    EggShape()
                        .stroke(palette.faint, lineWidth: 1.25)
                        .frame(width: 22, height: 28)
                    Text("Select a book to see its details.")
                        .font(.chickenSerif(14, italic: true))
                        .foregroundStyle(palette.muted)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: router.selectedBookID)
        .background(palette.background)
    }
}

/// The Space-bar preview: a large cover and what the book is about, over
/// a dimmed window. Space, Escape, or a click closes it.
struct BookPreviewOverlay: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppRouter.self) private var router
    @Environment(\.palette) private var palette

    var body: some View {
        if let id = router.previewingBookID, let book = library.book(id: id) {
            ZStack {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { router.previewingBookID = nil }
                HStack(alignment: .center, spacing: 36) {
                    BookCover(book: book, style: .hero)
                        .frame(width: 240, height: 360)
                        .shadow(color: .black.opacity(0.35), radius: 26, x: 4, y: 18)
                        .coverRibbon(book.progress > 0 && !book.isFinished, length: 34, width: 15)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(book.title)
                            .font(.chickenDisplay(30))
                            .foregroundStyle(palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(book.displayAuthor)
                            .font(.chickenSerif(17, italic: true))
                            .foregroundStyle(palette.muted)
                        if let summary = book.summary, !summary.isEmpty {
                            Text(summary)
                                .font(.chickenSerif(15))
                                .foregroundStyle(palette.text)
                                .lineSpacing(5)
                                .lineLimit(9)
                                .padding(.top, 8)
                        }
                        Text("Return to read · Space to close")
                            .font(.chickenUI(11, weight: .medium))
                            .foregroundStyle(palette.faint)
                            .padding(.top, 10)
                    }
                    .frame(width: 320, alignment: .leading)
                }
                .padding(36)
                .background(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(palette.surface)
                        .shadow(color: .black.opacity(0.25), radius: 40, y: 20)
                )
                .id(id)
                .transition(.opacity)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
    }
}
#endif
