import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Library

struct LibraryView: View {
    @EnvironmentObject private var library: LocalLibraryStore
    @State private var search = ""
    @State private var showingImporter = false
    @State private var showingScanSheet = false
    let onOpenBook: (Book) -> Void

    private var palette: ReaderPalette { library.readingTheme.palette }

    private var sortedBooks: [Book] {
        library.books.sorted {
            ($0.lastOpenedAt ?? $0.importedAt) > ($1.lastOpenedAt ?? $1.importedAt)
        }
    }

    private var filteredBooks: [Book] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return sortedBooks }
        return sortedBooks.filter {
            $0.title.lowercased().contains(q)
                || $0.displayAuthor.lowercased().contains(q)
                || ($0.publisher?.lowercased().contains(q) ?? false)
                || $0.originalFileName.lowercased().contains(q)
        }
    }

    private var continueBook: Book? {
        sortedBooks.first { $0.lastOpenedAt != nil && $0.progress < 1 }
    }

    private var finishedCount: Int {
        library.books.filter { $0.progress >= 1 }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            LibraryHeader(
                palette: palette,
                search: $search,
                theme: $library.readingTheme,
                onScan: { library.scanWholeMacForBooks(); showingScanSheet = true },
                onImport: { showingImporter = true },
                isScanning: library.scanState.isScanning
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    if !search.isEmpty {
                        searchResults
                    } else if library.books.isEmpty {
                        emptyState
                    } else {
                        if let book = continueBook {
                            continueSection(book: book)
                        }
                        booksThisYearStrip
                        librarySection
                    }
                }
                .frame(maxWidth: 1180, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.horizontal, 48)
                .padding(.top, 40)
                .padding(.bottom, 80)
            }

            LibraryFooter(
                palette: palette,
                bookCount: library.books.count,
                highlightCount: library.highlights.count,
                finishedCount: finishedCount
            )
        }
        .background(palette.background.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.4), value: library.readingTheme)
        .sheet(isPresented: $showingScanSheet) {
            DiscoveredBooksSheet(palette: palette) { showingScanSheet = false }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.pdf, .epub, .plainText, .rtf, .data],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                library.importBooks(from: urls)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .chickenImportRequested)) { _ in
            showingImporter = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .chickenScanRequested)) { _ in
            library.scanWholeMacForBooks()
            showingScanSheet = true
        }
        .onChange(of: library.scanState) { _, state in
            if case .finished(let found) = state, found > 0 {
                showingScanSheet = true
            }
        }
    }

    // MARK: Sections

    private func continueSection(book: Book) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionLabel(palette: palette, text: "Continue reading")
            ContinueReadingCard(
                palette: palette,
                book: book,
                highlightCount: library.highlights(for: book).count,
                secondsToday: library.readingSecondsToday,
                dailyGoalMinutes: library.dailyReadingMinutesGoal,
                weekReading: library.lastSevenDays,
                onContinue: { onOpenBook(book) }
            )
        }
    }

    private var booksThisYearStrip: some View {
        BooksThisYearStrip(
            palette: palette,
            year: Calendar.current.component(.year, from: Date()),
            finishedCount: library.booksFinishedThisYear.count,
            goal: library.annualBookGoal
        )
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 8) {
                SectionLabel(palette: palette, text: "Your library")
                Text("· \(library.books.count)")
                    .font(.chickenUI(11, weight: .medium))
                    .tracking(1.5)
                    .foregroundStyle(palette.faint)
            }
            BookGrid(palette: palette, books: filteredBooks, onOpen: onOpenBook)
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 8) {
                SectionLabel(palette: palette, text: "Results")
                Text("· \(filteredBooks.count)")
                    .font(.chickenUI(11, weight: .medium))
                    .tracking(1.5)
                    .foregroundStyle(palette.faint)
            }
            if filteredBooks.isEmpty {
                Text("No books match \u{201C}\(search)\u{201D}.")
                    .font(.chickenUI(14))
                    .foregroundStyle(palette.muted)
            } else {
                BookGrid(palette: palette, books: filteredBooks, onOpen: onOpenBook)
            }
        }
    }

    private var emptyState: some View {
        EmptyLibraryPanel(
            palette: palette,
            onScan: { library.scanWholeMacForBooks(); showingScanSheet = true },
            onImport: { showingImporter = true },
            scanState: library.scanState
        )
    }
}

// MARK: - Header

private struct LibraryHeader: View {
    let palette: ReaderPalette
    @Binding var search: String
    @Binding var theme: ReadingTheme
    let onScan: () -> Void
    let onImport: () -> Void
    let isScanning: Bool

    var body: some View {
        HStack(spacing: 24) {
            Wordmark(palette: palette)

            HeaderSearchField(palette: palette, text: $search)
                .frame(maxWidth: 420)

            Spacer(minLength: 0)

            ThemeSwitch(palette: palette, theme: $theme)

            HeaderIconButton(palette: palette, system: "plus", help: "Import books") {
                onImport()
            }

            SettingsMenuButton(palette: palette, onScan: onScan, isScanning: isScanning)
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            palette.background
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(palette.border)
                        .frame(height: 0.5)
                }
        )
    }
}

// MARK: - Settings popover

