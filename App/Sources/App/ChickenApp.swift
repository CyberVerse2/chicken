import ChickenKit
import SwiftData
import SwiftUI

@main
struct ChickenApp: App {
    @State private var library = LibraryStore.shared
    @State private var router = AppRouter.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if os(macOS)
        OverlayScrollbars.install()
        #endif
        #if DEBUG
        if let themeName = ProcessInfo.processInfo.environment["CHICKEN_DEBUG_THEME"],
           let debugTheme = ReadingTheme(rawValue: themeName) {
            LibraryStore.shared.preferences.theme = debugTheme
        }
        if let target = ProcessInfo.processInfo.environment["CHICKEN_DEBUG_OPEN"], !target.isEmpty {
            if target == "markdown", let book = LibraryStore.shared.allBooks().first(where: { $0.format == .text }) {
                AppRouter.shared.pendingDestination = .book(book.id)
            } else {
                AppRouter.shared.pendingDestination = UUID(uuidString: target).map(ChickenLink.Destination.book) ?? .continueReading
            }
        }
        switch ProcessInfo.processInfo.environment["CHICKEN_DEBUG_PANEL"] {
        case "discovery": AppRouter.shared.activeSheet = .discovery
        case "settings": AppRouter.shared.activeSheet = .settings
        case let value? where value.hasPrefix("detail:"):
            if let id = UUID(uuidString: String(value.dropFirst(7))) {
                AppRouter.shared.showDetails(id)
            }
        default: break
        }
        #endif
        #if DEBUG && os(macOS)
        if !(ProcessInfo.processInfo.environment["CHICKEN_SCROLL_BENCH"] ?? "").isEmpty {
            Task { @MainActor in
                ScrollBenchmarkRunner.shared.startIfRequested()
            }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup("Library", id: SceneID.library) {
            #if DEBUG && os(macOS)
            if !(ProcessInfo.processInfo.environment["CHICKEN_SCROLL_BENCH"] ?? "").isEmpty {
                Color.clear
                    .frame(width: 10, height: 10)
                    .task { ScrollBenchmarkRunner.shared.startIfRequested() }
            } else {
                LibraryRootView()
                    .environment(library)
                    .environment(router)
                    .modelContainer(library.container)
                    .readingTheme(library.preferences.theme)
                    .task { ChickenNotifications.shared.start(library: library) }
            }
            #else
            LibraryRootView()
                .environment(library)
                .environment(router)
                .modelContainer(library.container)
                .readingTheme(library.preferences.theme)
                .task { ChickenNotifications.shared.start(library: library) }
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1200, height: 820)
        .commands { ChickenCommands(library: library, router: router) }
        #endif
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                library.appDidBecomeActive()
                ChickenNotifications.shared.refresh()
            case .background, .inactive:
                library.appDidResignActive()
                ChickenNotifications.shared.refresh()
                #if os(iOS)
                ReadingActivityController.shared.refresh()
                #endif
            @unknown default: break
            }
        }

        #if os(macOS)
        WindowGroup("Reader", id: SceneID.reader, for: UUID.self) { $bookID in
            if let bookID {
                ReaderLoader(bookID: bookID)
                    .environment(library)
                    .environment(router)
                    .modelContainer(library.container)
            }
        }
        .defaultSize(width: 1240, height: 860)
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView()
                .environment(library)
                .environment(router)
                .modelContainer(library.container)
                .readingTheme(library.preferences.theme)
                .frame(width: 540, height: 620)
        }

        MenuBarReading(library: library, router: router)
        #endif
    }
}

enum SceneID {
    static let library = "library"
    static let reader = "reader"
}

struct JumpTarget: Equatable {
    let location: String?
    let chapterIndex: Int
}

struct ReaderPresentation: Identifiable, Equatable {
    let id: UUID
    let source: CoverSource?
}

struct DetailPresentation: Identifiable, Equatable {
    let id: UUID
    let sequence: [UUID]
    let source: CoverSource?
}

enum ActiveSheet: Identifiable, Equatable {
    case discovery
    case settings
    case addPhysicalBook(scanImmediately: Bool)
    case physicalLog(UUID)
    case bookFinished(UUID)
    case collectionPicker(CollectingBooks)
    case quoteCard(QuoteCardRequest)

    var id: String {
        switch self {
        case .discovery: "discovery"
        case .settings: "settings"
        case .addPhysicalBook(let scan): "add-physical-\(scan)"
        case .physicalLog(let id): "physical-log-\(id.uuidString)"
        case .bookFinished(let id): "book-finished-\(id.uuidString)"
        case .collectionPicker(let books): "collect-\(books.id.uuidString)"
        case .quoteCard(let request): "quote-\(request.id.uuidString)"
        }
    }
}

enum LibraryScope: String, CaseIterable, Identifiable {
    case all
    case reading
    case unread
    case finished
    case collections

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All"
        case .reading: "Reading"
        case .unread: "Unread"
        case .finished: "Finished"
        case .collections: "Collections"
        }
    }

    func includes(_ book: Book) -> Bool {
        switch self {
        case .all, .collections: true
        case .reading: book.progress > 0 && !book.isFinished
        case .unread: book.progress == 0
        case .finished: book.isFinished
        }
    }
}

