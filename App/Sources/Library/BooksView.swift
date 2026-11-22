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
        case .onDevice: return "On Device"
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

enum LibraryViewMode: String, CaseIterable, Identifiable {
    case covers
    case spines
    case list

    var id: String { rawValue }

    var label: String {
        switch self {
        case .covers: "Covers"
        case .spines: "Spines"
        case .list: "List"
        }
    }

    var systemImage: String {
        switch self {
        case .covers: "square.grid.2x2"
        case .spines: "books.vertical"
        case .list: "list.bullet"
        }
    }
}

struct BooksView: View {
    private enum CollectionDialog {
        case creating
        case renaming(BookCollection)
        case deleting(BookCollection)
    }

    @Environment(LibraryStore.self) private var library
    @Environment(AppRouter.self) private var router
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Book.lastActivityAt, order: .reverse) private var books: [Book]
    @AppStorage("Chicken.libraryFilter") private var filter: LibraryFilter = .all
    @AppStorage("Chicken.librarySort") private var sort: LibrarySort = .recent
    @AppStorage("Chicken.libraryViewMode") private var viewMode: LibraryViewMode = .covers
    @Query private var collections: [BookCollection]
    @AppStorage("Chicken.libraryCollection") private var collectionID = ""

    @State private var selection: Set<UUID>?
    @State private var dialog: CollectionDialog?
    @State private var draftName = ""
    @Namespace private var viewModeNamespace

    private var gutter: CGFloat { sizeClass == .compact ? 20 : 40 }
    private var isSelecting: Bool { selection != nil }

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

    private var canSelectDownloads: Bool { library.cloud != nil && !library.preferences.downloadsAllBooks }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center, spacing: 12) {
                    PageHeader(title: "Library")
                    Spacer(minLength: 8)
                    if !books.isEmpty {
                        viewModeSwitcher
                    }
                }
                .padding(.horizontal, gutter)

                LibraryFilterPills(
                    selection: $filter,
                    filters: filters,
                    counts: counts,
                    collections: sortedCollections,
                    collectionID: $collectionID,
                    gutter: gutter,
                    newCollection: {
                        draftName = ""
                        dialog = .creating
                    },
                    rename: { collection in
                        draftName = collection.name
                        dialog = .renaming(collection)
                    },
                    delete: { dialog = .deleting($0) }
                )

                if books.isEmpty {
                    EmptyLibraryView()
                        .padding(.horizontal, gutter)
                } else if visible.isEmpty {
                    Text(emptyMessage)
                        .font(.chickenUI(15))
                        .foregroundStyle(palette.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                } else {
                    Group {
                        switch viewMode {
                        case .covers:
                            BookGrid(books: visible, selection: selectionBinding)
                        case .spines:
                            BookSpineShelf(books: visible, selection: selectionBinding)
                        case .list:
                            BookEditorialList(books: visible, selection: selectionBinding)
                        }
                    }
                    .padding(.horizontal, gutter)
                    .animation(reduceMotion ? nil : ChickenMotion.standard, value: visible.map(\.id))
                    .animation(reduceMotion ? nil : ChickenMotion.standard, value: viewMode)
                }
            }
            .padding(.top, sizeClass == .compact ? 6 : 20)
            .padding(.bottom, 96)
            .frame(maxWidth: 1240, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.hard, for: .top)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .background(palette.background.ignoresSafeArea())
        .pageTitle("Library")
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                selectionBar
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : ChickenMotion.standard, value: isSelecting)
        .onChange(of: activeCollection == nil) { _, gone in if gone { collectionID = "" } }
        .alert("New Collection", isPresented: isCreatingBinding) {
            TextField("Name", text: $draftName)
            Button("Create") {
                if let collection = library.createCollection(named: draftName) {
                    collectionID = collection.id.uuidString
                }
                dialog = nil
            }
            Button("Cancel", role: .cancel) { dialog = nil }
        }
        .alert("Rename Collection", isPresented: isRenamingBinding) {
            TextField("Name", text: $draftName)
            Button("Rename") {
                if case .renaming(let target) = dialog {
                    library.rename(target, to: draftName)
                }
                dialog = nil
            }
            Button("Cancel", role: .cancel) { dialog = nil }
        }
        .confirmationDialog(
            deleteDialogTitle,
            isPresented: isDeletingBinding,
            titleVisibility: .visible
        ) {
            Button("Delete Collection", role: .destructive) {
                if case .deleting(let target) = dialog {
                    library.delete(target)
                }
                dialog = nil
            }
        } message: {
            Text("The books stay in your library.")
        }
        .toolbar {
            if isSelecting {
                ToolbarItem(placement: LibraryToolbar.placement) {
                    Button("Done") {
                        selection = nil
                    }
                    .fontWeight(.semibold)
                }
            } else {
                LibraryToolbar()
                if !books.isEmpty {
                    ToolbarItem(placement: LibraryToolbar.placement) {
                        Menu {
                            Button("Select Books", systemImage: "checkmark.circle") {
                                selection = []
                            }
                            Divider()
                            Picker("Sort By", selection: $sort) {
                                ForEach(LibrarySort.allCases) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.inline)
                        } label: {
                            Label("Library Options", systemImage: "ellipsis")
                        }
                    }
                }
            }
        }
    }

    private var viewModeSwitcher: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(LibraryViewMode.allCases) { mode in
                    let selected = viewMode == mode
                    Button {
                        Haptics.selection()
                        withAnimation(reduceMotion ? nil : ChickenMotion.snappy) { viewMode = mode }
                    } label: {
                        Image(systemName: mode.systemImage)
                            .font(.system(size: 13.5, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? palette.background : palette.muted)
                            .frame(width: 36, height: 32)
                            .background {
                                if selected {
                                    Capsule()
                                        .fill(palette.text)
                                        .matchedGeometryEffect(id: "viewModeIndicator", in: viewModeNamespace)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .glassEffectID(mode.rawValue, in: viewModeNamespace)
                    .accessibilityLabel(mode.label)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(3)
            .chickenGlass(in: Capsule(), interactive: true)
        }
    }

    private var selectionBinding: Binding<Set<UUID>>? {
        guard selection != nil else { return nil }
        return Binding(
            get: { selection ?? [] },
            set: { selection = $0 }
        )
    }

    private var isCreatingBinding: Binding<Bool> {
        Binding(
            get: { if case .creating = dialog { return true }; return false },
            set: { if !$0 { dialog = nil } }
        )
    }

    private var isRenamingBinding: Binding<Bool> {
        Binding(
            get: { if case .renaming = dialog { return true }; return false },
            set: { if !$0 { dialog = nil } }
        )
    }

    private var isDeletingBinding: Binding<Bool> {
        Binding(
            get: { if case .deleting = dialog { return true }; return false },
            set: { if !$0 { dialog = nil } }
        )
    }

    private var deleteDialogTitle: String {
        if case .deleting(let target) = dialog {
            return "Delete \u{201C}\(target.name)\u{201D}?"
        }
        return ""
    }

    private var counts: [LibraryFilter: Int] {
        Dictionary(uniqueKeysWithValues: filters.map { filter in
            (filter, books.filter { filter.includes($0, in: library) }.count)
        })
    }

    private var selectionBar: some View {
        let picked = selection ?? []
        return GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                SecondaryActionButton(title: "Add to Collection", systemImage: "rectangle.stack.badge.plus") {
                    router.presentSheet(.collectionPicker(CollectingBooks(bookIDs: Array(picked))))
                    selection = nil
                }
                if canSelectDownloads {
                    PrimaryActionButton(title: "Download", systemImage: "arrow.down") {
                        library.startDownload(books.filter { picked.contains($0.id) })
                        selection = nil
                    }
                }
            }
        }
        .disabled(picked.isEmpty)
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

private struct LibraryFilterPills: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: LibraryFilter
    let filters: [LibraryFilter]
    let counts: [LibraryFilter: Int]
    var collections: [BookCollection] = []
    @Binding var collectionID: String
    let gutter: CGFloat
    var newCollection: () -> Void = {}
    var rename: (BookCollection) -> Void = { _ in }
    var delete: (BookCollection) -> Void = { _ in }

    private var selectedTabID: String {
        collectionID.isEmpty ? "filter-\(selection.rawValue)" : collectionID
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(filters) { filter in
                            pill(
                                filter.label,
                                count: counts[filter] ?? 0,
                                selected: collectionID.isEmpty && filter == selection
                            ) {
                                selection = filter
                                collectionID = ""
                            }
                            .id("filter-\(filter.rawValue)")
                        }
                        if !collections.isEmpty {
                            Rectangle()
                                .fill(palette.borderStrong)
                                .frame(width: 1, height: 18)
                                .padding(.horizontal, 4)
                        }
                        ForEach(collections) { collection in
                            pill(
                                collection.name,
                                count: collection.books?.count ?? 0,
                                selected: collectionID == collection.id.uuidString
                            ) {
                                collectionID = collection.id.uuidString
                            }
                            .id(collection.id.uuidString)
                            .contextMenu {
                                Button("Rename…", systemImage: "pencil") { rename(collection) }
                                Button("Delete Collection", systemImage: "trash", role: .destructive) { delete(collection) }
                            }
                        }
                        Button(action: newCollection) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.system(size: 11.5, weight: .semibold))
                                Text("Collection")
                                    .font(.chickenUI(12.5, weight: .medium))
                            }
                            .foregroundStyle(palette.muted)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .chickenGlass(in: Capsule(), interactive: true)
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("New Collection")
                    }
                    .padding(.vertical, 4)
                }
            }
            .scrollIndicators(.never)
            .contentMargins(.horizontal, gutter, for: .scrollContent)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.03),
                        .init(color: .black, location: 0.93),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .onAppear { proxy.scrollTo(selectedTabID, anchor: .center) }
            .onChange(of: selectedTabID) { _, id in
                withAnimation(reduceMotion ? nil : ChickenMotion.standard) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private func pill(_ label: String, count: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            withAnimation(reduceMotion ? nil : ChickenMotion.snappy, action)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(label)
                    .font(.chickenUI(13.5, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
                Text("\(count)")
                    .font(.chickenMono(11, weight: .medium))
                    .opacity(selected ? 0.78 : 0.6)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .chickenGlassPill(isSelected: selected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct BookEditorialList: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.palette) private var palette
    @Environment(\.openBook) private var openBook
    @Environment(\.selectBook) private var selectBook
    @Environment(\.coverContext) private var coverContext
    @Environment(\.bookSequence) private var bookSequence
    let books: [Book]
    var selection: Binding<Set<UUID>>?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(books.enumerated()), id: \.element.id) { index, book in
                row(book)
                if index < books.count - 1 {
                    Rectangle()
                        .fill(palette.border)
                        .frame(height: 0.5)
                        .padding(.leading, 74)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(palette.surface)
                .stroke(palette.border, lineWidth: 0.5)
        )
        .chickenSwipeActionsContainer()
        .coverCollection("list", books: books.map(\.id))
    }

    private func row(_ book: Book) -> some View {
        let isSelected = selection?.wrappedValue.contains(book.id) ?? false
        let inProgress = book.progress > 0 && !book.isFinished
        return HStack(spacing: 14) {
            Button {
                if let selection {
                    if isSelected { selection.wrappedValue.remove(book.id) } else { selection.wrappedValue.insert(book.id) }
                } else {
                    selectBook(book.id, in: bookSequence, from: CoverSource(context: coverContext, bookID: book.id))
                }
            } label: {
                HStack(spacing: 14) {
                    if selection != nil {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(isSelected ? palette.ribbon : palette.faint)
                    }

                    BookCover(book: book, style: .mini)
                        .frame(width: 44, height: 66)
                        .downloadBadge(book, size: 18)
                        .shadow(color: palette.shadow, radius: 3, x: 0, y: 2)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(book.displayTitle)
                            .font(.chickenUI(15, weight: .semibold))
                            .foregroundStyle(palette.text)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        if let author = book.author, !author.isEmpty {
                            Text(author)
                                .font(.chickenUI(13))
                                .foregroundStyle(palette.muted)
                                .lineLimit(1)
                        }

                        if inProgress {
                            HStack(spacing: 6) {
                                ProgressLine(progress: book.progress, height: 2.5)
                                    .frame(maxWidth: 78)
                                Text("\(Int((book.progress * 100).rounded()))%")
                                    .font(.chickenMono(11, weight: .semibold))
                                    .foregroundStyle(palette.ribbon)
                                    .fixedSize()
                                if let left = book.estimatedPagesLeft {
                                    Text("· \(ReadingEstimate.duration(forPages: left, minutesPerPage: library.preferences.minutesPerPage)) left")
                                        .font(.chickenMono(11))
                                        .foregroundStyle(palette.faint)
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                            }
                            .padding(.top, 3)
                        } else if book.isFinished {
                            Label("Finished", systemImage: "checkmark")
                                .font(.chickenMono(11, weight: .medium))
                                .foregroundStyle(palette.muted)
                                .padding(.top, 2)
                        } else if let pages = book.pageCount, pages > 0 {
                            Text("\(pages) pages · \(book.format.label)")
                                .font(.chickenMono(11))
                                .foregroundStyle(palette.faint)
                                .padding(.top, 2)
                        }
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(TactilePressStyle(scale: 0.99))

            if selection == nil {
                Button {
                    Haptics.impact(.light)
                    openBook(book.id, from: CoverSource(context: coverContext, bookID: book.id))
                } label: {
                    Text(inProgress ? "Read" : "Open")
                        .font(.chickenUI(12, weight: .semibold))
                        .foregroundStyle(inProgress ? palette.text : palette.muted)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .chickenGlass(in: Capsule(), interactive: true)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Read \(book.displayTitle)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(book.isFinished ? "Unread" : "Finished", systemImage: book.isFinished ? "arrow.uturn.backward" : "checkmark") {
                library.setFinished(!book.isFinished, for: book)
            }
            .tint(palette.ribbon)
        }
        .bookContextMenu(book)
    }
}