private struct SettingsMenuButton: View {
    let palette: ReaderPalette
    let onScan: () -> Void
    let isScanning: Bool
    @State private var showing = false

    var body: some View {
        HeaderIconButton(palette: palette, system: "gearshape", help: "Settings") {
            showing.toggle()
        }
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            SettingsPopover(
                palette: palette,
                onScan: {
                    onScan()
                    showing = false
                },
                isScanning: isScanning
            )
                .frame(width: 320)
        }
    }
}

private struct SettingsPopover: View {
    @EnvironmentObject private var library: LocalLibraryStore
    let palette: ReaderPalette
    let onScan: () -> Void
    let isScanning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Settings")
                .font(.chickenUI(11, weight: .medium))
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(palette.muted)

            VStack(alignment: .leading, spacing: 10) {
                Text("Discovery")
                    .font(.chickenUI(13, weight: .medium))
                    .foregroundStyle(palette.text)

                Text("Scan the Mac for PDFs and EPUBs, then choose what to import into Chicken's managed local library.")
                    .font(.chickenUI(11))
                    .foregroundStyle(palette.muted)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    onScan()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isScanning ? "hourglass" : "magnifyingglass")
                            .font(.system(size: 11, weight: .medium))
                        Text(isScanning ? "Scanning…" : "Scan this Mac")
                    }
                }
                .buttonStyle(SecondaryReaderButton(palette: palette))
                .disabled(isScanning)
            }

            Divider().background(palette.border)

            VStack(alignment: .leading, spacing: 10) {
                Text("Book covers")
                    .font(.chickenUI(13, weight: .medium))
                    .foregroundStyle(palette.text)

                Text("Re-extract covers from PDFs and EPUBs. Source files that don't have a usable cover (slide decks, page spreads) fall back to the stylized cover.")
                    .font(.chickenUI(11))
                    .foregroundStyle(palette.muted)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Button {
                        library.refreshAllCovers()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: refreshIcon)
                                .font(.system(size: 11, weight: .medium))
                            Text(refreshLabel)
                        }
                    }
                    .buttonStyle(SecondaryReaderButton(palette: palette))
                    .disabled(refreshDisabled)

                    refreshStatus
                }
            }

            Divider().background(palette.border)

            VStack(alignment: .leading, spacing: 10) {
                Text("Reading goal · today")
                    .font(.chickenUI(13, weight: .medium))
                    .foregroundStyle(palette.text)

                Text("Minutes to spend reading each day. Tracks active time inside the reader.")
                    .font(.chickenUI(11))
                    .foregroundStyle(palette.muted)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        goalStepperButton(system: "minus", enabled: library.dailyReadingMinutesGoal > 5) {
                            library.dailyReadingMinutesGoal = max(5, library.dailyReadingMinutesGoal - 5)
                        }
                        goalStepperButton(system: "plus", enabled: library.dailyReadingMinutesGoal < 180) {
                            library.dailyReadingMinutesGoal = min(180, library.dailyReadingMinutesGoal + 5)
                        }
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(library.dailyReadingMinutesGoal)")
                            .font(.chickenSerif(16, weight: .medium))
                            .foregroundStyle(palette.text)
                            .monospacedDigit()
                        Text("min")
                            .font(.chickenSerif(13, italic: true))
                            .foregroundStyle(palette.muted)
                    }

                    Spacer(minLength: 0)
                }
            }

            Divider().background(palette.border)

            VStack(alignment: .leading, spacing: 10) {
                Text("Books this year")
                    .font(.chickenUI(13, weight: .medium))
                    .foregroundStyle(palette.text)

                Text("How many books to finish before year end. Separate from the daily reading goal.")
                    .font(.chickenUI(11))
                    .foregroundStyle(palette.muted)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        goalStepperButton(system: "minus", enabled: library.annualBookGoal > 1) {
                            library.annualBookGoal = max(1, library.annualBookGoal - 1)
                        }
                        goalStepperButton(system: "plus", enabled: library.annualBookGoal < 365) {
                            library.annualBookGoal = min(365, library.annualBookGoal + 1)
                        }
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(library.annualBookGoal)")
                            .font(.chickenSerif(16, weight: .medium))
                            .foregroundStyle(palette.text)
                            .monospacedDigit()
                        Text(library.annualBookGoal == 1 ? "book" : "books")
                            .font(.chickenSerif(13, italic: true))
                            .foregroundStyle(palette.muted)
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .padding(18)
        .background(palette.surface)
    }

    private func goalStepperButton(system: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 10, weight: .medium))
                .frame(width: 24, height: 24)
                .foregroundStyle(enabled ? palette.text : palette.faint)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(palette.surfaceAlt)
                        .stroke(palette.border, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var refreshIcon: String {
        switch library.coverRefreshState {
        case .finished: return "checkmark"
        default: return "arrow.clockwise"
        }
    }

    private var refreshLabel: String {
        switch library.coverRefreshState {
        case .refreshing: return "Refreshing…"
        case .finished:   return "Refreshed"
        case .idle:       return "Refresh covers"
        }
    }

    private var refreshDisabled: Bool {
        if library.coverRefreshState.isRefreshing { return true }
        if !library.books.contains(where: { $0.format == .pdf || $0.format == .epub }) {
            return true
        }
        return false
    }

    @ViewBuilder
    private var refreshStatus: some View {
        switch library.coverRefreshState {
        case .idle:
            EmptyView()
        case .refreshing(let completed, let total):
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("\(completed) of \(total)")
                    .font(.chickenMono(11))
                    .foregroundStyle(palette.faint)
            }
        case .finished(let count):
            Text("\(count) refreshed")
                .font(.chickenMono(11))
                .foregroundStyle(palette.faint)
        }
    }
}

