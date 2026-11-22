import ChickenKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum AppTab: Hashable {
    case home
    case library
    case notebook
    case search
    case yourReading
    case book(UUID)
}

struct LibraryRootView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppRouter.self) private var router
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    @Query(sort: \Book.lastActivityAt, order: .reverse) private var books: [Book]
    @Query private var highlights: [Highlight]

    @State private var tab: AppTab = LibraryRootView.initialTab
    #if os(iOS)
    @State private var pendingReaderFromDossier: ReaderPresentation?
    #endif
    @AppStorage("Chicken.libraryFilter") private var libraryFilter: LibraryFilter = .all
    @AppStorage("Chicken.librarySort") private var librarySort: LibrarySort = .recent
    @AppStorage("Chicken.libraryCollection") private var libraryCollection = ""
    @Namespace private var coverNamespace

    private var reading: [Book] {
        Array(books.lazy.filter { $0.progress > 0 && !$0.isFinished }.prefix(8))
    }

    private static var initialTab: AppTab {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["CHICKEN_DEBUG_TAB"] {
        case "library": return .library
        case "notebook": return .notebook
        case "search": return .search
        case "reading": return .yourReading
        default: return .home
        }
        #else
        return .home
        #endif
    }

    var body: some View {
        @Bindable var router = router

        navigation
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .onChange(of: reading.map(\.id)) { _, ids in
                if case .book(let id) = tab, !ids.contains(id) { tab = .home }
            }
            .tint(palette.text)
            .environment(\.openBook, OpenBookAction(handler: open))
            .environment(\.selectBook, SelectBookAction(handler: select))
            .environment(\.coverNamespace, coverNamespace)
            .environment(\.collectBooks, CollectBooksAction { ids in
                router.presentSheet(.collectionPicker(CollectingBooks(bookIDs: ids)))
            })
            .sheet(item: $router.activeSheet, onDismiss: router.flushQueuedSheet) { sheet in
                sheetContent(for: sheet)
            }
            .sheet(item: $router.presentedDetails, onDismiss: flushPendingReader) { presentation in
                BookDossierView(bookID: presentation.id)
                    .environment(\.openBook, OpenBookAction(handler: openFromDossier))
                    .readingTheme(library.preferences.theme)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            #if os(iOS)
            .fullScreenCover(item: $router.presentedReader) { presentation in
                ReaderLoader(bookID: presentation.id)
                    .zoomTransition(from: presentation.source, in: coverNamespace)
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
            .onChange(of: router.pendingLibraryPlace, initial: true) {
                guard let place = router.pendingLibraryPlace else { return }
                router.pendingLibraryPlace = nil
                showLibrary(place)
            }
            .onOpenURL(perform: handle)
            .spotlightIndexing(library: library, bookCount: books.count, highlightCount: highlights.count) { target in
                switch target {
                case .book(let id):
                    route(to: .book(id))
                case .highlight(let id):
                    route(to: .highlight(id))
                }
            }
            .onChange(of: router.pendingDestination, initial: true) {
                guard let destination = router.pendingDestination else { return }
                router.pendingDestination = nil
                route(to: destination)
            }
    }

    @ViewBuilder
    private func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .discovery:
            DiscoveryView()
                .readingTheme(library.preferences.theme)
        case .settings:
            NavigationStack { SettingsView() }
                .readingTheme(library.preferences.theme)
        case .collectionPicker(let request):
            CollectionPicker(bookIDs: request.bookIDs)
                .environment(library)
                .readingTheme(library.preferences.theme)
        case .quoteCard(let request):
            QuoteCardSheet(request: request)
                .readingTheme(library.preferences.theme)
        }
    }

    @ViewBuilder
    private var navigation: some View {
        #if os(macOS)
        NavigationSplitView {
            MacSidebar(selection: $tab, reading: reading)
                .navigationSplitViewColumnWidth(min: 200, ideal: 236, max: 320)
        } detail: {
            Group {
                switch tab {
                case .home: NavigationStack { HomeView() }
                case .library: NavigationStack { BooksView() }
                case .notebook: NavigationStack { NotebookView() }
                case .search: NavigationStack { SearchView() }
                case .yourReading: NavigationStack { YourReadingView() }
                case .book(let id): NavigationStack { BookDossierView(bookID: id, isPage: true) }.id(id)
                }
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
            if sizeClass == .regular {
                Tab("Your Reading", systemImage: "chart.bar", value: AppTab.yourReading) {
                    NavigationStack { YourReadingView() }
                }
                .defaultVisibility(.hidden, for: .tabBar)
            }
            if sizeClass == .regular && !reading.isEmpty {
                TabSection("Reading") {
                    ForEach(reading) { book in
                        Tab(value: AppTab.book(book.id)) {
                            NavigationStack { BookDossierView(bookID: book.id, isPage: true) }
                        } label: {
                            Label(book.displayTitle, systemImage: "bookmark.fill")
                        }
                        .defaultVisibility(.hidden, for: .tabBar)
                    }
                }
                .defaultVisibility(.hidden, for: .tabBar)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewSidebarHeader { SidebarHeader() }
        .tabViewSidebarBottomBar { SidebarTodayMeter { tab = .yourReading } }
        .modifier(NowReadingAccessoryModifier(
            book: reading.first,
            isEnabled: sizeClass == .compact && (tab == .library || tab == .notebook || tab == .search) && router.presentedReader == nil && reading.first != nil,
            onOpen: { book in
                Haptics.impact(.light)
                open(book.id)
            }
        ))
        #endif
    }

    private func showLibrary(_ place: ChickenNotifications.Place) {
        switch place {
        case .downloadedBooks:
            libraryFilter = .onDevice
            libraryCollection = ""
            router.presentedReader = nil
            router.dismissDetails()
            tab = .library
        case .settings:
            router.presentSheet(.settings)
        }
    }

    private func select(_ id: UUID, in sequence: [UUID], from source: CoverSource?) {
        router.showDetails(id, in: sequence, from: source)
    }

    private func open(_ id: UUID, from source: CoverSource? = nil, jumpTo target: JumpTarget? = nil) {
        if let target {
            router.pendingJumps[id] = target
        }
        #if os(macOS)
        openWindow(id: SceneID.reader, value: id)
        #else
        let resolvedSource = router.presentedDetails == nil ? source : nil
        router.dismissDetails()
        router.presentedReader = ReaderPresentation(id: id, source: resolvedSource)
        #endif
    }

    private func openFromDossier(_ id: UUID, from source: CoverSource? = nil, jumpTo target: JumpTarget? = nil) {
        if let target {
            router.pendingJumps[id] = target
        }
        #if os(macOS)
        router.dismissDetails()
        openWindow(id: SceneID.reader, value: id)
        #else
        pendingReaderFromDossier = ReaderPresentation(id: id, source: nil)
        router.dismissDetails()
        #endif
    }

    private func flushPendingReader() {
        #if os(iOS)
        guard let next = pendingReaderFromDossier else { return }
        pendingReaderFromDossier = nil
        router.presentedReader = next
        #endif
    }

    private var importerContentTypes: [UTType] {
        #if os(macOS)
        BookFormat.importableContentTypes + [.folder]
        #else
        BookFormat.importableContentTypes
        #endif
    }

    private func receive(_ urls: [URL]) {
        let folders = urls.filter(\.isFolder)
        library.importFiles(urls.filter { !$0.isFolder })
        guard !folders.isEmpty else { return }
        library.addFolders(folders)
        router.presentSheet(.discovery)
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
        case .highlight(let id):
            guard let highlight = library.highlight(id: id), let book = highlight.book else { return }
            open(book.id, jumpTo: JumpTarget(location: highlight.location, chapterIndex: highlight.chapterIndex))
        }
    }
}

private extension URL {
    var isFolder: Bool {
        let accessing = startAccessingSecurityScopedResource()
        defer { if accessing { stopAccessingSecurityScopedResource() } }
        let values = try? resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return values?.isDirectory == true && values?.isPackage != true
    }
}

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
                Button("Find Books in Folders…", systemImage: "folder.badge.gearshape") { router.presentSheet(.discovery) }
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
            Button("Settings", systemImage: "gearshape") { router.presentSheet(.settings) }
            #endif
        }
    }

    private var themeBinding: Binding<ReadingTheme> {
        Binding(get: { library.preferences.theme }, set: { library.preferences.theme = $0 })
    }

    static var placement: ToolbarItemPlacement {
        #if os(macOS)
        .automatic
        #else
        .primaryAction
        #endif
    }
}