enum LibrarySecondaryFilter: String, CaseIterable, Identifiable {
    case none
    case quickReads
    case physical
    case epub
    case pdf
    case onDevice

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "All Formats"
        case .quickReads: "Quick Reads"
        case .physical: "Print"
        case .epub: "EPUBs"
        case .pdf: "PDFs"
        case .onDevice: "On Device"
        }
    }

    func includes(_ book: Book, in library: LibraryStore) -> Bool {
        switch self {
        case .none: true
        case .quickReads: book.isQuickRead
        case .physical: book.isPhysical
        case .epub: book.format == .epub
        case .pdf: book.format == .pdf
        case .onDevice: library.isOnDevice(book)
        }
    }
}

struct LibraryNavigationRequest: Equatable {
    var scope: LibraryScope?
    var secondaryFilter: LibrarySecondaryFilter?
    var facet: LibraryFacetFilter?
    var collectionID: String?
}

enum LibraryFacetFilter: Equatable, Hashable {
    case genre(String)
    case author(String)
    case series(String)

    var eyebrow: String {
        switch self {
        case .genre: "Genre"
        case .author: "Author"
        case .series: "Series"
        }
    }

    var value: String {
        switch self {
        case .genre(let s), .author(let s), .series(let s): s
        }
    }

    func matches(_ book: Book) -> Bool {
        switch self {
        case .genre(let name):
            return book.genres.contains { $0.localizedCaseInsensitiveCompare(name) == .orderedSame }
        case .author(let name):
            return (book.author ?? "").localizedCaseInsensitiveCompare(name) == .orderedSame
        case .series(let name):
            return (book.seriesName ?? "").localizedCaseInsensitiveCompare(name) == .orderedSame
        }
    }
}

@Observable
final class AppRouter {
    static let shared = AppRouter()

    var presentedReader: ReaderPresentation?
    var presentedDetails: DetailPresentation?
    var activeSheet: ActiveSheet?
    var queuedSheet: ActiveSheet?
    var showingImporter = false
    var pendingDestination: ChickenLink.Destination?
    var pendingLibraryPlace: ChickenNotifications.Place?
    var pendingLibraryRequest: LibraryNavigationRequest?
    var libraryFacet: LibraryFacetFilter?
    var pendingJumps: [UUID: JumpTarget] = [:]

    func openLibrary(
        scope: LibraryScope? = nil,
        secondaryFilter: LibrarySecondaryFilter? = nil,
        facet: LibraryFacetFilter? = nil,
        collectionID: String? = nil
    ) {
        pendingLibraryRequest = LibraryNavigationRequest(
            scope: scope,
            secondaryFilter: secondaryFilter,
            facet: facet,
            collectionID: collectionID
        )
    }

    func showDetails(_ id: UUID, in sequence: [UUID] = [], from source: CoverSource? = nil) {
        let resolved = sequence.contains(id) ? sequence : [id]
        presentedDetails = DetailPresentation(id: id, sequence: resolved, source: source)
    }

    func updateDetailBook(_ id: UUID) {
        guard let current = presentedDetails else { return }
        presentedDetails = DetailPresentation(id: id, sequence: current.sequence, source: current.source)
    }

    func dismissDetails() {
        presentedDetails = nil
    }

    func filterLibrary(by facet: LibraryFacetFilter) {
        libraryFacet = facet
        presentedDetails = nil
    }

    func presentSheet(_ sheet: ActiveSheet) {
        if activeSheet != nil {
            queuedSheet = sheet
            activeSheet = nil
        } else {
            activeSheet = sheet
        }
    }

    func flushQueuedSheet() {
        guard let next = queuedSheet else { return }
        queuedSheet = nil
        activeSheet = next
    }

    func consumeJumpTarget(for bookID: UUID) -> JumpTarget? {
        pendingJumps.removeValue(forKey: bookID)
    }
}

struct CollectingBooks: Identifiable, Equatable {
    let id = UUID()
    let bookIDs: [UUID]
}

struct OpenBookAction {
    let handler: (UUID, CoverSource?, JumpTarget?) -> Void
    func callAsFunction(_ id: UUID, from source: CoverSource? = nil, jumpTo target: JumpTarget? = nil) {
        handler(id, source, target)
    }
}

extension EnvironmentValues {
    @Entry var openBook = OpenBookAction { _, _, _ in }
}

#if os(macOS)
struct ChickenCommands: Commands {
    let library: LibraryStore
    let router: AppRouter
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Import Books…") {
                openWindow(id: SceneID.library)
                router.showingImporter = true
            }
            .keyboardShortcut("o")

            Button("Find Books in Folders…") {
                openWindow(id: SceneID.library)
                router.presentSheet(.discovery)
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
        }

        CommandMenu("Reading") {
            Button("Continue Reading") {
                if let book = library.continueReadingBook() {
                    openWindow(id: SceneID.reader, value: book.id)
                }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Divider()

            Picker("Theme", selection: Binding(get: { library.preferences.theme }, set: { library.preferences.theme = $0 })) {
                ForEach(ReadingTheme.allCases) { theme in
                    Text(theme.label).tag(theme)
                }
            }
        }
    }
}
#endif