private struct Wordmark: View {
    let palette: ReaderPalette
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image("HeaderLogo")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 26, height: 26)
                // The chicken-on-book artwork has its visual mass in the upper
                // portion and the book base sitting below. Map the icon's
                // baseline to ~78% down its frame so the chicken body lines up
                // with the cap-x band of the type, instead of the icon hanging
                // below the text's descender.
                .alignmentGuide(.firstTextBaseline) { dim in dim.height * 0.78 }

            Text("Chicken")
                .font(.chickenSerif(22, weight: .medium))
                .tracking(-0.2)
                .foregroundStyle(palette.text)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Chicken")
    }
}

private struct HeaderSearchField: View {
    let palette: ReaderPalette
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.faint)
            TextField("Search title or author", text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .font(.chickenUI(13))
                .foregroundStyle(palette.text)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.faint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.surface)
                .stroke(focused ? palette.borderStrong : palette.border, lineWidth: 0.5)
        )
    }
}

private struct ThemeSwitch: View {
    let palette: ReaderPalette
    @Binding var theme: ReadingTheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ReadingTheme.allCases) { t in
                Button { theme = t } label: {
                    Text(t.label)
                        .font(.chickenUI(11))
                        .tracking(0.3)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(theme == t ? palette.surface : .clear)
                        )
                        .foregroundStyle(theme == t ? palette.text : palette.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.surfaceAlt)
                .stroke(palette.border, lineWidth: 0.5)
        )
    }
}

private struct HeaderIconButton: View {
    let palette: ReaderPalette
    let system: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(palette.muted)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Section label

struct SectionLabel: View {
    let palette: ReaderPalette
    let text: String
    var body: some View {
        Text(text)
            .font(.chickenUI(11, weight: .medium))
            .tracking(1.5)
            .textCase(.uppercase)
            .foregroundStyle(palette.muted)
    }
}

// MARK: - Continue reading card

struct ContinueReadingCard: View {
    let palette: ReaderPalette
    let book: Book
    let highlightCount: Int
    let secondsToday: Int
    let dailyGoalMinutes: Int
    let weekReading: [DayReading]
    let onContinue: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 36) {
            BookCover(book: book, palette: palette, size: .hero)
                .frame(width: 200, height: 300)

            VStack(alignment: .leading, spacing: 0) {
                Text("Last opened · \(timeAgo(book.lastOpenedAt))")
                    .font(.chickenUI(11, weight: .medium))
                    .tracking(1.5)
                    .textCase(.uppercase)
                    .foregroundStyle(palette.muted)
                    .padding(.bottom, 12)

                Text(book.title)
                    .font(.chickenSerif(36, weight: .medium))
                    .tracking(-0.5)
                    .foregroundStyle(palette.text)
                    .lineLimit(2)
                    .padding(.bottom, 8)

                Text(book.displayAuthor)
                    .font(.chickenSerif(16, italic: true))
                    .foregroundStyle(palette.muted)
                    .padding(.bottom, 28)

                ProgressMeter(
                    palette: palette,
                    progress: book.progress,
                    page: pageLabel(book),
                    total: totalPagesLabel(book)
                )
                .frame(maxWidth: 280)
                .padding(.bottom, 20)

                HStack(spacing: 14) {
                    Button(action: onContinue) {
                        HStack(spacing: 8) {
                            Text("Continue reading")
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    .buttonStyle(PrimaryReaderButton(palette: palette))

                    if book.pageCount != nil {
                        InlineMeta(palette: palette, system: "clock", text: pagesLeftLabel(book))
                    }
                    if highlightCount > 0 {
                        InlineMeta(palette: palette, system: "bookmark", text: "\(highlightCount) highlights")
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            DailyReadingPanel(
                palette: palette,
                secondsToday: secondsToday,
                goalMinutes: dailyGoalMinutes,
                week: weekReading
            )
            .frame(width: 200)
        }
        .padding(EdgeInsets(top: 32, leading: 36, bottom: 32, trailing: 36))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.surface)
                .stroke(palette.border, lineWidth: 0.5)
                .shadow(color: palette.shadow, radius: 1, x: 0, y: 1)
        )
    }

    private func timeAgo(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func pageLabel(_ book: Book) -> String {
        guard let total = book.pageCount, total > 0 else { return "—" }
        let page = max(1, Int(round(Double(total) * book.progress)))
        return "page \(page)"
    }

    private func totalPagesLabel(_ book: Book) -> String {
        guard let total = book.pageCount, total > 0 else { return "" }
        return "of \(total)"
    }

    private func pagesLeftLabel(_ book: Book) -> String {
        guard let total = book.pageCount, total > 0 else { return "" }
        let left = max(0, total - Int(round(Double(total) * book.progress)))
        return "~\(left) pages left"
    }
}

private struct ProgressMeter: View {
    let palette: ReaderPalette
    let progress: Double
    let page: String
    let total: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .leading) {
                Capsule().fill(palette.surfaceAlt).frame(height: 3)
                GeometryReader { geo in
                    Capsule().fill(palette.text)
                        .frame(width: max(0, geo.size.width * progress), height: 3)
                }
                .frame(height: 3)
            }
            HStack {
                Text("\(Int(round(progress * 100)))% complete")
                Spacer()
                Text("\(page) \(total)".trimmingCharacters(in: .whitespaces))
            }
            .font(.chickenMono(11))
            .foregroundStyle(palette.faint)
        }
    }
}