private struct SidebarHeader: View {
    var body: some View {
        BrandLockup(size: 17)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SidebarTodayMeter: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.palette) private var palette
    var open: () -> Void = {}

    private var goalSeconds: Int { library.preferences.dailyGoalMinutes * 60 }
    private var fraction: Double {
        goalSeconds > 0 ? min(1, Double(library.readingSecondsToday) / Double(goalSeconds)) : 0
    }

    var body: some View {
        Button(action: open) { meter }
            .buttonStyle(.plain)
    }

    private var meter: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("Today").chickenEyebrow(palette)
                Spacer(minLength: 4)
                Text("\(library.readingSecondsToday / 60)")
                    .font(.chickenDisplay(15))
                    .foregroundStyle(palette.text)
                Text("of \(library.preferences.dailyGoalMinutes) min")
                    .font(.chickenUI(12))
                    .foregroundStyle(palette.muted)
            }
            .lineLimit(1)
            .fixedSize(horizontal: false, vertical: true)
            .monospacedDigit()
            ProgressLine(progress: fraction, height: 3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Read today")
        .accessibilityValue("\(library.readingSecondsToday / 60) of \(library.preferences.dailyGoalMinutes) minutes")
    }
}

#if !os(macOS)
private struct NowReadingAccessoryModifier: ViewModifier {
    let book: Book?
    let isEnabled: Bool
    let onOpen: (Book) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: isEnabled) {
                accessory
            }
        } else if isEnabled {
            content.tabViewBottomAccessory {
                accessory
            }
        } else {
            content
        }
    }

    @ViewBuilder
    private var accessory: some View {
        if let book {
            NowReadingTabBarAccessory(book: book) {
                onOpen(book)
            }
        }
    }
}

