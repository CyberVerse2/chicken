import ChickenKit
import SwiftData
import SwiftUI

/// Home: a greeting, the book you're in the middle of, your goals, and
/// shelves of what's next.
struct HomeView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: \Book.lastActivityAt, order: .reverse) private var books: [Book]

    private var isCompact: Bool { sizeClass == .compact }
    private var gutter: CGFloat { isCompact ? 20 : 44 }

    private var continueBook: Book? {
        books.first { $0.lastOpenedAt != nil && !$0.isFinished }
    }

    private var alsoReading: [Book] {
        books.filter { $0.progress > 0 && !$0.isFinished && $0.id != continueBook?.id }
    }

    private var recentlyAdded: [Book] {
        Array(books.sorted { $0.importedAt > $1.importedAt }.prefix(16))
    }

    /// Unread books in a stable but shuffled-looking order that changes daily.
    private var upNext: [Book] {
        let seed = ReadingLog.dayKey(for: Date())
        return Array(
            books.filter { $0.progress == 0 && $0.lastOpenedAt == nil }
                .sorted { ($0.id.uuidString + seed).stableChickenHash < ($1.id.uuidString + seed).stableChickenHash }
                .prefix(16)
        )
    }

    private var finishedThisYear: [Book] {
        books.filter { $0.finishedAt.map { Calendar.current.isDate($0, equalTo: Date(), toGranularity: .year) } ?? false }
            .sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: isCompact ? 40 : 56) {
                HomeHeader()
                    .padding(.horizontal, gutter)

                if let summary = library.migrationSummary {
                    MigrationNotice(text: summary) { library.migrationSummary = nil }
                        .padding(.horizontal, gutter)
                }

                if books.isEmpty {
                    EmptyLibraryView()
                        .padding(.horizontal, gutter)
                } else {
                    Group {
                        if let continueBook {
                            ContinueReadingCard(book: continueBook, mode: .continuing)
                                .coverCollection("hero", books: [continueBook.id] + alsoReading.map(\.id))
                        } else if let first = upNext.first {
                            ContinueReadingCard(book: first, mode: .starting)
                                .coverCollection("hero", books: upNext.map(\.id))
                        }
                    }
                    .padding(.horizontal, gutter)

                    if !alsoReading.isEmpty {
                        BookShelf(title: "Also reading", books: alsoReading, gutter: gutter, showsProgress: true)
                    }

                    GoalsRow(finishedThisYear: finishedThisYear, annualGoal: library.preferences.annualBookGoal)
                        .padding(.horizontal, gutter)

                    BookShelf(title: "Recently added", books: recentlyAdded, gutter: gutter)

                    if upNext.count > 1 {
                        BookShelf(title: "Waiting on the shelf", books: Array(upNext.dropFirst(continueBook == nil ? 1 : 0)), gutter: gutter)
                    }

                }
            }
            .padding(.top, isCompact ? 8 : 28)
            .padding(.bottom, 80)
            .frame(maxWidth: 1180, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.hard, for: .top)
        .background(palette.background.ignoresSafeArea())
        .pageTitle("Home")
        .toolbar {
            #if os(iOS)
            if isCompact {
                ToolbarItem(placement: .topBarLeading) {
                    BrandLockup(size: 19)
                        .padding(.leading, 4)
                }
                .sharedBackgroundVisibility(.hidden)
            }
            #endif
            LibraryToolbar()
        }
    }
}

// MARK: - Header

private struct HomeHeader: View {
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        TimelineView(.everyMinute) { context in
            Text(Self.greeting(for: context.date))
                .font(.chickenDisplay(sizeClass == .compact ? 38 : 52))
                .tracking(sizeClass == .compact ? -0.8 : -1.2)
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    static func greeting(for date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 4..<12: return "Good morning."
        case 12..<17: return "Good afternoon."
        case 17..<22: return "Good evening."
        default: return "Up late reading?"
        }
    }
}

// MARK: - Shelves

/// A horizontally scrolling row of covers standing on a shelf ledge that
/// runs to the screen edges.
struct BookShelf: View {
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass
    let title: String
    let books: [Book]
    let gutter: CGFloat
    var showsProgress = false