private struct InlineMeta: View {
    let palette: ReaderPalette
    let system: String
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: system).font(.system(size: 11))
            Text(text).font(.chickenUI(12))
        }
        .foregroundStyle(palette.muted)
    }
}

// MARK: - Daily reading panel (inline inside Continue Reading card)

private struct DailyReadingPanel: View {
    let palette: ReaderPalette
    let secondsToday: Int
    let goalMinutes: Int
    let week: [DayReading]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasShownGlint = false
    @State private var glintAt: CGFloat = -0.3  // -0.3 = off-screen left, 1.3 = off-screen right

    private var goalSeconds: Int { max(0, goalMinutes) * 60 }
    private var fraction: Double {
        guard goalSeconds > 0 else { return 0 }
        return min(1.0, Double(secondsToday) / Double(goalSeconds))
    }
    private var weekScaleSeconds: Int {
        let m = week.map(\.seconds).max() ?? 0
        return Swift.max(goalSeconds, m, 60)
    }
    private var metGoal: Bool { goalSeconds > 0 && secondsToday >= goalSeconds }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Reading today")
                .font(.chickenUI(11, weight: .medium))
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(palette.muted)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(primaryLabel)
                    .font(.chickenSerif(22, weight: .medium))
                    .foregroundStyle(palette.text)
                    .monospacedDigit()
                Text("/ \(goalMinutes) min")
                    .font(.chickenSerif(13, italic: true))
                    .foregroundStyle(palette.muted)
                    .monospacedDigit()
            }

            ZStack(alignment: .leading) {
                Capsule().fill(palette.surfaceAlt).frame(height: 3)
                GeometryReader { geo in
                    Capsule()
                        .fill(palette.text)
                        .frame(width: max(0, geo.size.width * fraction), height: 3)
                        .overlay(
                            // One-shot shimmer that runs the moment the user
                            // crosses the daily goal. Sweeps left → right
                            // exactly once, then sits idle for the rest of
                            // the day. Reduce-motion users skip the sweep
                            // entirely; the meter still fills.
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            .clear,
                                            palette.background.opacity(0.55),
                                            .clear
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(0, geo.size.width * fraction), height: 3)
                                .mask(
                                    Capsule()
                                        .fill(.white)
                                        .frame(width: 60, height: 3)
                                        .offset(x: glintAt * (geo.size.width * fraction + 80) - 40)
                                )
                                .opacity(reduceMotion ? 0 : 1)
                                .allowsHitTesting(false)
                        )
                }
                .frame(height: 3)
            }
            .onChange(of: metGoal) { _, met in
                guard met, !hasShownGlint, !reduceMotion else { return }
                hasShownGlint = true
                glintAt = -0.3
                withAnimation(.easeOut(duration: 1.1)) {
                    glintAt = 1.3
                }
            }

            Text(captionText)
                .font(.chickenSerif(11, italic: true))
                .foregroundStyle(palette.muted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if !week.isEmpty {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(week) { day in
                        DaySparkBar(
                            palette: palette,
                            day: day,
                            scaleSeconds: weekScaleSeconds,
                            goalSeconds: goalSeconds
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
        }
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 14, trailing: 16))
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.surfaceAlt.opacity(0.6))
                .stroke(palette.border, lineWidth: 0.5)
        )
    }

    private var primaryLabel: String {
        if secondsToday < 60 { return "\(secondsToday) sec" }
        let h = secondsToday / 3600
        let m = (secondsToday % 3600) / 60
        if h > 0 { return "\(h) h \(m) min" }
        return "\(m) min"
    }

    private var captionText: String {
        if goalSeconds <= 0 { return "Set a daily goal in settings." }
        if metGoal { return "Goal met. Read on." }
        if secondsToday == 0 { return "Open a book to start." }
        let remaining = goalSeconds - secondsToday
        let mins = (remaining + 59) / 60
        return mins == 1 ? "One minute to go." : "\(mins) minutes to go."
    }
}

private struct DaySparkBar: View {
    let palette: ReaderPalette
    let day: DayReading
    let scaleSeconds: Int
    let goalSeconds: Int