private struct NowReadingTabBarAccessory: View {
    @Environment(\.palette) private var palette
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    let book: Book
    let onOpen: () -> Void

    private var isInline: Bool { placement == .inline }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: isInline ? 8 : 11) {
                BookCover(book: book, style: .mini)
                    .frame(width: isInline ? 18 : 23, height: isInline ? 27 : 34)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .shadow(color: palette.shadow, radius: 1.5, x: 0, y: 1)

                VStack(alignment: .leading, spacing: 1) {
                    Text(book.displayTitle)
                        .font(.chickenUI(isInline ? 13 : 14, weight: .semibold))
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                    if !isInline {
                        HStack(spacing: 5) {
                            Text("\(Int((book.progress * 100).rounded()))%")
                                .font(.chickenMono(11.5, weight: .semibold))
                                .foregroundStyle(palette.ribbon)
                            if let chapter = book.lastChapterTitle, !chapter.isEmpty, chapter != book.title {
                                Text("·")
                                    .foregroundStyle(palette.faint)
                                Text(chapter)
                                    .font(.chickenUI(11.5))
                                    .foregroundStyle(palette.muted)
                                    .lineLimit(1)
                            } else if let author = book.author, !author.isEmpty {
                                Text("·")
                                    .foregroundStyle(palette.faint)
                                Text(author)
                                    .font(.chickenSerif(12, italic: true))
                                    .foregroundStyle(palette.muted)
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                Spacer(minLength: 4)

                Image(systemName: "arrow.right")
                    .font(.system(size: isInline ? 12 : 13, weight: .semibold))
                    .foregroundStyle(palette.muted)
            }
            .padding(.horizontal, isInline ? 12 : 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Continue reading \(book.displayTitle), \(Int((book.progress * 100).rounded())) percent")
    }
}
#endif
