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
    /// Books whose files are here, for reading offline. Shown only when
    /// the library syncs.
    case onDevice

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .reading: return "Reading"
        case .unread: return "Unread"
        case .finished: return "Finished"
        case .pdf: return "PDFs"
        case .epub: return "EPUBs"
        case .onDevice: return "On This Device"
        }
    }

    func includes(_ book: Book, in library: LibraryStore) -> Bool {
        switch self {
        case .all: return true
        case .reading: return book.progress > 0 && !book.isFinished
        case .unread: return book.progress == 0
        case .finished: return book.isFinished
        case .pdf: return book.format == .pdf
        case .epub: return book.format == .epub
        case .onDevice: return library.isOnDevice(book)
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
    @Environment(LibraryStore.self) private var library
    @Environment(AppRouter.self) private var router
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: \Book.lastActivityAt, order: .reverse) private var books: [Book]
    @AppStorage("Chicken.libraryFilter") private var filter: LibraryFilter = .all
    @AppStorage("Chicken.librarySort") private var sort: LibrarySort = .recent
    @Query private var collections: [BookCollection]
    /// The collection being shown, if any, instead of a filter.
    @AppStorage("Chicken.libraryCollection") private var collectionID = ""

    /// Picking several books to collect or download at once.
    @State private var selecting = false
    @State private var selection: Set<UUID> = []

    // Naming, renaming, and deleting collections.
    @State private var naming = false
    @State private var renaming: BookCollection?
    @State private var deleting: BookCollection?
    @State private var name = ""

    private var gutter: CGFloat { sizeClass == .compact ? 20 : 40 }

    private var sortedCollections: [BookCollection] {
        collections.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var activeCollection: BookCollection? {
        collectionID.isEmpty ? nil : collections.first { $0.id.uuidString == collectionID }
    }

    private var visible: [Book] {
        if let activeCollection {
            let ids = Set((activeCollection.books ?? []).map(\.id))
            return sort.sorted(books.filter { ids.contains($0.id) })
        }
        return sort.sorted(books.filter { filter.includes($0, in: library) })
    }
    private var filters: [LibraryFilter] {
        LibraryFilter.allCases.filter { $0 != .onDevice || library.cloud != nil }
    }
    /// With "Download all" on, every book comes down by itself.
    private var canSelectDownloads: Bool { library.cloud != nil && !library.preferences.downloadsAllBooks }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeader(title: "Library")
                    .padding(.horizontal, gutter)

                FilterChips(
                    selection: $filter, filters: filters, counts: counts,
                    collections: sortedCollections, collectionID: $collectionID,
                    newCollection: { name = ""; naming = true },
                    rename: { collection in name = collection.name; renaming = collection },
                    delete: { deleting = $0 }
                )

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
                    BookGrid(books: visible, selection: selecting ? $selection : nil)
                        .padding(.horizontal, gutter)
                        .animation(.smooth(duration: 0.3), value: visible.map(\.id))
                }
            }
            .padding(.top, sizeClass == .compact ? 4 : 20)
            .padding(.bottom, 80)
            .frame(maxWidth: 1240, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.hard, for: .top)
        .background(palette.background.ignoresSafeArea())
        .pageTitle("Library")
        .safeAreaInset(edge: .bottom) {
            if selecting {
                selectionBar
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.25), value: selecting)
        // A collection deleted here or on another device.
        .onChange(of: activeCollection == nil) { _, gone in if gone { collectionID = "" } }
        .alert("New Collection", isPresented: $naming) {
            TextField("Name", text: $name)
            Button("Create") {
                if let collection = library.createCollection(named: name) { collectionID = collection.id.uuidString }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Collection", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $name)
            Button("Rename") { if let renaming { library.rename(renaming, to: name) } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete \u{201C}\(deleting?.name ?? "")\u{201D}?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Collection", role: .destructive) {
                if let deleting { library.delete(deleting) }
            }
        } message: {
            Text("The books stay in your library.")
        }
        .toolbar {
            if !books.isEmpty {
                ToolbarItem(placement: LibraryToolbar.placement) {
                    Button(selecting ? "Done" : "Select") {
                        if selecting { endSelecting() } else { selecting = true }
                    }
                }
            }
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
        Dictionary(uniqueKeysWithValues: filters.map { filter in
            (filter, books.filter { filter.includes($0, in: library) }.count)
        })
    }

    /// Collect the picked books, or download them when there's anything
    /// to download.
    private var selectionBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                SecondaryActionButton(title: "Add to Collection", systemImage: "rectangle.stack.badge.plus") {
                    router.collectingBooks = CollectingBooks(bookIDs: Array(selection))
                    endSelecting()
                }
                if canSelectDownloads {
                    PrimaryActionButton(title: "Download", systemImage: "arrow.down") {
                        library.startDownload(books.filter { selection.contains($0.id) })
                        endSelecting()
                    }
                }
            }
        }
        .disabled(selection.isEmpty)
    }

    private func endSelecting() {
        selecting = false
        selection = []
    }

    private var emptyMessage: String {
        if let activeCollection { return "Nothing in \(activeCollection.name) yet." }
        switch filter {
        case .reading: return "Nothing in progress. Open a book to start."
        case .finished: return "No finished books yet."
        case .unread: return "You've started every book here."
        case .onDevice: return "No books downloaded to this device."
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
    let filters: [LibraryFilter]
    let counts: [LibraryFilter: Int]
    /// Your collections follow the built-in filters; picking one sets
    /// `collectionID`, and picking a filter clears it.
    var collections: [BookCollection] = []
    @Binding var collectionID: String
    var newCollection: () -> Void = {}
    var rename: (BookCollection) -> Void = { _ in }
    var delete: (BookCollection) -> Void = { _ in }
    @Namespace private var underline

    /// The tab that's selected, kept in view as the strip scrolls.
    private var selectedTabID: String {
        collectionID.isEmpty ? "filter-\(selection.rawValue)" : collectionID
    }

    var body: some View {
        ScrollViewReader { proxy in
            strip
                .onAppear { proxy.scrollTo(selectedTabID, anchor: .center) }
                .onChange(of: selectedTabID) { _, id in
                    withAnimation(.smooth(duration: 0.3)) { proxy.scrollTo(id, anchor: .center) }
                }
        }
    }

    private var strip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: sizeClass == .compact ? 20 : 26) {
                ForEach(filters) { filter in
                    tab(filter.label, count: counts[filter] ?? 0, selected: collectionID.isEmpty && filter == selection) {
                        selection = filter
                        collectionID = ""
                    }
                    .id("filter-\(filter.rawValue)")
                }
                if !collections.isEmpty {
                    Rectangle().fill(palette.border).frame(width: 0.5, height: 16)
                }
                ForEach(collections) { collection in
                    tab(collection.name, count: collection.books?.count ?? 0, selected: collectionID == collection.id.uuidString) {
                        collectionID = collection.id.uuidString
                    }
                    .id(collection.id.uuidString)
                    .contextMenu {
                        Button("Rename…", systemImage: "pencil") { rename(collection) }
                        Button("Delete Collection", systemImage: "trash", role: .destructive) { delete(collection) }
                    }
                }
                Button(action: newCollection) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.muted)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New Collection")
            }
            .padding(.bottom, 2)
        }
        .scrollIndicators(.never)
        .contentMargins(.horizontal, sizeClass == .compact ? 20 : 44, for: .scrollContent)
        .scrollClipDisabled()
        .background(alignment: .bottom) {
            Rectangle().fill(palette.border).frame(height: 0.5)
        }
    }

    private func tab(_ label: String, count: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.smooth(duration: 0.3), action)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(label)
                    .font(.chickenUI(14, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? palette.text : palette.muted)
                    .lineLimit(1)
                Text("\(count)")
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
