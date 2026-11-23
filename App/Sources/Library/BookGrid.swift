import ChickenKit
import SwiftUI

struct BookSection: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let books: [Book]
}

struct BookGrid: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    let books: [Book]
    var selection: Binding<Set<UUID>>?
    var matchReasons: [UUID: String] = [:]
    var collectionContext: String? = "grid"

    private var spacing: CGFloat { sizeClass == .compact ? 16 : 28 }

    private var columns: [GridItem] {
        let large = typeSize.isAccessibilitySize
        return sizeClass == .compact
            ? [GridItem(.adaptive(minimum: large ? 168 : 136, maximum: large ? 240 : 184), spacing: spacing, alignment: .bottom)]
            : [GridItem(.adaptive(minimum: large ? 220 : 172, maximum: large ? 280 : 220), spacing: spacing, alignment: .bottom)]
    }

    var body: some View {
        let grid = LazyVGrid(columns: columns, alignment: .leading, spacing: sizeClass == .compact ? 26 : 36) {
            ForEach(books) { book in
                BookObjectView(
                    book: book,
                    surface: .grid,
                    selection: selection,
                    matchReason: matchReasons[book.id]
                )
                .id(book.id)
            }
        }
        if let collectionContext {
            grid.coverCollection(collectionContext, books: books.map(\.id))
        } else {
            grid
        }
    }
}

struct SectionedBookGrid: View {
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass
    let sections: [BookSection]
    var selection: Binding<Set<UUID>>?
    var matchReasons: [UUID: String] = [:]

    private var allBookIDs: [UUID] {
        sections.flatMap { $0.books.map(\.id) }
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: sizeClass == .compact ? 28 : 36) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(section.title)
                            .font(.chickenDisplay(sizeClass == .compact ? 19 : 21))
                            .tracking(-0.3)
                            .foregroundStyle(palette.text)
                            .lineLimit(1)
                        if let subtitle = section.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.chickenUI(12))
                                .foregroundStyle(palette.muted)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Text("\(section.books.count)")
                            .font(.chickenMono(11.5, weight: .medium))
                            .foregroundStyle(palette.faint)
                    }
                    BookGrid(
                        books: section.books,
                        selection: selection,
                        matchReasons: matchReasons,
                        collectionContext: nil
                    )
                }
            }
        }
        .coverCollection("grid", books: allBookIDs)
    }
}
