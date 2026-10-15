import ChickenKit
import SwiftUI

@main
struct ChickenApp: App {
    @State private var library = LibraryStore()
    @State private var router = AppRouter.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup("Library", id: SceneID.library) {
            LibraryRootView()
                .environment(library)
                .environment(router)
                .readingTheme(library.preferences.theme)
        }
        #if os(macOS)
        .defaultSize(width: 1200, height: 820)
        .commands { ChickenCommands(library: library, router: router) }
        #endif
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: library.appDidBecomeActive()
            case .background, .inactive: library.appDidResignActive()
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
            }
        }
        .defaultSize(width: 1240, height: 860)
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView()
                .environment(library)
                .readingTheme(library.preferences.theme)
                .frame(width: 540, height: 620)
        }
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
    var showingImporter = false
    var showingDiscovery = false
    var showingSettings = false
    /// Set by the "Continue Reading" intent; the library opens the book once it appears.
    var pendingDestination: ChickenLink.Destination?
}

/// Opens a book in the platform-appropriate way: a new window on the Mac, a
/// full-screen reader on iPhone and iPad.
struct OpenBookAction {
    let handler: (UUID) -> Void
    func callAsFunction(_ id: UUID) { handler(id) }
}

extension EnvironmentValues {
    @Entry var openBook = OpenBookAction { _ in }
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
