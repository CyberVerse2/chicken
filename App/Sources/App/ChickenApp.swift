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
        // `CHICKEN_DEBUG_OPEN=continue` or a book UUID opens a reader at launch.
        if let target = ProcessInfo.processInfo.environment["CHICKEN_DEBUG_OPEN"], !target.isEmpty {
            AppRouter.shared.pendingDestination = UUID(uuidString: target).map(ChickenLink.Destination.book) ?? .continueReading
        }
        // `CHICKEN_DEBUG_PANEL=discovery|settings` opens a library sheet;
        // `annotations|typography|search` opens a reader panel.
        switch ProcessInfo.processInfo.environment["CHICKEN_DEBUG_PANEL"] {
        case "discovery": AppRouter.shared.showingDiscovery = true
        case "settings": AppRouter.shared.showingSettings = true
        case let value? where value.hasPrefix("detail:"):
            AppRouter.shared.detailBookID = UUID(uuidString: String(value.dropFirst(7)))
        default: break
        }
        #endif
    }

    var body: some Scene {
        WindowGroup("Library", id: SceneID.library) {
            LibraryRootView()
                .environment(library)
                .environment(router)
                .modelContainer(library.container)
                .readingTheme(library.preferences.theme)
                .task { ChickenNotifications.shared.start(library: library) }
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
                // Reading today moves the nudge to tomorrow.
                ChickenNotifications.shared.refresh()
                #if os(iOS)
                // Today's minutes were just counted; the island shows them.
                ReadingActivityController.shared.refresh()
                #endif
            @unknown default: break
            }
        }

        #if os(macOS)
        // Each book opens in its own window on the Mac.
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

/// Navigation state shared by the library window, menus, intents, and deep links.
@Observable
final class AppRouter {
    static let shared = AppRouter()

    /// Book shown in the full-screen reader on iPhone and iPad.
    var presentedBookID: UUID?
    /// The cover the reader zoomed out of, and shrinks back into.
    var presentedSource: CoverSource?
    /// Book whose details sheet is showing.
    var detailBookID: UUID?
    /// Books the details sheet swipes through, and the cover it zoomed from.
    var detailSequence: [UUID] = []
    var detailSource: CoverSource?

    /// Shows details for a book, swipeable through the books around it.
    func showDetails(_ id: UUID, in sequence: [UUID] = [], from source: CoverSource? = nil) {
        detailSequence = sequence.contains(id) ? sequence : [id]
        detailSource = source
        detailBookID = id
    }
    /// Books being added to a collection; shows the collection picker.
    var collectingBooks: CollectingBooks?
    var showingImporter = false
    var showingDiscovery = false
    var showingSettings = false
    /// Set by the "Continue Reading" intent; the library opens the book once it appears.
    var pendingDestination: ChickenLink.Destination?
}

/// The books "Add to Collection" is for.
struct CollectingBooks: Identifiable {
    let id = UUID()
    let bookIDs: [UUID]
}

/// Opens a book in the platform-appropriate way: a new window on the Mac, a
/// full-screen reader on iPhone and iPad.
struct OpenBookAction {
    let handler: (UUID, CoverSource?) -> Void
    /// `source` is the cover the reader zooms out of on iPhone and iPad.
    func callAsFunction(_ id: UUID, from source: CoverSource? = nil) { handler(id, source) }
}

extension EnvironmentValues {
    @Entry var openBook = OpenBookAction { _, _ in }
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
                router.showingDiscovery = true
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
