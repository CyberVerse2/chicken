import SwiftUI

@main
struct ChickenApp: App {
    @StateObject private var library = LocalLibraryStore()

    var body: some Scene {
        WindowGroup {
            ChickenRootView()
                .environmentObject(library)
                .preferredColorScheme(library.readingTheme.preferredColorScheme)
                .frame(minWidth: 960, minHeight: 640)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import Books…") {
                    NotificationCenter.default.post(name: .chickenImportRequested, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Scan for Books") {
                    NotificationCenter.default.post(name: .chickenScanRequested, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }
        }
    }
}

struct ChickenRootView: View {
    @EnvironmentObject private var library: LocalLibraryStore
    @State private var openBookID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var openBook: Book? {
        guard let id = openBookID else { return nil }
        return library.books.first(where: { $0.id == id })
    }

    var body: some View {
        ZStack {
            if let book = openBook {
                ReaderView(book: book) { openBookID = nil }
                    .transition(readerTransition)
            } else {
                LibraryView { book in openBookID = book.id }
                    .transition(libraryTransition)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.12) : .timingCurve(0.25, 1, 0.5, 1, duration: 0.26),
                   value: openBookID)
    }

    /// Reader fades in slightly enlarged (1.02 → 1.0) — feels like the page
    /// is rising into focus. Reverse on dismiss.
    private var readerTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 1.02, anchor: .center)),
            removal:   .opacity.combined(with: .scale(scale: 1.02, anchor: .center))
        )
    }

    /// Library settles back from a slight zoom-out (0.985 → 1.0) when you
    /// close a book, and pulls in slightly when you open one. Mirrored to
    /// the reader's gesture so they feel like one motion.
    private var libraryTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.985, anchor: .center)),
            removal:   .opacity.combined(with: .scale(scale: 0.985, anchor: .center))
        )
    }
}

extension Notification.Name {
    static let chickenImportRequested = Notification.Name("ChickenImportRequested")
    static let chickenScanRequested = Notification.Name("ChickenScanRequested")
}
