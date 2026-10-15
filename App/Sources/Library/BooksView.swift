import ChickenKit
import SwiftData
import SwiftUI

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all
    case reading
    case unread
    case finished
    case pdf
    case epub

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .reading: return "Reading"
        case .unread: return "Unread"
        case .finished: return "Finished"
        case .pdf: return "PDFs"
        case .epub: return "EPUBs"
        }
    }

    func includes(_ book: Book) -> Bool {
        switch self {
        case .all: return true
        case .reading: return book.progress > 0 && !book.isFinished
        case .unread: return book.progress == 0
        case .finished: return book.isFinished
        case .pdf: return book.format == .pdf
        case .epub: return book.format == .epub
        }
    }
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case recent
    case added
    case title
    case author

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recent: return "Recently Read"
        case .added: return "Recently Added"
        case .title: return "Title"
        case .author: return "Author"
        }
    }

    func sorted(_ books: [Book]) -> [Book] {
        switch self {
        case .recent:
            // Books you've opened, latest first, then the ones you haven't
            // started, newest arrivals first.
            return books.sorted { lhs, rhs in
                switch (lhs.lastOpenedAt, rhs.lastOpenedAt) {
                case let (left?, right?): return left > right
                case (.some, nil): return true
                case (nil, .some): return false
                case (nil, nil): return lhs.importedAt > rhs.importedAt
                }
            }
        case .added: return books.sorted { $0.importedAt > $1.importedAt }
        case .title: return books.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .author: return books.sorted { $0.displayAuthor.localizedStandardCompare($1.displayAuthor) == .orderedAscending }
        }
    }
}

/// Every book, with quick filters and sorting.
struct BooksView: View {
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: \Book.lastActivityAt, order: .reverse) private var books: [Book]
    @AppStorage("Chicken.libraryFilter") private var filter: LibraryFilter = .all
    @AppStorage("Chicken.librarySort") private var sort: LibrarySort = .recent

    private var gutter: CGFloat { sizeClass == .compact ? 20 : 40 }
    private var visible: [Book] { sort.sorted(books.filter(filter.includes)) }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeader(title: "Library")
                    .padding(.horizontal, gutter)

                FilterChips(selection: $filter, counts: counts)

                if books.isEmpty {
                    EmptyLibraryView()
                        .padding(.horizontal, gutter)
                } else if visible.isEmpty {
                    Text(emptyMessage)
                        .font(.chickenSerif(16, italic: true))
                        .foregroundStyle(palette.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                } else {
                    BookGrid(books: visible)
                        .padding(.horizontal, gutter)
                        .animation(.smooth(duration: 0.3), value: visible.map(\.id))
                }
            }
            .padding(.top, sizeClass == .compact ? 4 : 20)
            .padding(.bottom, 80)
            .frame(maxWidth: 1240, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .bookSelectionKeys()
        .followsSelection(in: "grid", proxy: proxy)
        }
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.hard, for: .top)
        .background(palette.background.ignoresSafeArea())
        .pageTitle("Library")
        .toolbar {
            LibraryToolbar()
            ToolbarItem(placement: LibraryToolbar.placement) {
                Menu {
                    Picker("Sort By", selection: $sort) {
                        ForEach(LibrarySort.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }
        }
    }

    private var counts: [LibraryFilter: Int] {
        Dictionary(uniqueKeysWithValues: LibraryFilter.allCases.map { filter in
            (filter, books.filter(filter.includes).count)
        })
    }

    private var emptyMessage: String {
        switch filter {
        case .reading: return "Nothing in progress. Open a book to start."
        case .finished: return "No finished books yet."
        case .unread: return "You've started every book here."
        default: return "No \(filter.label) in your library."
        }
    }
}

/// Filters as a row of quiet text tabs; the selected one is underlined
/// with the ribbon.
struct FilterChips: View {
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Binding var selection: LibraryFilter
    let counts: [LibraryFilter: Int]
    @Namespace private var underline

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: sizeClass == .compact ? 20 : 26) {
                ForEach(LibraryFilter.allCases) { filter in
                    tab(filter)
                }
            }
            .padding(.bottom, 2)
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, sizeClass == .compact ? 20 : 44, for: .scrollContent)
        .scrollClipDisabled()
        .background(alignment: .bottom) {
            Rectangle().fill(palette.border).frame(height: 0.5)
        }
    }

    private func tab(_ filter: LibraryFilter) -> some View {
        let selected = filter == selection
        return Button {
            withAnimation(.smooth(duration: 0.3)) { selection = filter }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(filter.label)
                    .font(.chickenUI(14, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? palette.text : palette.muted)
                Text("\(counts[filter] ?? 0)")
                    .font(.chickenMono(11, weight: .medium))
                    .foregroundStyle(selected ? palette.ribbon : palette.faint)
            }
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) {
                if selected {
                    Capsule()
                        .fill(palette.ribbon)
                        .frame(height: 2)
                        .matchedGeometryEffect(id: "underline", in: underline)
                        .offset(y: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