    private var fillFraction: Double {
        guard scaleSeconds > 0 else { return 0 }
        return min(1.0, Double(day.seconds) / Double(scaleSeconds))
    }
    private var metGoal: Bool { goalSeconds > 0 && day.seconds >= goalSeconds }

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(palette.surfaceAlt)
                    .frame(width: 10, height: 26)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(barColor)
                    .frame(width: 10, height: max(2, 26 * fillFraction))
            }
            Circle()
                .fill(metGoal ? palette.text : palette.faint.opacity(0.35))
                .frame(width: 2.5, height: 2.5)
            Text(day.dayLetter)
                .font(.chickenMono(8, weight: day.isToday ? .medium : .regular))
                .foregroundStyle(day.isToday ? palette.text : palette.faint)
        }
        .frame(width: 16)
    }

    private var barColor: Color {
        if day.isToday { return palette.text }
        return day.seconds == 0 ? palette.surfaceAlt : palette.muted
    }
}

// MARK: - Books-this-year strip (separate from the daily reading goal)

private struct BooksThisYearStrip: View {
    let palette: ReaderPalette
    let year: Int
    let finishedCount: Int
    let goal: Int

    private var fraction: Double {
        guard goal > 0 else { return 0 }
        return min(1.0, Double(finishedCount) / Double(goal))
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text("Books this year · \(String(year))")
                .font(.chickenUI(11, weight: .medium))
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(palette.muted)
                .layoutPriority(1)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(finishedCount)")
                    .font(.chickenSerif(14, weight: .medium))
                    .foregroundStyle(palette.text)
                    .monospacedDigit()
                Text("of \(goal)")
                    .font(.chickenSerif(12, italic: true))
                    .foregroundStyle(palette.muted)
                    .monospacedDigit()
            }
            .layoutPriority(1)

            ZStack(alignment: .leading) {
                Capsule().fill(palette.surfaceAlt).frame(height: 2)
                GeometryReader { geo in
                    Capsule()
                        .fill(palette.muted)
                        .frame(width: max(0, geo.size.width * fraction), height: 2)
                }
                .frame(height: 2)
            }

            Text(caption)
                .font(.chickenSerif(11, italic: true))
                .foregroundStyle(palette.faint)
                .lineLimit(1)
                .layoutPriority(1)
        }
        .padding(.horizontal, 4)
    }

    private var caption: String {
        guard goal > 0 else { return "Set in settings." }
        if finishedCount == 0 { return "—" }
        if finishedCount >= goal { return "goal met" }
        let remaining = goal - finishedCount
        return remaining == 1 ? "1 to go" : "\(remaining) to go"
    }
}

// MARK: - Book grid + tile

struct BookGrid: View {
    let palette: ReaderPalette
    let books: [Book]
    let onOpen: (Book) -> Void

    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 36, alignment: .top)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 36) {
            ForEach(books) { book in
                BookTile(palette: palette, book: book, onOpen: { onOpen(book) })
            }
        }
    }
}

private struct BookTile: View {
    @EnvironmentObject private var library: LocalLibraryStore
    let palette: ReaderPalette
    let book: Book
    let onOpen: () -> Void
    @State private var hover = false

    private var highlightCount: Int { library.highlights(for: book).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BookCover(book: book, palette: palette, size: .tile)
                .aspectRatio(2.0/3.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .shadow(
                    color: palette.shadow,
                    radius: hover ? 8 : 2,
                    x: 0,
                    y: hover ? 6 : 1
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.chickenSerif(15, weight: .medium))
                    .foregroundStyle(palette.text)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(book.displayAuthor)
                    .font(.chickenSerif(13, italic: true))
                    .foregroundStyle(palette.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 4)

                tileMeta
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .offset(y: hover ? -3 : 0)
        .animation(.easeOut(duration: 0.2), value: hover)
        .onHover { hover = $0 }
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .contextMenu {
            Button(role: .destructive) { library.delete(book) } label: { Text("Remove") }
        }
    }

    @ViewBuilder
    private var tileMeta: some View {
        HStack(spacing: 10) {
            if book.progress >= 1 {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark").font(.system(size: 10))
                    Text("Read")
                }
                .font(.chickenUI(11))
                .foregroundStyle(palette.faint)
            } else if book.progress > 0 {
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.surfaceAlt).frame(height: 2)
                    GeometryReader { g in
                        Capsule().fill(palette.muted)
                            .frame(width: max(0, g.size.width * book.progress), height: 2)
                    }
                    .frame(height: 2)
                }
                .frame(maxWidth: 100)
                Text("\(Int(round(book.progress * 100)))%")
                    .font(.chickenMono(11))
                    .foregroundStyle(palette.faint)
            } else {
                Text("Unread")
                    .font(.chickenUI(11))
                    .foregroundStyle(palette.faint)
            }

            Spacer(minLength: 0)

            if highlightCount > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "bookmark").font(.system(size: 9))
                    Text("\(highlightCount)").font(.chickenMono(11))
                }
                .foregroundStyle(palette.faint)
            }
        }
    }
}

// MARK: - Cover

enum BookCoverSize {
    case hero
    case tile

    var titleSize: CGFloat {
        switch self {
        case .hero: return 22
        case .tile: return 17
        }
    }

    var authorSize: CGFloat {
        switch self {
        case .hero: return 13
        case .tile: return 11
        }
    }

    var pad: CGFloat {
        switch self {
        case .hero: return 28
        case .tile: return 22
        }
    }

