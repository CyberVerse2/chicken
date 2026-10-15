import ChickenKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum AppTab: Hashable {
    case home
    case library
    case notebook
    case search
    /// A book you're reading, picked from the sidebar's Reading section.
    case book(UUID)
}

/// The app's main window: Home, Library, Notebook, and Search. With the
/// sidebar-adaptable style this is a glass tab bar on iPhone, a tab bar
/// that expands into a sidebar on iPad, and a sidebar on the Mac.
struct LibraryRootView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppRouter.self) private var router
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    @Query(sort: \Book.lastActivityAt, order: .reverse) private var books: [Book]

    @State private var tab: AppTab = LibraryRootView.initialTab
    /// Covers, the reader, and the details sheet share this so books zoom
    /// open from wherever they were tapped (iPhone and iPad).
    @Namespace private var coverNamespace

    /// Books in progress, most recent first: the sidebar's Reading section.
    private var reading: [Book] {
        Array(books.lazy.filter { $0.progress > 0 && !$0.isFinished }.prefix(8))
    }

    private static var initialTab: AppTab {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["CHICKEN_DEBUG_TAB"] {
        case "library": return .library
        case "notebook": return .notebook
        case "search": return .search
        default: return .home
        }
        #else
        return .home
        #endif
    }

    var body: some View {
        @Bindable var router = router

        navigation
            // Scale with the reader's text size, up to the point where
            // shelves and covers still lay out.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .onChange(of: reading.map(\.id)) { _, ids in
            // A finished or removed book drops out of the sidebar.
            if case .book(let id) = tab, !ids.contains(id) { tab = .home }
        }
        .tint(palette.text)
        .environment(\.openBook, OpenBookAction(handler: open))
        .environment(\.selectBook, SelectBookAction(handler: select))
        .environment(\.coverNamespace, coverNamespace)
        .sheet(isPresented: $router.showingDiscovery) {
            DiscoveryView()
                .readingTheme(library.preferences.theme)
        }
        .sheet(item: detailBook) { item in
            BookDetailPager(ids: router.detailSequence, start: item.id)
                .environment(\.openBook, OpenBookAction(handler: open))
                // Sheets don't inherit environment set on the presenter.
                .environment(\.coverNamespace, coverNamespace)
                .readingTheme(library.preferences.theme)
                .zoomTransition(from: router.detailSource, in: coverNamespace)
        }
        #if !os(macOS)
        .sheet(isPresented: $router.showingSettings) {
            NavigationStack { SettingsView() }
                .readingTheme(library.preferences.theme)
        }
        .fullScreenCover(item: presentedBook) { item in
            ReaderLoader(bookID: item.id)
                .zoomTransition(from: router.presentedSource, in: coverNamespace)
        }
        #endif
        .fileImporter(
            isPresented: $router.showingImporter,
            allowedContentTypes: importerContentTypes,
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { receive(urls) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            receive(files)
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

    /// A sidebar of places and the books you're reading on the Mac; on
    /// iPhone and iPad, a tab view that becomes a sidebar on wide screens.
    @ViewBuilder
    private var navigation: some View {
        #if os(macOS)
        NavigationSplitView {
            MacSidebar(selection: $tab, reading: reading)
                .navigationSplitViewColumnWidth(min: 200, ideal: 236, max: 320)
        } detail: {
            switch tab {
            case .home: NavigationStack { HomeView() }
            case .library: NavigationStack { BooksView() }
            case .notebook: NavigationStack { NotebookView() }
            case .search: NavigationStack { SearchView() }
            case .book(let id): NavigationStack { BookDetailView(bookID: id, isPage: true) }.id(id)
            }
        }
        #else
        TabView(selection: $tab) {
            Tab("Home", systemImage: "book.pages", value: AppTab.home) {
                NavigationStack { HomeView() }
            }
            Tab("Library", systemImage: "books.vertical", value: AppTab.library) {
                NavigationStack { BooksView() }
            }
            Tab("Notebook", systemImage: "highlighter", value: AppTab.notebook) {
                NavigationStack { NotebookView() }
            }
            Tab(value: AppTab.search, role: .search) {
                NavigationStack { SearchView() }
            }
            // Only where there's a sidebar: on iPhone these tabs would
            // crowd the tab bar into a "More" tab.
            if sizeClass == .regular && !reading.isEmpty {
                TabSection("Reading") {
                    ForEach(reading) { book in
                        Tab(value: AppTab.book(book.id)) {
                            NavigationStack { BookDetailView(bookID: book.id, isPage: true) }
                        } label: {
                            Label(book.title, systemImage: "bookmark.fill")
                        }
                        .defaultVisibility(.hidden, for: .tabBar)
                    }
                }
                .defaultVisibility(.hidden, for: .tabBar)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewSidebarHeader { SidebarHeader() }
        .tabViewSidebarBottomBar { SidebarTodayMeter() }
        #endif
    }

    // MARK: Opening books

    private func select(_ id: UUID, in sequence: [UUID], from source: CoverSource?) {
        #if os(macOS)
        open(id, from: source)
        #else
        router.showDetails(id, in: sequence, from: source)
        #endif
    }

    private func open(_ id: UUID, from source: CoverSource? = nil) {
        #if os(macOS)
        openWindow(id: SceneID.reader, value: id)
        #else
        // From the details sheet the cover is going away with the sheet, so
        // the reader uses the standard presentation instead of a zoom.
        router.presentedSource = router.detailBookID == nil ? source : nil
        router.detailBookID = nil
        router.presentedBookID = id
        #endif
    }

    private var detailBook: Binding<IdentifiedBook?> {
        Binding(
            get: { router.detailBookID.map(IdentifiedBook.init) },
            set: { router.detailBookID = $0?.id }
        )
    }

    #if !os(macOS)
    private var presentedBook: Binding<IdentifiedBook?> {
        Binding(
            get: { router.presentedBookID.map(IdentifiedBook.init) },
            set: { router.presentedBookID = $0?.id }
        )
    }
    #endif

    // MARK: Importing

    /// Folders can be picked on the Mac too, so the Downloads folder isn't
    /// greyed out; they go to Find Books rather than being imported whole.
    private var importerContentTypes: [UTType] {
        #if os(macOS)
        BookFormat.importableContentTypes + [.folder]
        #else
        BookFormat.importableContentTypes
        #endif
    }

    /// Imports files straight away. Folders (from the picker or a drop) are
    /// shared with Find Books instead, so their contents are reviewed first.
    private func receive(_ urls: [URL]) {
        let folders = urls.filter(\.isFolder)
        library.importFiles(urls.filter { !$0.isFolder })
        guard !folders.isEmpty else { return }
        library.addFolders(folders)
        router.showingDiscovery = true
    }

    private func handle(_ url: URL) {
        if url.isFileURL {
            receive([url])
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

private extension URL {
    /// A plain folder, not a package such as an .rtfd bundle.
    var isFolder: Bool {
        let accessing = startAccessingSecurityScopedResource()
        defer { if accessing { stopAccessingSecurityScopedResource() } }
        let values = try? resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return values?.isDirectory == true && values?.isPackage != true
    }
}

struct IdentifiedBook: Identifiable {
    let id: UUID
}

/// Add books, theme, and settings: the same controls on every library page.
struct LibraryToolbar: ToolbarContent {
    @Environment(LibraryStore.self) private var library
    @Environment(AppRouter.self) private var router

    var body: some ToolbarContent {
        #if os(macOS)
        ToolbarSpacer(.flexible)
        #endif
        ToolbarItemGroup(placement: Self.placement) {
            Menu {
                Button("Import Files…", systemImage: "doc.badge.plus") { router.showingImporter = true }
                Button("Find Books in Folders…", systemImage: "folder.badge.gearshape") { router.showingDiscovery = true }
            } label: {
                Label("Add Books", systemImage: "plus")
            }

            Menu {
                Picker("Theme", selection: themeBinding) {
                    ForEach(ReadingTheme.allCases) { theme in
                        Label(theme.label, systemImage: theme.systemImage).tag(theme)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Theme", systemImage: library.preferences.theme.systemImage)
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

    /// Trailing on every platform (`.primaryAction` is leading on macOS).
    static var placement: ToolbarItemPlacement {
        #if os(macOS)
        .automatic
        #else
        .primaryAction
        #endif
    }
}

/// The house lockup above the sidebar.
private struct SidebarHeader: View {
    var body: some View {
        BrandLockup(size: 17)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Today's reading against the daily goal, as a ribbon meter at the foot
/// of the sidebar.
struct SidebarTodayMeter: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.palette) private var palette

    private var goalSeconds: Int { library.preferences.dailyGoalMinutes * 60 }
    private var fraction: Double {
        goalSeconds > 0 ? min(1, Double(library.readingSecondsToday) / Double(goalSeconds)) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("Today").chickenEyebrow(palette)
                Spacer(minLength: 4)
                Text("\(library.readingSecondsToday / 60)")
                    .font(.chickenDisplay(15))
                    .foregroundStyle(palette.text)
                Text("of \(library.preferences.dailyGoalMinutes) min")
                    .font(.chickenSerif(12, italic: true))
                    .foregroundStyle(palette.muted)
            }
            .lineLimit(1)
            .fixedSize(horizontal: false, vertical: true)
            .monospacedDigit()
            ProgressLine(progress: fraction, height: 3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Read today")
        .accessibilityValue("\(library.readingSecondsToday / 60) of \(library.preferences.dailyGoalMinutes) minutes")
    }
}
