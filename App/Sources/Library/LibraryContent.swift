import SwiftData
import SwiftUI

/// The scrolling body of the library: continue-reading card, yearly goal,
/// and the book grid, or search results / the empty state.
struct LibraryContent: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppRouter.self) private var router
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query private var highlights: [Highlight]

    let books: [Book]
    let visibleBooks: [Book]
    let search: String

    private var isCompact: Bool { sizeClass == .compact }
    private var isSearching: Bool { !search.trimmingCharacters(in: .whitespaces).isEmpty }

    private var continueBook: Book? {
        books.first { $0.lastOpenedAt != nil && !$0.isFinished }
    }

    private var finishedThisYear: [Book] {
        let calendar = Calendar.current
        return books.filter { book in
            guard let finished = book.finishedAt else { return false }
            return calendar.isDate(finished, equalTo: Date(), toGranularity: .year)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: isCompact ? 28 : 40) {
                if let summary = library.migrationSummary {
                    MigrationNotice(text: summary) { library.migrationSummary = nil }
                }

                if isSearching {
                    searchResults
                } else if books.isEmpty {
                    EmptyLibraryView()
                } else {
                    if let continueBook {
                        VStack(alignment: .leading, spacing: 18) {
                            SectionLabel(text: "Continue reading")
                            ContinueReadingCard(book: continueBook)
                        }
                    }
                    BooksThisYearStrip(finished: finishedThisYear, goal: library.preferences.annualBookGoal)
                    VStack(alignment: .leading, spacing: 20) {
                        SectionLabel(text: "Your library", count: books.count)
                        BookGrid(books: visibleBooks)
                    }
                    LibraryFooter(bookCount: books.count, highlightCount: highlights.count, finishedCount: books.filter(\.isFinished).count)
                }
            }
            .padding(.horizontal, isCompact ? 18 : 44)
            .padding(.top, isCompact ? 8 : 28)
            .padding(.bottom, 72)
            .frame(maxWidth: 1240, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollContentBackground(.hidden)
        .background(palette.background.ignoresSafeArea())
    }

    @ViewBuilder
    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionLabel(text: "Results", count: visibleBooks.count)
            if visibleBooks.isEmpty {
                Text("No books match \u{201C}\(search)\u{201D}.")
                    .font(.chickenUI(14))
                    .foregroundStyle(palette.muted)
            } else {
                BookGrid(books: visibleBooks)
            }
        }
    }
}

private struct MigrationNotice: View {
    @Environment(\.palette) private var palette
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(palette.muted)
            Text(text)
                .font(.chickenUI(13))
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Dismiss", systemImage: "xmark", action: onDismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(palette.faint)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

private struct LibraryFooter: View {
    @Environment(\.palette) private var palette
    let bookCount: Int
    let highlightCount: Int
    let finishedCount: Int

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                storageNote
                Spacer()
                counts
            }
            VStack(alignment: .leading, spacing: 6) {
                counts
                storageNote
            }
        }
        .font(.chickenUI(12))
        .foregroundStyle(palette.faint)
        .padding(.top, 8)
    }

    private var counts: some View {
        HStack(spacing: 18) {
            Text("\(bookCount) books")
            Text("\(highlightCount) highlights")
            Text("\(finishedCount) read")
        }
    }

    private var storageNote: some View {
        Label("Stored on this device", systemImage: "lock")
            .labelStyle(.titleAndIcon)
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
                GlassCapsule {
                    HStack(spacing: 10) {
                        if isWorking { ProgressView().controlSize(.small) }
                        Text(message)
                            .font(.chickenUI(13, weight: .medium))
                            .foregroundStyle(palette.text)
                            .monospacedDigit()
                        if !library.importErrors.isEmpty, !isWorking {
                            Button("Details") { showingErrors = true }
                                .font(.chickenUI(13, weight: .semibold))
                                .buttonStyle(.plain)
                                .foregroundStyle(palette.muted)
                        }
                    }
                }
                .padding(.bottom, 24)
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