    var ruleWidth: CGFloat {
        switch self {
        case .hero: return 28
        case .tile: return 22
        }
    }
}

struct BookCover: View {
    @EnvironmentObject private var library: LocalLibraryStore
    let book: Book
    let palette: ReaderPalette
    let size: BookCoverSize

    @State private var generatedImage: NSImage?

    /// A source image is "cover-shaped" when its aspect is portrait-ish or near
    /// square. Anything wider than ~1.05:1 is almost always a slide deck or a
    /// two-page-spread (front + back as one page) and looks awful when
    /// center-cropped to 2:3 — fall back to the stylized cover instead.
    private var imageIsCoverShaped: Bool {
        guard let image = generatedImage, image.size.height > 0 else { return false }
        return image.size.width / image.size.height <= 1.05
    }

    var body: some View {
        // Rectangle establishes the cover's frame. Whatever the parent proposes
        // (e.g. 200×300 from an external aspect-ratio modifier) is the bound.
        // The overlay can't exceed that bound, and .clipped() trims any image
        // overflow from .aspectRatio(.fill). This is the only reliable pattern
        // here — putting .frame(maxWidth: .infinity) inside an .aspectRatio
        // chain lets Image's intrinsic size leak past the parent's frame.
        Rectangle()
            .fill(preset.background)
            .overlay {
                if let image = generatedImage, imageIsCoverShaped {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    stylizedCover
                }
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .task(id: library.coverURL(for: book)?.path) {
                if let url = library.coverURL(for: book) {
                    generatedImage = await CoverImageCache.shared.image(for: url)
                } else {
                    generatedImage = nil
                }
            }
    }

    private var preset: CoverPreset { CoverPreset.preset(for: book.coverTintIndex) }

    private var stylizedCover: some View {
        ZStack(alignment: .bottomLeading) {
            CoverMotif(motif: preset.motif, accent: preset.accent)

            VStack(alignment: .leading, spacing: 8) {
                Rectangle()
                    .fill(preset.accent.opacity(0.5))
                    .frame(width: size.ruleWidth, height: 1)

                Text(book.title)
                    .font(.system(size: size.titleSize, weight: .medium, design: .serif))
                    .foregroundStyle(preset.accent)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                Text(book.displayAuthor)
                    .font(.system(size: size.authorSize, weight: .regular, design: .serif).italic())
                    .foregroundStyle(preset.accent.opacity(0.78))
                    .lineLimit(2)
            }
            .padding(size.pad)
        }
    }
}

private struct CoverPreset {
    let background: Color
    let accent: Color
    let motif: CoverMotifKind

    static func preset(for index: Int) -> CoverPreset {
        let presets: [CoverPreset] = [
            CoverPreset(background: .hex(0x1F3A4D), accent: .hex(0xD9B380), motif: .lines),
            CoverPreset(background: .hex(0x6B3E3A), accent: .hex(0xF4E4D0), motif: .frame),
            CoverPreset(background: .hex(0x2D4A2A), accent: .hex(0xD8C99B), motif: .tree),
            CoverPreset(background: .hex(0x1A1A1A), accent: .hex(0xC9A861), motif: .flourish),
            CoverPreset(background: .hex(0x3A3D40), accent: .hex(0xB8B0A0), motif: .crack),
            CoverPreset(background: .hex(0xB8902F), accent: .hex(0x2A2519), motif: .pattern),
        ]
        return presets[((index % presets.count) + presets.count) % presets.count]
    }
}

private enum CoverMotifKind { case lines, frame, tree, flourish, crack, pattern }

private struct CoverMotif: View {
    let motif: CoverMotifKind
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            switch motif {
            case .lines:
                ZStack {
                    Path { p in
                        p.move(to: CGPoint(x: w * 0.10, y: h * 0.27))
                        p.addLine(to: CGPoint(x: w * 0.90, y: h * 0.20))
                    }
                    .stroke(accent.opacity(0.18), lineWidth: 0.5)

                    Path { p in
                        p.move(to: CGPoint(x: w * 0.20, y: h * 0.43))
                        p.addLine(to: CGPoint(x: w * 0.85, y: h * 0.53))
                    }
                    .stroke(accent.opacity(0.18), lineWidth: 0.5)

                    Path { p in
                        p.move(to: CGPoint(x: w * 0.10, y: h * 0.66))
                        p.addLine(to: CGPoint(x: w * 0.80, y: h * 0.60))
                    }
                    .stroke(accent.opacity(0.18), lineWidth: 0.5)

                    ForEach(0..<3, id: \.self) { i in
                        let xs = [0.30, 0.70, 0.45]
                        let ys = [0.33, 0.50, 0.65]
                        Circle()
                            .fill(accent.opacity(0.18))
                            .frame(width: 4, height: 4)
                            .position(x: w * xs[i], y: h * ys[i])
                    }
                }
            case .frame:
                ZStack {
                    Rectangle()
                        .stroke(accent.opacity(0.40), lineWidth: 0.5)
                        .padding(12)
                    Rectangle()
                        .stroke(accent.opacity(0.24), lineWidth: 0.3)
                        .padding(16)
                }
            case .tree:
                ZStack {
                    ForEach([0.20, 0.50, 0.80], id: \.self) { x in
                        Path { p in
                            p.move(to: CGPoint(x: w * x, y: h * 0.20))
                            p.addLine(to: CGPoint(x: w * x, y: h * 0.80))
                        }
                        .stroke(accent.opacity(0.18), lineWidth: 0.5)
                    }
                    ForEach([0.35, 0.65], id: \.self) { x in
                        Path { p in
                            p.move(to: CGPoint(x: w * x, y: h * 0.30))
                            p.addLine(to: CGPoint(x: w * x, y: h * 0.70))
                        }
                        .stroke(accent.opacity(0.14), lineWidth: 0.4)
                    }
                }
            case .flourish:
                ZStack {
                    Path { p in
                        p.move(to: CGPoint(x: w * 0.20, y: h * 0.50))
                        p.addQuadCurve(to: CGPoint(x: w * 0.50, y: h * 0.50), control: CGPoint(x: w * 0.35, y: h * 0.40))
                        p.addQuadCurve(to: CGPoint(x: w * 0.80, y: h * 0.50), control: CGPoint(x: w * 0.65, y: h * 0.60))
                    }
                    .stroke(accent.opacity(0.50), lineWidth: 0.5)

                    Circle()
                        .fill(accent.opacity(0.50))
                        .frame(width: 3, height: 3)
                        .position(x: w * 0.50, y: h * 0.50)
                }
            case .crack:
                Path { p in
                    p.move(to: CGPoint(x: w * 0.50, y: 0))
                    p.addLine(to: CGPoint(x: w * 0.47, y: h * 0.20))
                    p.addLine(to: CGPoint(x: w * 0.55, y: h * 0.37))
                    p.addLine(to: CGPoint(x: w * 0.45, y: h * 0.57))
                    p.addLine(to: CGPoint(x: w * 0.52, y: h * 0.77))
                    p.addLine(to: CGPoint(x: w * 0.47, y: h))
                }
                .stroke(accent.opacity(0.18), lineWidth: 0.5)
            case .pattern:
                Canvas { ctx, size in
                    let step: CGFloat = 18
                    ctx.opacity = 0.22
                    var x: CGFloat = 0
                    while x < size.width + step {
                        var y: CGFloat = 0
                        while y < size.height + step {
                            ctx.stroke(
                                Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6)),
                                with: .color(accent),
                                lineWidth: 0.5
                            )
                            ctx.fill(
                                Path(ellipseIn: CGRect(x: x + step / 2 - 1, y: y + step / 2 - 1, width: 2, height: 2)),
                                with: .color(accent)
                            )
                            y += step
                        }
                        x += step
                    }
                }
            }
        }
    }
}