    private var coverWidth: CGFloat { sizeClass == .compact ? 108 : 132 }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.chickenDisplay(sizeClass == .compact ? 19 : 22))
                .foregroundStyle(palette.text)
                .padding(.horizontal, gutter)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: sizeClass == .compact ? 18 : 26) {
                    ForEach(books) { book in
                        ShelfItem(book: book, width: coverWidth, showsProgress: showsProgress)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, gutter, for: .scrollContent)
            .scrollClipDisabled()
            .background(alignment: .top) {
                ShelfLedge().offset(y: coverWidth * 1.5)
            }
            .coverCollection("shelf-\(title)", books: books.map(\.id))
        }
    }
}

/// The lip of a shelf: a hairline catching light over a soft shadow.
struct ShelfLedge: View {
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(palette.borderStrong).frame(height: 0.5)
            LinearGradient(colors: [palette.shadow, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 10)
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ShelfItem: View {
    @Environment(\.palette) private var palette
    @Environment(\.openBook) private var openBook
    @Environment(\.coverContext) private var coverContext
    @Environment(\.bookSequence) private var bookSequence
    @Environment(\.selectBook) private var selectBook
    let book: Book
    let width: CGFloat
    let showsProgress: Bool
    @State private var hovering = false

    private var inProgress: Bool { book.progress > 0 && !book.isFinished }

    var body: some View {
        Button { selectBook(book.id, in: bookSequence, from: CoverSource(context: coverContext, bookID: book.id)) } label: {
            VStack(alignment: .leading, spacing: 14) {
                BookCover(book: book, style: .tile)
                    .frame(width: width, height: width * 1.5)
                    .coverTransitionSource(book.id)
                    .shadow(color: palette.shadow, radius: hovering ? 10 : 3, x: 1, y: hovering ? 6 : 2)
                    .offset(y: hovering ? -6 : 0)
                    .coverRibbon(inProgress)
                VStack(alignment: .leading, spacing: 3) {
                    Text(book.title)
                        .font(.chickenSerif(13.5, weight: .semibold))
                        .foregroundStyle(palette.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(book.author ?? book.format.label)
                        .font(.chickenSerif(12.5, italic: true))
                        .foregroundStyle(palette.muted)
                        .lineLimit(1)
                    if showsProgress {
                        Text("\(Int((book.progress * 100).rounded()))% read")
                            .font(.chickenMono(10.5, weight: .medium))
                            .foregroundStyle(palette.ribbon)
                            .padding(.top, 2)
                    }
                }
            }
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.25), value: hovering)
        .bookContextMenu(book)
        .accessibilityLabel("\(book.title) by \(book.displayAuthor)")
    }
}

// MARK: - Notices and footer

struct MigrationNotice: View {
    @Environment(\.palette) private var palette
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            BrandBadge(size: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome back")
                    .font(.chickenDisplay(17))
                    .foregroundStyle(palette.text)
                Text(text)
                    .font(.chickenUI(13))
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button("Dismiss", systemImage: "xmark", action: onDismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(palette.surface)
                .stroke(palette.border, lineWidth: 0.5)
        )
    }
}

/// Floating glass status for imports and cover refreshes.
struct ActivityToast: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.palette) private var palette
    @State private var showingErrors = false

    var body: some View {
        Group {
            if let message {
                HStack(spacing: 10) {
                    if isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "checkmark.circle")
                    }
                    Text(message)
                        .font(.chickenUI(13, weight: .medium))
                        .monospacedDigit()
                    if !library.importErrors.isEmpty, !isWorking {
                        Button("Details") { showingErrors = true }
                            .font(.chickenUI(13, weight: .semibold))
                            .buttonStyle(.plain)
                            .foregroundStyle(palette.muted)
                    }
                }
                .foregroundStyle(palette.text)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: .capsule)
                .padding(.bottom, 96)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.3), value: message)
        .alert("Import notes", isPresented: $showingErrors) {
            Button("OK") { library.importErrors = [] }
        } message: {
            Text(library.importErrors.prefix(8).joined(separator: "\n"))
        }
    }

    private var isWorking: Bool {
        library.importState.isImporting || library.coverRefreshState.isRefreshing
    }

    private var message: String? {
        switch library.importState {
        case .importing(let completed, let total):
            return "Importing \(completed) of \(total)"
        case .finished(let imported, let failed):
            if failed > 0 { return "Imported \(imported) · \(failed) skipped" }
            return imported == 1 ? "Imported 1 book" : "Imported \(imported) books"
        case .idle:
            break
        }
        switch library.coverRefreshState {
        case .refreshing(let completed, let total):
            return "Refreshing covers \(completed) of \(total)"
        case .finished(let refreshed):
            return "Refreshed \(refreshed) covers"
        case .idle:
            return nil
        }
    }
}
