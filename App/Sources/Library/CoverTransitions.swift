import SwiftUI

/// Where a book's cover sits on screen. On iPhone and iPad the reader and
/// the details sheet zoom out of it and shrink back into it, so the same
/// book on two shelves needs two distinct sources.
struct CoverSource: Hashable {
    let context: String
    let bookID: UUID
}

/// What tapping a book's cover does: on iPhone and iPad its details card
/// zooms open (swipeable through `sequence`); on the Mac the book opens.
struct SelectBookAction {
    let handler: (UUID, [UUID], CoverSource?) -> Void
    func callAsFunction(_ id: UUID, in sequence: [UUID], from source: CoverSource?) {
        handler(id, sequence, source)
    }
}

extension EnvironmentValues {
    @Entry var selectBook = SelectBookAction { _, _, _ in }
    /// Shared by every cover and by the reader and details presentations.
    @Entry var coverNamespace: Namespace.ID?
    /// Names the shelf, grid, or list a cover belongs to.
    @Entry var coverContext = "library"
    /// The books around this one, in order: details swipe through these.
    @Entry var bookSequence: [UUID] = []
}

extension View {
    /// Marks this view as the cover a book's reader and details zoom from.
    func coverTransitionSource(_ bookID: UUID) -> some View {
        modifier(CoverTransitionSource(bookID: bookID))
    }

    /// Names the collection the covers inside belong to, and their order.
    func coverCollection(_ context: String, books: [UUID]) -> some View {
        environment(\.coverContext, context)
            .environment(\.bookSequence, books)
    }

    /// Zooms a full-screen presentation out of `source` (iPhone and iPad).
    func zoomTransition(from source: CoverSource?, in namespace: Namespace.ID) -> some View {
        modifier(ZoomFromCover(source: source, namespace: namespace))
    }
}

private struct CoverTransitionSource: ViewModifier {
    @Environment(\.coverNamespace) private var namespace
    @Environment(\.coverContext) private var context
    let bookID: UUID

    func body(content: Content) -> some View {
        #if os(iOS)
        if let namespace {
            content.matchedTransitionSource(id: CoverSource(context: context, bookID: bookID), in: namespace) { source in
                source.clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

private struct ZoomFromCover: ViewModifier {
    let source: CoverSource?
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        #if os(iOS)
        if let source {
            content.navigationTransition(.zoom(sourceID: source, in: namespace))
        } else {
            content
        }
        #else
        content
        #endif
    }
}