private final class CoverImageCache {
    static let shared = CoverImageCache()
    private let cache = NSCache<NSString, NSImage>()
    private init() {
        cache.countLimit = 500
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInvalidate),
            name: .chickenCoverCacheInvalidated,
            object: nil
        )
    }

    func image(for url: URL) async -> NSImage? {
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        return await Task.detached(priority: .utility) { [cache] in
            guard let image = NSImage(contentsOf: url) else { return nil }
            cache.setObject(image, forKey: key)
            return image
        }.value
    }

    @objc private func handleInvalidate() {
        cache.removeAllObjects()
    }
}

// MARK: - Footer

private struct LibraryFooter: View {
    let palette: ReaderPalette
    let bookCount: Int
    let highlightCount: Int
    let finishedCount: Int

    var body: some View {
        HStack {
            Text("chicken · v0.5")
                .font(.chickenUI(12))
                .tracking(0.4)
                .foregroundStyle(palette.faint)
            Spacer()
            HStack(spacing: 24) {
                Text("\(bookCount) books")
                Text("\(highlightCount) highlights")
                Text("\(finishedCount) read")
            }
            .font(.chickenUI(12))
            .foregroundStyle(palette.faint)
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(
            palette.background
                .overlay(alignment: .top) {
                    Rectangle().fill(palette.border).frame(height: 0.5)
                }
        )
    }
}

// MARK: - Empty state

private struct EmptyLibraryPanel: View {
    let palette: ReaderPalette
    let onScan: () -> Void
    let onImport: () -> Void
    let scanState: LibraryScanState

    var body: some View {
        VStack(alignment: .center, spacing: 18) {
            Image(systemName: "books.vertical")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(palette.muted)
                .padding(.bottom, 4)

            Text("Your library is empty")
                .font(.chickenSerif(28, weight: .medium))
                .foregroundStyle(palette.text)

            Text("Scan this Mac for PDFs and EPUBs you already own, or import files directly. Originals stay where they are — Chicken keeps a managed local copy.")
                .font(.chickenUI(14))
                .foregroundStyle(palette.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
                .lineSpacing(2)

            HStack(spacing: 12) {
                Button(action: onScan) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12, weight: .medium))
                        Text("Scan this Mac")
                    }
                }
                .buttonStyle(PrimaryReaderButton(palette: palette))
                .disabled(scanState.isScanning)

