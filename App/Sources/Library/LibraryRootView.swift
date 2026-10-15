import ChickenKit
import SwiftData
import SwiftUI

enum LibrarySort: String, CaseIterable, Identifiable {
    case recent
    case title
    case author

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recent: return "Recently Read"
        case .title: return "Title"
        case .author: return "Author"
        }
    }
}

struct LibraryRootView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppRouter.self) private var router
    @Environment(\.palette) private var palette
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    @Query(sort: \Book.lastActivityAt, order: .reverse) private var books: [Book]
    @State private var search = ""
    @AppStorage("Chicken.librarySort") private var sort: LibrarySort = .recent

    var body: some View {
        @Bindable var router = router

        NavigationStack {
            LibraryContent(books: books, visibleBooks: visibleBooks, search: search)
                .navigationTitle("Library")
                .searchable(text: $search, prompt: "Title, author, or publisher")
                .toolbar { toolbar }
        }
        .environment(\.openBook, OpenBookAction(handler: open))
        .sheet(isPresented: $router.showingDiscovery) {
            DiscoveryView()
                .readingTheme(library.preferences.theme)
        }
        #if !os(macOS)
        .sheet(isPresented: $router.showingSettings) {
            NavigationStack { SettingsView() }
                .readingTheme(library.preferences.theme)
        }
        .fullScreenCover(item: presentedBook) { item in
            ReaderLoader(bookID: item.id)
        }
        #endif
        .fileImporter(
            isPresented: $router.showingImporter,
            allowedContentTypes: BookFormat.importableContentTypes,
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { library.importFiles(urls) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            library.importFiles(files)
            return true
        }
        .overlay(alignment: .bottom) { ActivityToast() }
        .onOpenURL(perform: handle)
        .onChange(of: router.pendingDestination, initial: true) { _, destination in
            guard let destination else { return }
            router.pendingDestination = nil
            route(to: destination)
        }
        .animation(.easeInOut(duration: 0.4), value: library.preferences.theme)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Button("Import Files…", systemImage: "doc.badge.plus") { router.showingImporter = true }
                Button("Find Books in Folders…", systemImage: "folder.badge.gearshape") { router.showingDiscovery = true }
            } label: {
                Label("Add Books", systemImage: "plus")
            }

            Menu {
                Picker("Sort By", selection: $sort) {
                    ForEach(LibrarySort.allCases) { Text($0.label).tag($0) }
                }
                Picker("Theme", selection: themeBinding) {
                    ForEach(ReadingTheme.allCases) { theme in
                        Label(theme.label, systemImage: theme.systemImage).tag(theme)
                    }
                }
            } label: {
                Label("View Options", systemImage: library.preferences.theme.systemImage)
            }

            #if os(macOS)
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            #else
            Button("Settings", systemImage: "gearshape") { router.showingSettings = true }
            #endif
        }
    }

    private var themeBinding: Binding<ReadingTheme> {
        Binding(get: { library.preferences.theme }, set: { library.preferences.theme = $0 })
    }

    // MARK: Filtering

    private var visibleBooks: [Book] {
        let sorted: [Book]
        switch sort {
        case .recent:
            sorted = books
        case .title:
            sorted = books.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .author:
            sorted = books.sorted { $0.displayAuthor.localizedStandardCompare($1.displayAuthor) == .orderedAscending }
        }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sorted }
        return sorted.filter {
            $0.title.localizedStandardContains(query)
                || $0.displayAuthor.localizedStandardContains(query)
                || ($0.publisher?.localizedStandardContains(query) ?? false)
                || $0.originalFileName.localizedStandardContains(query)
        }
    }

    // MARK: Opening books

    private func open(_ id: UUID) {
        #if os(macOS)
        openWindow(id: SceneID.reader, value: id)
        #else
        router.presentedBookID = id
        #endif
    }

    #if !os(macOS)
    private var presentedBook: Binding<PresentedBook?> {
        Binding(
            get: { router.presentedBookID.map(PresentedBook.init) },
            set: { router.presentedBookID = $0?.id }
        )
    }
    #endif

    private func handle(_ url: URL) {
        if url.isFileURL {
            library.importFiles([url])
        } else if let destination = ChickenLink.destination(for: url) {
            route(to: destination)
        }
    }

    private func route(to destination: ChickenLink.Destination) {
        switch destination {
        case .book(let id):
            if library.book(id: id) != nil { open(id) }
        case .continueReading:
            if let book = library.continueReadingBook() { open(book.id) }
        }
    }
}

private struct PresentedBook: Identifiable {
    let id: UUID
}
