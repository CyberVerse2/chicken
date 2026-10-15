import ChickenKit
import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case home
    case library
    case notebook
    case search
}

/// The app's main window: Home, Library, Notebook, and Search. With the
/// sidebar-adaptable style this is a glass tab bar on iPhone, a tab bar
/// that expands into a sidebar on iPad, and a sidebar on the Mac.
struct LibraryRootView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppRouter.self) private var router
    @Environment(\.palette) private var palette
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    @State private var tab: AppTab = LibraryRootView.initialTab

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
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewSidebarHeader { SidebarHeader() }
        .tint(palette.text)
        .environment(\.openBook, OpenBookAction(handler: open))
        .sheet(isPresented: $router.showingDiscovery) {
            DiscoveryView()
                .readingTheme(library.preferences.theme)
        }
        .sheet(item: detailBook) { item in
            BookDetailView(bookID: item.id)
                .environment(\.openBook, OpenBookAction(handler: open))
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

    // MARK: Opening books

    private func open(_ id: UUID) {
        #if os(macOS)
        openWindow(id: SceneID.reader, value: id)
        #else
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