                Button(action: onImport) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                        Text("Import files")
                    }
                }
                .buttonStyle(SecondaryReaderButton(palette: palette))
            }
            .padding(.top, 8)

            if case .scanning(let checked, let found, _) = scanState {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("\(checked.formatted()) files checked · \(found) found")
                        .font(.chickenMono(11))
                        .foregroundStyle(palette.faint)
                }
                .padding(.top, 12)
            }
        }
        .padding(.vertical, 80)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.surface)
                .stroke(palette.border, lineWidth: 0.5)
        )
    }
}

// MARK: - Discovered books sheet

struct DiscoveredBooksSheet: View {
    @EnvironmentObject private var library: LocalLibraryStore
    let palette: ReaderPalette
    let onClose: () -> Void

    private var likely: [DiscoveredBook] {
        library.discoveredBooks.filter(\.isLikelyBook)
    }

    private var others: [DiscoveredBook] {
        library.discoveredBooks.filter { !$0.isLikelyBook }
    }

    private var importAllTitle: String {
        switch library.importState {
        case .idle: return "Import \(likely.count) likely books"
        case .importing(let completed, let total): return "Importing \(completed) of \(total)"
        case .finished(let imported): return "Imported \(imported)"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Found on this Mac")
                        .font(.chickenSerif(22, weight: .medium))
                        .foregroundStyle(palette.text)
                    Text(scanStatusLine)
                        .font(.chickenUI(12))
                        .foregroundStyle(palette.muted)
                }
                Spacer()
                if library.scanState.isScanning {
                    ProgressView().controlSize(.small)
                }
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.muted)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider().background(palette.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !likely.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                SectionLabel(palette: palette, text: "Likely books · \(likely.count)")
                                Spacer()
                                Button { library.importAllDiscovered() } label: {
                                    Text(importAllTitle)
                                }
                                .buttonStyle(SecondaryReaderButton(palette: palette))
                                .disabled(likely.isEmpty || library.importState.isImporting)
                            }
                            ForEach(likely) { d in
                                DiscoveredRow(palette: palette, discovered: d)
                            }
                        }
                    }

                    if !others.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionLabel(palette: palette, text: "Lower confidence · \(others.count)")
                            ForEach(others) { d in
                                DiscoveredRow(palette: palette, discovered: d)
                            }
                        }
                    }

                    if library.discoveredBooks.isEmpty && !library.scanState.isScanning {
                        Text("No new files found.")
                            .font(.chickenUI(14))
                            .foregroundStyle(palette.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 640, idealWidth: 720, minHeight: 440, idealHeight: 560)
        .background(palette.background)
    }

    private var scanStatusLine: String {
        switch library.scanState {
        case .idle:
            return "Scan again to refresh."
        case .scanning(let checked, let found, let folder):
            return "Scanning · \(checked.formatted()) checked · \(found) found · \(folder)"
        case .finished(let found):
            return "Scan complete · \(found) found. Import copies into Chicken; originals stay where they are."
        case .failed(let message):
            return message
        }
    }
}

private struct DiscoveredRow: View {
    @EnvironmentObject private var library: LocalLibraryStore
    let palette: ReaderPalette
    let discovered: DiscoveredBook

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: discovered.format.systemImage)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(palette.muted)
                .frame(width: 36, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(palette.surfaceAlt)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(discovered.title)
                    .font(.chickenSerif(14, weight: .medium))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                Text(discovered.sourceFolder)
                    .font(.chickenUI(11))
                    .foregroundStyle(palette.muted)
                    .lineLimit(1)
                Text(metaLine)
                    .font(.chickenMono(10))
                    .foregroundStyle(palette.faint)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(discovered.format.label)
                .font(.chickenMono(10, weight: .medium))
                .foregroundStyle(palette.muted)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(palette.surfaceAlt).stroke(palette.border, lineWidth: 0.5)
                )

            Text("\(discovered.bookScore)")
                .font(.chickenMono(10, weight: .medium))
                .foregroundStyle(palette.muted)
                .frame(width: 24)

            Button { library.importDiscovered(discovered) } label: {
                Text("Import")
            }
            .buttonStyle(SecondaryReaderButton(palette: palette))
            .disabled(library.importState.isImporting)

            Button { library.dismissDiscovered(discovered) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.faint)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.surface)
                .stroke(palette.border, lineWidth: 0.5)
        )
    }

    private var metaLine: String {
        var parts: [String] = []
        if let author = discovered.author, !author.isEmpty { parts.append(author) }
        if let pages = discovered.pageCount { parts.append("\(pages.formatted()) pages") }
        if let publisher = discovered.publisher, !publisher.isEmpty { parts.append(publisher) }
        if discovered.fileSize > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: discovered.fileSize, countStyle: .file))
        }
        parts.append(discovered.classification)
        return parts.joined(separator: " · ")
    }
}

// MARK: - Button styles

struct PrimaryReaderButton: ButtonStyle {
    let palette: ReaderPalette
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.chickenUI(13, weight: .medium))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .foregroundStyle(palette.background)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(palette.text.opacity(configuration.isPressed ? 0.85 : 1))
            )
    }
}

struct SecondaryReaderButton: ButtonStyle {
    let palette: ReaderPalette
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.chickenUI(13, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(palette.text)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(configuration.isPressed ? palette.surfaceAlt : palette.surface)
                    .stroke(palette.border, lineWidth: 0.5)
            )
    }
}
