#if os(macOS)
import AppKit
import ChickenKit
import SwiftData
import SwiftUI

/// Chicken in the menu bar: the house egg, filling up as you read toward
/// today's goal. Click it for the book you're in and the others on the go,
/// one click from their pages.
struct MenuBarReading: Scene {
    let library: LibraryStore
    let router: AppRouter
    @AppStorage(MenuBarReading.visibilityKey) private var isInserted = true

    static let visibilityKey = "Chicken.showsMenuBarItem"

    var body: some Scene {
        MenuBarExtra(isInserted: $isInserted) {
            MenuBarPanel()
                .environment(library)
                .environment(router)
                .modelContainer(library.container)
                .readingTheme(library.preferences.theme)
        } label: {
            MenuBarEgg(fraction: goalFraction)
                #if DEBUG
                .modifier(MenuBarPreviewOpener())
                #endif
        }
        .menuBarExtraStyle(.window)

        #if DEBUG
        // `CHICKEN_DEBUG_PANEL=menubar` shows the panel in a window, for review.
        Window("Menu Bar Panel", id: "menubar-preview") {
            MenuBarPanel()
                .environment(library)
                .environment(router)
                .modelContainer(library.container)
                .readingTheme(library.preferences.theme)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        #endif
    }

    private var goalFraction: Double {
        let goal = library.preferences.dailyGoalMinutes * 60
        return goal > 0 ? min(1, Double(library.readingSecondsToday) / Double(goal)) : 0
    }
}

#if DEBUG
private struct MenuBarPreviewOpener: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.task {
            if ProcessInfo.processInfo.environment["CHICKEN_DEBUG_PANEL"] == "menubar" {
                openWindow(id: "menubar-preview")
            }
        }
    }
}
#endif

/// The menu bar icon: an egg outline whose yolk rises with today's minutes,
/// solid once the goal is met. Rendered as a template image so it follows
/// the menu bar's light, dark, and tinted looks.
private struct MenuBarEgg: View {
    let fraction: Double

    var body: some View {
        Image(nsImage: Self.image(for: (fraction * 12).rounded() / 12))
            .accessibilityLabel("Chicken")
    }

    @MainActor private static var cache: [Double: NSImage] = [:]

    @MainActor
    private static func image(for fraction: Double) -> NSImage {
        if let cached = cache[fraction] { return cached }
        let egg = ZStack(alignment: .bottom) {
            EggShape().stroke(.black, lineWidth: 1.4)
            GeometryReader { geometry in
                Rectangle()
                    .frame(height: geometry.size.height * fraction)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .mask(EggShape())
        }
        .frame(width: 12, height: 15.5)
        .padding(.horizontal, 2)
        .padding(.vertical, 1)

        let renderer = ImageRenderer(content: egg)
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = true
        cache[fraction] = image
        return image
    }
}

private struct MenuBarPanel: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.palette) private var palette
    @Environment(\.openWindow) private var openWindow

    @State private var current: Book?
    @State private var others: [Book] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            today
                .padding(16)

            if let current {
                divider
                currentBook(current)
                    .padding(16)
            }

            if !others.isEmpty {
                divider
                VStack(alignment: .leading, spacing: 2) {
                    Text("Also reading")
                        .chickenEyebrow(palette)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 4)
                    ForEach(others) { book in
                        Button { open(book) } label: { row(book) }
                            .buttonStyle(MenuRowStyle())
                    }
                }
                .padding(8)
                .padding(.top, 6)
            }

            divider
            HStack {
                Button("Open Library") {
                    openWindow(id: SceneID.library)
                    NSApp.activate()
                }
                .buttonStyle(MenuRowStyle())
                Spacer()
                Button {
                    UserDefaults.standard.set(false, forKey: MenuBarReading.visibilityKey)
                } label: {
                    Image(systemName: "eye.slash")
                }
                .buttonStyle(MenuRowStyle())
                .help("Hide from the menu bar. Show it again from the Reading menu.")
            }
            .padding(8)
        }
        .frame(width: 300)
        .background(palette.background)
        .foregroundStyle(palette.text)
        .onAppear(perform: reload)
    }

    private var divider: some View {
        Rectangle().fill(palette.border).frame(height: 1)
    }

    // MARK: Today

    private var minutes: Int { library.readingSecondsToday / 60 }
    private var goal: Int { library.preferences.dailyGoalMinutes }
    private var fraction: Double { goal > 0 ? min(1, Double(minutes) / Double(goal)) : 0 }

    private var today: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(palette.surfaceAlt, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: max(fraction, minutes > 0 ? 0.03 : 0))
                    .stroke(palette.ribbon, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(minutes)")
                        .font(.chickenDisplay(22))
                        .monospacedDigit()
                    Text("of \(goal) min today")
                        .font(.chickenSerif(13, italic: true))
                        .foregroundStyle(palette.muted)
                }
                Text(fraction >= 1 ? "Goal done. Anything more is a bonus." : "\(goal - minutes) min to go")
                    .font(.chickenUI(11))
                    .foregroundStyle(palette.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Books

    private func currentBook(_ book: Book) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                BookCover(book: book, style: .mini)
                    .frame(width: 56, height: 84)
                VStack(alignment: .leading, spacing: 3) {
                    Text(book.title)
                        .font(.chickenDisplay(16))
                        .lineLimit(2)
                    Text(book.displayAuthor)
                        .font(.chickenSerif(12, italic: true))
                        .foregroundStyle(palette.muted)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    HStack(spacing: 4) {
                        Text("\(Int((book.progress * 100).rounded()))%")
                            .monospacedDigit()
                        if let chapter = book.lastChapterTitle, !chapter.isEmpty {
                            Text("·")
                            Text(chapter).lineLimit(1)
                        }
                    }
                    .font(.chickenUI(11))
                    .foregroundStyle(palette.muted)
                    ProgressLine(progress: book.progress)
                }
                .frame(height: 84, alignment: .top)
            }

            Button { open(book) } label: {
                Text("Continue Reading")
                    .font(.chickenUI(13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(palette.text, in: Capsule())
                    .foregroundStyle(palette.background)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func row(_ book: Book) -> some View {
        HStack(spacing: 10) {
            BookCover(book: book, style: .mini)
                .frame(width: 22, height: 33)
            VStack(alignment: .leading, spacing: 1) {
                Text(book.title)
                    .font(.chickenSerif(13))
                    .lineLimit(1)
                Text(book.displayAuthor)
                    .font(.chickenUI(10.5))
                    .foregroundStyle(palette.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("\(Int((book.progress * 100).rounded()))%")
                .font(.chickenUI(11).monospacedDigit())
                .foregroundStyle(palette.muted)
        }
    }

    private func open(_ book: Book) {
        openWindow(id: SceneID.reader, value: book.id)
        NSApp.activate()
    }

    private func reload() {
        library.recomputeReadingStats()
        let current = library.continueReadingBook()
        self.current = current
        others = Array(
            library.allBooks()
                .filter { $0.progress > 0 && !$0.isFinished && $0.id != current?.id }
                .sorted { $0.lastActivityAt > $1.lastActivityAt }
                .prefix(3)
        )
    }
}

/// A full-width row that lights up under the pointer, like a menu item.
private struct MenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MenuRow(configuration: configuration)
    }

    private struct MenuRow: View {
        @Environment(\.palette) private var palette
        let configuration: Configuration
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .font(.chickenUI(13))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(palette.text.opacity(configuration.isPressed ? 0.12 : (isHovering ? 0.07 : 0)))
                )
                .contentShape(Rectangle())
                .onHover { isHovering = $0 }
        }
    }
}
#endif
