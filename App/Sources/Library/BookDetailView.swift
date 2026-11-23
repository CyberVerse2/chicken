import ChickenKit
import SwiftData
import SwiftUI
#if os(macOS)
import AppKit
#endif

struct BookDossierView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppRouter.self) private var router
    @Environment(\.palette) private var palette
    @Environment(\.readingTheme) private var theme
    @Environment(\.openBook) private var openBook
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var collections: [BookCollection]

    let bookID: UUID
    var isPage = false

    @State private var coverHue: CoverHue?
    @State private var summaryExpanded = false
    @State private var confirmingRemoval = false
    @State private var quoteCardRequest: QuoteCardRequest?
    @State private var addingCollection = false
    @State private var newCollectionName = ""
    @State private var companionNote: String?
    @State private var generatingCompanion = false
    @State private var companionError: String?
    @State private var showingMetadataMatch = false

    private var book: Book? { library.book(id: bookID) }
    private var isCompact: Bool { sizeClass == .compact }

    private var sortedCollections: [BookCollection] {
        collections.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Group {
            if let book {
                dossier(for: book)
            } else {
                ContentUnavailableView("Book Unavailable", systemImage: "book.closed")
                    .background(palette.background.ignoresSafeArea())
            }
        }
        .sheet(item: $quoteCardRequest) { request in
            QuoteCardSheet(request: request)
                .readingTheme(library.preferences.theme)
        }
        .sheet(isPresented: $showingMetadataMatch) {
            if let book {
                NavigationStack {
                    BookMetadataMatchSheet(book: book)
                        .environment(library)
                }
                .readingTheme(library.preferences.theme)
            }
        }
        #if os(macOS)
        .frame(minWidth: isPage ? nil : 540, idealWidth: isPage ? nil : 620, minHeight: isPage ? nil : 600, idealHeight: isPage ? nil : 720)
        #endif
    }

    private func dossier(for book: Book) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                atmosphericHero(for: book)
                VStack(alignment: .leading, spacing: 26) {
                    statStrip(for: book)
                        .padding(.horizontal, gutter)
                    collectionsStrip(for: book)
                    if !book.genres.isEmpty || !book.moods.isEmpty {
                        genresAndMoodsStrip(for: book)
                    }
                    if let summary = book.summary, !summary.isEmpty {
                        summarySection(summary)
                            .padding(.horizontal, isCompact ? 20 : 32)
                    } else {
                        Button {
                            showingMetadataMatch = true
                        } label: {
                            Label("Fetch Synopsis & Details", systemImage: "sparkles.rectangle.stack")
                                .font(.chickenUI(13, weight: .semibold))
                                .foregroundStyle(palette.ribbon)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .chickenGlass(in: Capsule(), interactive: true)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, isCompact ? 20 : 32)
                    }
                    if ReadingCompanion.isAvailable && (book.progress > 0.05 || (book.summary ?? "").isEmpty) {
                        companionSection(for: book)
                            .padding(.horizontal, isCompact ? 20 : 32)
                    }
                    if book.highlightCount > 0 {
                        highlightsSection(for: book)
                            .padding(.horizontal, isCompact ? 20 : 32)
                    }
                    relatedShelves(for: book)
                    detailsSection(for: book)
                        .padding(.horizontal, isCompact ? 20 : 32)
                }
                .padding(.top, 24)
                .padding(.bottom, 48)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.background.ignoresSafeArea())
        .ignoresSafeArea(edges: isPage ? [] : .top)
        .task(id: "\(book.id)-\(book.coverImageName ?? "")") {
            coverHue = await CoverTintModifier.hue(for: book, library: library)
        }
        .overlay(alignment: .top) {
            if !isPage {
                GlassEffectContainer(spacing: 12) {
                    HStack {
                        CircularGlassButton(
                            title: "Close",
                            systemImage: "xmark",
                            diameter: 44,
                            iconSize: 17,
                            action: { dismiss() }
                        )

                        Spacer()

                        moreMenu(for: book)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, isCompact ? 18 : 20)
            }
        }
        .pageTitle(isPage ? book.displayTitle : "")
        .toolbar {
            if isPage { LibraryToolbar() }
        }
        .alert("New Collection", isPresented: $addingCollection) {
            TextField("Collection name", text: $newCollectionName)
            Button("Create") {
                if library.createCollection(named: newCollectionName, with: [book]) != nil {
                    Haptics.impact(.light)
                }
                newCollectionName = ""
            }
            Button("Cancel", role: .cancel) { newCollectionName = "" }
        }
        .confirmationDialog("Remove \u{201C}\(book.displayTitle)\u{201D}?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if !isPage { dismiss() }
                library.delete(book)
            }
        } message: {
            Text("Chicken's copy, highlights, and bookmarks for this book will be deleted. The original file is not affected.")
        }
    }

    private func atmosphericHero(for book: Book) -> some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [
                    (coverHue?.wash(for: theme) ?? palette.surfaceAlt).opacity(palette.isDark ? 0.65 : 0.72),
                    palette.background,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .animation(reduceMotion ? nil : ChickenMotion.theme, value: coverHue)

            VStack(spacing: 18) {
                Button { read(book) } label: {
                    BookCover(book: book, style: .hero)
                        .frame(width: isCompact ? 156 : 176, height: isCompact ? 234 : 264)
                        .downloadBadge(book, size: 28)
                        .shadow(color: palette.shadow.opacity(0.95), radius: 2, x: 0, y: 1)
                        .shadow(color: palette.shadow, radius: 24, x: 0, y: 16)
                        .coverRibbon(book.progress > 0 && !book.isFinished, length: 26, width: 12)
                }
                .buttonStyle(TactilePressStyle())
                .accessibilityLabel("Read \(book.displayTitle)")

                VStack(spacing: 6) {
                    if let seriesBadge = book.seriesBadgeText, let seriesKey = book.seriesName {
                        Button {
                            Haptics.selection()
                            router.filterLibrary(by: .series(seriesKey))
                            if !isPage { dismiss() }
                        } label: {
                            Text(seriesBadge)
                                .chickenEyebrow(palette, color: palette.ribbon)
                        }
                        .buttonStyle(.plain)
                    }
                    Text(book.displayTitle)
                        .font(.chickenDisplay(isCompact ? 25 : 30))
                        .tracking(-0.6)
                        .foregroundStyle(palette.text)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                    if let author = book.author, !author.isEmpty {
                        Button {
                            Haptics.selection()
                            router.filterLibrary(by: .author(author))
                            if !isPage { dismiss() }
                        } label: {
                            Text(book.releaseYear.map { "\(author) · \($0)" } ?? author)
                                .font(.chickenSerif(16.5, italic: true))
                                .foregroundStyle(palette.muted)
                        }
                        .buttonStyle(.plain)
                    } else if let year = book.releaseYear {
                        Text(String(year))
                            .font(.chickenMono(12.5))
                            .foregroundStyle(palette.muted)
                    }
                }
                .padding(.horizontal, 24)

                if book.progress > 0 && !book.isFinished {
                    VStack(spacing: 8) {
                        ProgressLine(progress: book.progress, height: 3.5)
                            .frame(maxWidth: 260)
                        HStack(spacing: 6) {
                            Text("\(Int((book.progress * 100).rounded()))%")
                                .font(.chickenMono(12, weight: .semibold))
                                .foregroundStyle(palette.ribbon)
                            if let chapter = book.lastChapterTitle, !chapter.isEmpty, chapter != book.title {
                                Text("·")
                                    .foregroundStyle(palette.faint)
                                Text(chapter)
                                    .font(.chickenUI(12.5))
                                    .foregroundStyle(palette.muted)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }

                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        PrimaryHeroButton(
                            title: actionTitle(for: book),
                            systemImage: "arrow.right",
                            height: 50,
                            action: { read(book) }
                        )
                        .frame(maxWidth: isCompact ? .infinity : 260)

                        CircularGlassButton(
                            title: book.isFinished ? "Mark as Unread" : "Mark as Finished",
                            systemImage: "checkmark",
                            diameter: 50,
                            iconSize: 19,
                            foreground: book.isFinished ? palette.ribbon : palette.text,
                            action: {
                                Haptics.impact(.light)
                                library.setFinished(!book.isFinished, for: book)
                            }
                        )
                    }
                }
                .frame(maxWidth: isCompact ? 320 : .infinity)
                .padding(.horizontal, 24)
                .padding(.top, 4)
            }
            .padding(.top, isPage ? 32 : 76)
            .padding(.bottom, 22)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
    }

    private var gutter: CGFloat { isCompact ? 20 : 32 }

    private var horizontalFadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.03),
                .init(color: .black, location: 0.94),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func statStrip(for book: Book) -> some View {
        var stats: [ChickenStat] = [
            ChickenStat(label: "Format", value: book.format.label, isNumeric: false),
        ]
        if let pages = book.pageCount, pages > 0 {
            stats.append(ChickenStat(label: "Pages", value: "\(pages)"))
        }
        if book.isFinished {
            let value = book.finishedAt.map { $0.formatted(.dateTime.month(.abbreviated).day()) } ?? "Done"
            stats.append(ChickenStat(label: "Finished", value: value, isNumeric: false, isAccent: true))
        } else if let left = book.estimatedPagesLeft {
            let duration = ReadingEstimate.duration(forPages: left, minutesPerPage: library.preferences.minutesPerPage)
            stats.append(ChickenStat(label: "Left", value: duration))
        } else if let pages = book.pageCount, pages > 0 {
            let duration = ReadingEstimate.duration(forPages: pages, minutesPerPage: library.preferences.minutesPerPage)
            stats.append(ChickenStat(label: "Est. read", value: duration))
        }
        if book.highlightCount > 0 {
            stats.append(ChickenStat(label: book.highlightCount == 1 ? "Note" : "Notes", value: "\(book.highlightCount)"))
        }
        if let rating = book.formattedRating {
            stats.append(ChickenStat(label: "Rating", value: "★ \(rating)"))
        }
        return ChickenStatStrip(stats: stats)
    }

    private func genresAndMoodsStrip(for book: Book) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(book.genres, id: \.self) { genre in
                    Button {
                        Haptics.selection()
                        router.filterLibrary(by: .genre(genre))
                        if !isPage { dismiss() }
                    } label: {
                        Text(genre)
                            .font(.chickenUI(12.5, weight: .medium))
                            .foregroundStyle(palette.text)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(palette.surfaceAlt, in: Capsule())
                            .overlay(Capsule().stroke(palette.border, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
                ForEach(book.moods, id: \.self) { mood in
                    Text(mood)
                        .font(.chickenSerif(12.5, italic: true))
                        .foregroundStyle(palette.muted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.never)
        .contentMargins(.horizontal, gutter, for: .scrollContent)
    }

    @ViewBuilder
    private func relatedShelves(for book: Book) -> some View {
        let inSeries = library.seriesBooks(for: book)
        if inSeries.count > 1, let seriesName = book.seriesName {
            BookShelf(title: "In \(seriesName)", books: inSeries, gutter: gutter)
        }
        let otherByAuthor = library.otherBooksByAuthor(of: book)
        if !otherByAuthor.isEmpty, let author = book.author {
            BookShelf(title: "More by \(author)", books: otherByAuthor, gutter: gutter)
        }
    }

    private func collectionsStrip(for book: Book) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Collections")
                .padding(.horizontal, gutter)
            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(sortedCollections) { collection in
                            let member = library.contains(book, in: collection)
                            Button {
                                Haptics.selection()
                                withAnimation(reduceMotion ? nil : ChickenMotion.snappy) {
                                    if member {
                                        library.remove([book], from: collection)
                                    } else {
                                        library.add([book], to: collection)
                                    }
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: member ? "checkmark" : "plus")
                                        .font(.system(size: 10.5, weight: .semibold))
                                    Text(collection.name)
                                        .font(.chickenUI(13, weight: member ? .semibold : .medium))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .chickenGlassPill(isSelected: member)
                            }
                            .buttonStyle(.plain)
                        }
                        Button {
                            newCollectionName = ""
                            addingCollection = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 11.5, weight: .medium))
                                Text("New")
                                    .font(.chickenUI(13, weight: .medium))
                            }
                            .foregroundStyle(palette.muted)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .chickenGlass(in: Capsule(), interactive: true)
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
            }
            .scrollIndicators(.never)
            .contentMargins(.horizontal, gutter, for: .scrollContent)
            .mask(horizontalFadeMask)
        }
    }

    private func summarySection(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Synopsis")
            Text(summary)
                .font(.chickenSerif(16))
                .foregroundStyle(palette.text)
                .lineSpacing(6)
                .lineLimit(summaryExpanded ? nil : 5)
            if summary.count > 300 {
                Button(summaryExpanded ? "Show Less" : "Read More") {
                    withAnimation(reduceMotion ? nil : ChickenMotion.standard) { summaryExpanded.toggle() }
                }
                .font(.chickenUI(13, weight: .semibold))
                .foregroundStyle(palette.ribbon)
                .buttonStyle(TactilePressStyle(scale: 0.96))
            }
        }
    }

    private func companionSection(for book: Book) -> some View {
        let isRecap = book.progress > 0.05
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                SectionLabel(text: isRecap ? "Catch me up" : "About this book")
                Spacer()
                if companionNote == nil {
                    Button {
                        generateCompanion(for: book, isRecap: isRecap)
                    } label: {
                        HStack(spacing: 6) {
                            if generatingCompanion {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 11.5, weight: .semibold))
                            }
                            Text(generatingCompanion ? "Thinking…" : (isRecap ? "Recap" : "Summarize"))
                                .font(.chickenUI(12.5, weight: .semibold))
                        }
                        .foregroundStyle(palette.text)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .chickenGlass(in: Capsule(), interactive: true)
                    }
                    .buttonStyle(.plain)
                    .disabled(generatingCompanion)
                }
            }

            if let companionNote {
                Text(companionNote)
                    .font(.chickenSerif(15.5))
                    .foregroundStyle(palette.text)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if let companionError {
                Text(companionError)
                    .font(.chickenUI(12.5))
                    .foregroundStyle(palette.muted)
            }
        }
        .animation(reduceMotion ? nil : ChickenMotion.standard, value: companionNote)
    }

    private func generateCompanion(for book: Book, isRecap: Bool) {
        generatingCompanion = true
        companionError = nil
        let title = book.displayTitle
        let author = book.author
        let progress = book.progress
        let chapter = book.lastChapterTitle
        let highlights = book.sortedHighlights.map(\.text)
        Task {
            defer { generatingCompanion = false }
            do {
                let result: String
                if isRecap {
                    result = try await ReadingCompanion.recap(
                        title: title,
                        author: author,
                        progress: progress,
                        chapter: chapter,
                        highlights: highlights
                    )
                } else {
                    result = try await ReadingCompanion.briefOverview(title: title, author: author)
                }
                if !result.isEmpty {
                    companionNote = result
                }
            } catch {
                companionError = "On-device summary couldn't run right now."
            }
        }
    }

    private func highlightsSection(for book: Book) -> some View {
        ChickenSection("Highlights", count: book.highlightCount) {
            ForEach(Array(book.sortedHighlights.prefix(6).enumerated()), id: \.element.id) { index, highlight in
                ChickenRow(isLast: index == min(book.highlightCount, 6) - 1) {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            read(book, jumpTo: JumpTarget(location: highlight.location, chapterIndex: highlight.chapterIndex))
                        } label: {
                            Text({
                                var text = AttributedString(highlight.text)
                                text.backgroundColor = highlight.color.fill
                                return text
                            }())
                            .font(.chickenSerif(15.5))
                            .foregroundStyle(palette.text)
                            .lineSpacing(5)
                            .lineLimit(5)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(TactilePressStyle(scale: 0.99))

                        HStack {
                            if !highlight.note.isEmpty {
                                Text(highlight.note)
                                    .font(.chickenSerif(13, italic: true))
                                    .foregroundStyle(palette.muted)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button {
                                quoteCardRequest = QuoteCardRequest(
                                    quote: highlight.text,
                                    note: highlight.note,
                                    bookTitle: book.displayTitle,
                                    author: book.displayAuthor,
                                    highlightColor: highlight.color,
                                    coverTintIndex: book.coverTintIndex
                                )
                            } label: {
                                Label("Quote Card", systemImage: "square.and.arrow.up")
                                    .font(.chickenUI(11.5, weight: .medium))
                                    .foregroundStyle(palette.muted)
                            }
                            .buttonStyle(TactilePressStyle(scale: 0.95))
                        }
                    }
                }
            }
        }
    }

    private func detailsSection(for book: Book) -> some View {
        let rows: [(String, String)] = [
            ("Series", book.seriesBadgeText ?? ""),
            ("Published", book.releaseYear.map(String.init) ?? ""),
            ("Publisher", book.publisher ?? ""),
            ("Language", book.language.flatMap { Locale.current.localizedString(forLanguageCode: $0) } ?? book.language ?? ""),
            ("ISBN", book.isbn ?? ""),
            ("File Size", book.fileSize > 0 ? ByteCountFormatter.string(fromByteCount: book.fileSize, countStyle: .file) : ""),
            ("Added", book.importedAt.formatted(date: .long, time: .omitted)),
            ("Finished", book.finishedAt?.formatted(date: .long, time: .omitted) ?? ""),
        ].filter { !$0.1.isEmpty }
        let duplicate = library.duplicateEdition(of: book)
        let catalogURL = book.catalogURL
        let hasExtraRows = duplicate != nil || catalogURL != nil

        return Group {
            if !rows.isEmpty || hasExtraRows {
                ChickenSection("Edition", accessory: {
                    Button("Match Metadata") { showingMetadataMatch = true }
                        .font(.chickenUI(12.5, weight: .medium))
                        .foregroundStyle(palette.ribbon)
                        .buttonStyle(.plain)
                }) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        ChickenRow(isLast: index == rows.count - 1 && !hasExtraRows) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(row.0)
                                    .font(.chickenUI(13.5))
                                    .foregroundStyle(palette.muted)
                                Spacer(minLength: 16)
                                Text(row.1)
                                    .font(.chickenUI(13.5, weight: .medium))
                                    .foregroundStyle(palette.text)
                                    .multilineTextAlignment(.trailing)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                    if let duplicate {
                        ChickenRow(isLast: catalogURL == nil) {
                            Button {
                                router.updateDetailBook(duplicate.id)
                            } label: {
                                HStack {
                                    Text("Also in library")
                                        .font(.chickenUI(13.5))
                                        .foregroundStyle(palette.muted)
                                    Spacer(minLength: 16)
                                    Text("\(duplicate.format.label) edition")
                                        .font(.chickenUI(13.5, weight: .medium))
                                        .foregroundStyle(palette.ribbon)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(palette.faint)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if let catalogURL {
                        ChickenRow(isLast: true) {
                            Link(destination: catalogURL) {
                                HStack {
                                    Text(catalogURL.host()?.contains("hardcover") == true ? "View on Hardcover" : "View on Open Library")
                                        .font(.chickenUI(13.5, weight: .medium))
                                        .foregroundStyle(palette.ribbon)
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundStyle(palette.ribbon)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func moreMenu(for book: Book) -> some View {
        Menu {
            Button(book.isFinished ? "Mark as Unread" : "Mark as Finished", systemImage: book.isFinished ? "arrow.uturn.backward" : "checkmark.circle") {
                library.setFinished(!book.isFinished, for: book)
            }
            Button("Match Metadata…", systemImage: "text.magnifyingglass") {
                showingMetadataMatch = true
            }
            #if os(macOS)
            if !book.isPhysical && !book.storedFileName.isEmpty {
                Button("Show in Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([library.fileURL(for: book)])
                }
            }
            #endif
            if !book.isPhysical {
                DownloadMenuItems(book: book)
            }
            Divider()
            Button("Remove from Library…", systemImage: "trash", role: .destructive) {
                confirmingRemoval = true
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.text)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("More")
    }

    private func actionTitle(for book: Book) -> String {
        if book.isPhysical {
            return book.isFinished ? "Update Log" : "Log Progress"
        }
        if book.isFinished { return "Read Again" }
        return book.progress > 0 ? "Continue Reading" : "Begin Reading"
    }

    private func read(_ book: Book, jumpTo target: JumpTarget? = nil) {
        Haptics.impact(.light)
        openBook(book.id, from: nil, jumpTo: target)
    }
}
