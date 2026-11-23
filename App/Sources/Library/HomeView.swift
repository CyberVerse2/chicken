import ChickenKit
import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppRouter.self) private var router
    @Environment(\.palette) private var palette
    @Environment(\.readingTheme) private var theme
    @Environment(\.openBook) private var openBook
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Book.lastActivityAt, order: .reverse) private var books: [Book]
    @Query(sort: \Highlight.createdAt, order: .reverse) private var highlights: [Highlight]
    var onOpenProfile: (() -> Void)? = nil

    @State private var focusedBookID: UUID?
    @State private var focusedHue: CoverHue?

    private var isCompact: Bool { sizeClass == .compact }
    private var gutter: CGFloat { isCompact ? 20 : 40 }

    private struct DeskSections {
        let deskBooks: [Book]
        let isContinuing: Bool
        let sequels: [Book]
        let upNext: [Book]
        let quickReads: [Book]
        let recentlyFinished: [Book]
        let finishedThisYearCount: Int
        let featuredHighlight: (highlight: Highlight, book: Book)?
    }

    private var sections: DeskSections {
        let now = Date()
        let calendar = Calendar.current
        var activeReading: [Book] = []
        var unread: [Book] = []
        var finished: [Book] = []
        var finishedThisYear = 0

        for book in books {
            if book.isFinished {
                finished.append(book)
                if let finishedAt = book.finishedAt, calendar.isDate(finishedAt, equalTo: now, toGranularity: .year) {
                    finishedThisYear += 1
                }
            } else if book.progress > 0 || book.lastOpenedAt != nil {
                activeReading.append(book)
            } else {
                unread.append(book)
            }
        }

        let isContinuing = !activeReading.isEmpty
        let deskBooks: [Book]
        if isContinuing {
            deskBooks = Array(activeReading.prefix(6))
        } else if let latestUnread = unread.max(by: { lhs, rhs in
            if lhs.importedAt != rhs.importedAt { return lhs.importedAt < rhs.importedAt }
            return lhs.title > rhs.title
        }) {
            deskBooks = [latestUnread]
        } else if let firstBook = books.first {
            deskBooks = [firstBook]
        } else {
            deskBooks = []
        }

        let deskIDs = Set(deskBooks.map(\.id))

        var sequelIDs: Set<UUID> = []
        var sequels: [Book] = []
        for sourceBook in (finished + activeReading).prefix(12) {
            if let next = library.nextInSeries(after: sourceBook),
               !deskIDs.contains(next.id),
               next.progress == 0,
               sequelIDs.insert(next.id).inserted {
                sequels.append(next)
            }
        }

        let orderedUnread = unread
            .filter { !deskIDs.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.importedAt != rhs.importedAt { return lhs.importedAt > rhs.importedAt }
                return lhs.title < rhs.title
            }

        let quickReads = orderedUnread
            .filter { ($0.pageCount ?? 0) > 0 && ($0.pageCount ?? 0) <= 240 }
            .sorted { lhs, rhs in
                let lr = lhs.catalogRating ?? 0
                let rr = rhs.catalogRating ?? 0
                if lr != rr { return lr > rr }
                return lhs.importedAt > rhs.importedAt
            }

        let recentlyFinished = finished
            .filter { !deskIDs.contains($0.id) }
            .sorted { ($0.finishedAt ?? $0.lastActivityAt) > ($1.finishedAt ?? $1.lastActivityAt) }

        let featuredHighlight: (Highlight, Book)? = highlights.lazy.compactMap { highlight in
            guard let book = highlight.book else { return nil }
            return (highlight, book)
        }.first

        return DeskSections(
            deskBooks: deskBooks,
            isContinuing: isContinuing,
            sequels: Array(sequels.prefix(10)),
            upNext: Array(orderedUnread.prefix(16)),
            quickReads: Array(quickReads.prefix(12)),
            recentlyFinished: Array(recentlyFinished.prefix(12)),
            finishedThisYearCount: finishedThisYear,
            featuredHighlight: featuredHighlight
        )
    }

    private func resolvedFocusedBook(in s: DeskSections) -> Book? {
        if let focusedBookID, let match = s.deskBooks.first(where: { $0.id == focusedBookID }) {
            return match
        }
        return s.deskBooks.first
    }

    var body: some View {
        let s = sections
        let hero = resolvedFocusedBook(in: s)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ChickenScreenHeader(title: "Home") {
                    #if !os(macOS)
                    CircularGlassMenu(title: "Add Books", systemImage: "plus") {
                        AddBooksMenuItems()
                    }
                    #endif
                }
                .padding(.horizontal, gutter)
                .padding(.bottom, isCompact ? 18 : 22)

                if let summary = library.migrationSummary {
                    MigrationNotice(text: summary) { library.migrationSummary = nil }
                        .padding(.horizontal, gutter)
                        .padding(.bottom, 18)
                }

                if books.isEmpty {
                    EmptyLibraryView()
                        .padding(.horizontal, gutter)
                        .padding(.top, 8)
                } else {
                    if !s.deskBooks.isEmpty {
                        ReadingDeskHero(
                            books: s.deskBooks,
                            isContinuing: s.isContinuing,
                            focusedID: $focusedBookID,
                            gutter: gutter,
                            onRead: { book in
                                Haptics.impact(.light)
                                openBook(book.id, from: CoverSource(context: "hero", bookID: book.id))
                            },
                            onDetails: { book in
                                router.showDetails(book.id, in: s.deskBooks.map(\.id))
                            }
                        )
                    }

                    VStack(alignment: .leading, spacing: isCompact ? 30 : 38) {
                        pulseStripLink(finishedCount: s.finishedThisYearCount)
                            .padding(.horizontal, gutter)

                        if !s.sequels.isEmpty {
                            BookShelf(title: "Next in Series", books: s.sequels, gutter: gutter)
                        }

                        if !s.upNext.isEmpty {
                            BookShelf(
                                title: "Up Next",
                                books: s.upNext,
                                gutter: gutter,
                                actionLabel: s.upNext.count >= 6 ? "See All" : nil,
                                onAction: { router.openLibrary(scope: .unread) }
                            )
                        }

                        if s.quickReads.count >= 3 {
                            BookShelf(
                                title: "Quick Reads",
                                books: s.quickReads,
                                gutter: gutter,
                                actionLabel: "See All",
                                onAction: { router.openLibrary(scope: .all, secondaryFilter: .quickReads) }
                            )
                        }

                        if !s.recentlyFinished.isEmpty {
                            BookShelf(
                                title: "Recently Finished",
                                books: s.recentlyFinished,
                                gutter: gutter,
                                actionLabel: s.recentlyFinished.count >= 4 ? "See All" : nil,
                                onAction: { router.openLibrary(scope: .finished) }
                            )
                        }

                        if let featured = s.featuredHighlight {
                            HomePassageCard(
                                highlight: featured.highlight,
                                book: featured.book,
                                onOpen: {
                                    openBook(
                                        featured.book.id,
                                        jumpTo: JumpTarget(
                                            location: featured.highlight.location,
                                            chapterIndex: featured.highlight.chapterIndex
                                        )
                                    )
                                },
                                onDetails: {
                                    router.showDetails(featured.book.id, in: [featured.book.id])
                                }
                            )
                            .padding(.horizontal, gutter)
                        }
                    }
                    .padding(.top, isCompact ? 26 : 30)
                }
            }
            .padding(.top, isCompact ? 6 : 20)
            .padding(.bottom, 112)
            .frame(maxWidth: 1180, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                palette.background.ignoresSafeArea()
                if hero != nil {
                    HomeAtmosphereBackdrop(
                        coverHue: focusedHue ?? hero?.persistedCoverHue,
                        isCompact: isCompact
                    )
                    .frame(height: isCompact ? 540 : 460)
                    .ignoresSafeArea(edges: .top)
                }
            }
        }
        .pageTitle("Home")
        #if !os(macOS)
        .toolbar(isCompact ? .hidden : .automatic, for: .navigationBar)
        #else
        .toolbar {
            LibraryToolbar()
        }
        #endif
        .onAppear {
            if focusedBookID == nil {
                focusedBookID = s.deskBooks.first?.id
            }
        }
        .onChange(of: s.deskBooks.map(\.id)) { _, ids in
            if let focusedBookID, ids.contains(focusedBookID) { return }
            focusedBookID = ids.first
        }
        .task(id: "\(hero?.id.uuidString ?? "none")-\(hero?.coverImageName ?? "")-\(hero?.coverDominantHex ?? -1)") {
            guard let hero else {
                focusedHue = nil
                return
            }
            focusedHue = await CoverTintModifier.hue(for: hero, library: library)
        }
    }

    @ViewBuilder
    private func pulseStripLink(finishedCount: Int) -> some View {
        if let onOpenProfile {
            Button(action: onOpenProfile) {
                ReadingPulseStrip(
                    finishedCount: finishedCount,
                    annualGoal: library.preferences.annualBookGoal
                )
            }
            .buttonStyle(TactilePressStyle())
        } else {
            NavigationLink {
                ProfileView(isPushed: true)
            } label: {
                ReadingPulseStrip(
                    finishedCount: finishedCount,
                    annualGoal: library.preferences.annualBookGoal
                )
            }
            .buttonStyle(TactilePressStyle())
        }
    }
}

private struct HomeAtmosphereBackdrop: View {
    @Environment(\.palette) private var palette
    @Environment(\.readingTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let coverHue: CoverHue?
    let isCompact: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    (coverHue?.wash(for: theme) ?? palette.surfaceAlt).opacity(palette.isDark ? 0.50 : 0.52),
                    (coverHue?.wash(for: theme) ?? palette.surfaceAlt).opacity(palette.isDark ? 0.14 : 0.12),
                    palette.background,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [
                    (coverHue?.wash(for: theme) ?? palette.surfaceAlt).opacity(palette.isDark ? 0.28 : 0.20),
                    .clear,
                ],
                center: isCompact ? UnitPoint(x: 0.5, y: 0.34) : UnitPoint(x: 0.24, y: 0.45),
                startRadius: 24,
                endRadius: isCompact ? 280 : 420
            )
        }
        .animation(reduceMotion ? nil : ChickenMotion.theme, value: coverHue)
        .allowsHitTesting(false)
    }
}

private struct ReadingDeskHero: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let books: [Book]
    let isContinuing: Bool
    @Binding var focusedID: UUID?
    let gutter: CGFloat
    let onRead: (Book) -> Void
    let onDetails: (Book) -> Void

    private var isCompact: Bool { sizeClass == .compact }
    private var showsTitleText: Bool { library.preferences.showCoverTitles || typeSize.isAccessibilitySize }

    private var activeBook: Book {
        if let focusedID, let match = books.first(where: { $0.id == focusedID }) {
            return match
        }
        return books[0]
    }

    var body: some View {
        if isCompact {
            VStack(spacing: 14) {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(books) { book in
                            compactDeskCard(for: book)
                                .containerRelativeFrame(.horizontal)
                                .id(book.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.never)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $focusedID)

                if books.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(books) { book in
                            let selected = book.id == activeBook.id
                            Capsule()
                                .fill(selected ? palette.text : palette.borderStrong)
                                .frame(width: selected ? 18 : 6, height: 6)
                                .animation(reduceMotion ? nil : ChickenMotion.snappy, value: activeBook.id)
                                .onTapGesture {
                                    withAnimation(reduceMotion ? nil : ChickenMotion.standard) {
                                        focusedID = book.id
                                    }
                                }
                        }
                    }
                    .padding(.top, 2)
                }
            }
        } else {
            regularDeskStage(for: activeBook)
                .padding(.horizontal, gutter)
        }
    }

    private func compactDeskCard(for book: Book) -> some View {
        VStack(spacing: 0) {
            sculptedCover(book: book, width: 184)
                .padding(.bottom, 18)

            if showsTitleText {
                VStack(spacing: 4) {
                    if let seriesBadge = book.seriesBadgeText {
                        Text(seriesBadge)
                            .chickenEyebrow(palette, color: palette.ribbon)
                            .lineLimit(1)
                    }
                    Text(book.displayTitle)
                        .font(.chickenDisplay(22))
                        .tracking(-0.4)
                        .foregroundStyle(palette.text)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                    if let author = book.author, !author.isEmpty {
                        Text(author)
                            .font(.chickenSerif(14.5, italic: true))
                            .foregroundStyle(palette.muted)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: 280)
                .padding(.bottom, 12)
            } else if let seriesBadge = book.seriesBadgeText {
                Text(seriesBadge)
                    .chickenEyebrow(palette, color: palette.ribbon)
                    .lineLimit(1)
                    .padding(.bottom, 10)
            }

            if isContinuing {
                VStack(spacing: 6) {
                    ProgressLine(progress: book.progress, height: 3)
                    HStack(spacing: 6) {
                        Text("\(Int((book.progress * 100).rounded()))%")
                            .foregroundStyle(palette.text)
                            .fontWeight(.semibold)
                        if let chapter = book.lastChapterTitle, !chapter.isEmpty, chapter != book.title {
                            Text("·").foregroundStyle(palette.faint)
                            Text(chapter).lineLimit(1)
                        } else if let left = book.estimatedPagesLeft {
                            Text("·").foregroundStyle(palette.faint)
                            Text(ReadingEstimate.duration(forPages: left, minutesPerPage: library.preferences.minutesPerPage) + " left")
                        }
                    }
                    .font(.chickenMono(11.5))
                    .foregroundStyle(palette.muted)
                }
                .frame(maxWidth: 240)
                .padding(.bottom, 18)
            } else if let pages = book.pageCount, pages > 0 {
                Text("\(pages) pages · \(ReadingEstimate.duration(forPages: pages, minutesPerPage: library.preferences.minutesPerPage))")
                    .font(.chickenMono(11.5))
                    .foregroundStyle(palette.muted)
                    .padding(.bottom, 18)
            }

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    PrimaryHeroButton(
                        title: primaryButtonTitle(for: book),
                        systemImage: book.isPhysical ? "book.closed" : "arrow.right",
                        height: 48,
                        action: { onRead(book) }
                    )

                    CircularGlassButton(
                        title: "Details",
                        systemImage: "info",
                        diameter: 48,
                        iconSize: 19,
                        action: { onDetails(book) }
                    )
                }
            }
            .frame(maxWidth: 290)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, gutter)
        .bookContextMenu(book)
    }

    private func regularDeskStage(for book: Book) -> some View {
        HStack(alignment: .center, spacing: 40) {
            sculptedCover(book: book, width: 216)

            VStack(alignment: .leading, spacing: 0) {
                if let seriesBadge = book.seriesBadgeText {
                    Text(seriesBadge)
                        .chickenEyebrow(palette, color: palette.ribbon)
                        .padding(.bottom, showsTitleText ? 6 : 12)
                }

                if showsTitleText {
                    Text(book.displayTitle)
                        .font(.chickenDisplay(36))
                        .tracking(-0.8)
                        .foregroundStyle(palette.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .padding(.bottom, 6)

                    if let author = book.author, !author.isEmpty {
                        Text(book.releaseYear.map { "\(author) · \($0)" } ?? author)
                            .font(.chickenSerif(17, italic: true))
                            .foregroundStyle(palette.muted)
                            .lineLimit(1)
                            .padding(.bottom, 20)
                    } else {
                        Spacer().frame(height: 16)
                    }
                }

                if isContinuing {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressLine(progress: book.progress, height: 3.5)
                        HStack(spacing: 6) {
                            Text("\(Int((book.progress * 100).rounded()))%")
                                .foregroundStyle(palette.text)
                                .fontWeight(.semibold)
                            if let chapter = book.lastChapterTitle, !chapter.isEmpty, chapter != book.title {
                                Text("·")
                                Text(chapter).lineLimit(1)
                            } else if let pages = book.pageCount, pages > 0 {
                                Text("·")
                                Text("p. \(max(1, Int((Double(pages) * book.progress).rounded()))) of \(pages)")
                            }
                            Spacer(minLength: 8)
                            if let left = book.estimatedPagesLeft {
                                Text(ReadingEstimate.duration(forPages: left, minutesPerPage: library.preferences.minutesPerPage) + " left")
                            }
                        }
                        .font(.chickenMono(12.5))
                        .foregroundStyle(palette.muted)
                    }
                    .frame(maxWidth: 420)
                    .padding(.bottom, 22)
                } else if let pages = book.pageCount, pages > 0 {
                    Text("\(pages) pages · \(ReadingEstimate.duration(forPages: pages, minutesPerPage: library.preferences.minutesPerPage))")
                        .font(.chickenMono(12.5))
                        .foregroundStyle(palette.muted)
                        .padding(.bottom, 22)
                }

                HStack(spacing: 12) {
                    PrimaryHeroButton(
                        title: primaryButtonTitle(for: book),
                        systemImage: book.isPhysical ? "book.closed" : "arrow.right",
                        height: 46,
                        action: { onRead(book) }
                    )
                    .frame(maxWidth: 240)

                    CircularGlassButton(
                        title: "Details",
                        systemImage: "info",
                        diameter: 46,
                        iconSize: 18,
                        action: { onDetails(book) }
                    )
                }

                if books.count > 1 {
                    HStack(spacing: 10) {
                        ForEach(books) { candidate in
                            let selected = candidate.id == book.id
                            Button {
                                Haptics.selection()
                                withAnimation(reduceMotion ? nil : ChickenMotion.standard) {
                                    focusedID = candidate.id
                                }
                            } label: {
                                BookCover(book: candidate, style: .mini)
                                    .frame(width: 34, height: (34 / candidate.resolvedAspectRatio).rounded())
                                    .opacity(selected ? 1 : 0.52)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                            .stroke(selected ? palette.ribbon : .clear, lineWidth: 1.5)
                                    }
                                    .shadow(color: palette.shadow, radius: selected ? 6 : 2, y: 2)
                            }
                            .buttonStyle(TactilePressStyle(scale: 0.95))
                            .help(candidate.displayTitle)
                        }
                    }
                    .padding(.top, 20)
                }
            }
            Spacer(minLength: 0)
        }
        .bookContextMenu(book)
    }

    private func primaryButtonTitle(for book: Book) -> String {
        if book.isPhysical {
            return book.isFinished ? "Update Log" : "Log Progress"
        }
        return isContinuing ? "Continue Reading" : "Begin Reading"
    }

    private func sculptedCover(book: Book, width: CGFloat) -> some View {
        DeskSculptedCover(book: book, width: width, isContinuing: isContinuing, isCompact: isCompact) {
            onRead(book)
        }
    }
}

private struct DeskSculptedCover: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let book: Book
    let width: CGFloat
    let isContinuing: Bool
    let isCompact: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let coverHeight = min((width / book.resolvedAspectRatio).rounded(), width * 1.65)
        Button(action: action) {
            BookCover(book: book, style: isCompact ? .tile : .hero, showsClothText: true)
                .frame(width: width, height: coverHeight)
                .coverTransitionSource(book.id)
                .shadow(color: .black.opacity(palette.isDark ? 0.55 : 0.22), radius: 3, x: 0, y: 2)
                .shadow(color: palette.shadow, radius: hovering ? 28 : 18, x: 0, y: hovering ? 18 : 12)
                .coverRibbon(isContinuing, length: width * 0.18, width: max(11, width * 0.08))
                #if os(macOS)
                .rotation3DEffect(
                    .degrees(hovering && !reduceMotion ? -6 : 0),
                    axis: (x: 0, y: 1, z: 0),
                    anchor: .leading,
                    perspective: 0.6
                )
                #endif
        }
        .buttonStyle(TactilePressStyle())
        #if os(macOS)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : ChickenMotion.standard, value: hovering)
        .help("\(book.displayTitle) — \(book.displayAuthor)")
        #endif
        .accessibilityLabel("Continue reading \(book.displayTitle)")
    }
}

private struct HomePassageCard: View {
    @Environment(\.palette) private var palette
    let highlight: Highlight
    let book: Book
    let onOpen: () -> Void
    let onDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ShelfSectionHeader(title: "From Your Notebook", actionLabel: "Book", action: onDetails)

            Button(action: onOpen) {
                HStack(alignment: .top, spacing: 14) {
                    BookCover(book: book, style: .mini)
                        .frame(width: 44, height: (44 / book.resolvedAspectRatio).rounded())
                        .shadow(color: palette.shadow, radius: 4, y: 2)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("\u{201C}\(highlight.text)\u{201D}")
                            .font(.chickenSerif(15.5))
                            .foregroundStyle(palette.text)
                            .lineSpacing(5)
                            .lineLimit(4)
                            .multilineTextAlignment(.leading)
                        Text(book.displayTitle)
                            .font(.chickenUI(12, weight: .medium))
                            .foregroundStyle(palette.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(palette.surface)
                        .stroke(palette.border, lineWidth: 0.5)
                )
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(TactilePressStyle(scale: 0.99))
        }
    }
}

private struct ReadingPulseStrip: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.palette) private var palette
    let finishedCount: Int
    let annualGoal: Int

    private var minutesToday: Int { library.readingSecondsToday / 60 }
    private var dailyGoal: Int { library.preferences.dailyGoalMinutes }
    private var dailyFraction: Double {
        dailyGoal > 0 ? min(1, Double(library.readingSecondsToday) / Double(dailyGoal * 60)) : 0
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(palette.surfaceAlt, lineWidth: 4.5)
                if library.readingSecondsToday > 0 {
                    Circle()
                        .trim(from: 0, to: max(0.04, dailyFraction))
                        .stroke(palette.ribbon, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Text("\(minutesToday)")
                    .font(.chickenMono(13, weight: .semibold))
                    .foregroundStyle(palette.text)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text("Today · \(minutesToday) of \(dailyGoal) min")
                    .font(.chickenUI(14, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .monospacedDigit()
                Text("\(finishedCount) of \(annualGoal) books this year")
                    .font(.chickenUI(12))
                    .foregroundStyle(palette.muted)
                    .monospacedDigit()
            }

            Spacer(minLength: 8)

            weekBars

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.faint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(palette.surface)
                .stroke(palette.border, lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens Profile")
    }

    private var weekBars: some View {
        let days = library.lastSevenDays
        let goalSeconds = dailyGoal * 60
        let scale = max(goalSeconds, days.map(\.seconds).max() ?? 0, 60)
        return HStack(alignment: .bottom, spacing: 4) {
            ForEach(days) { day in
                RoundedRectangle(cornerRadius: 2)
                    .fill(day.isToday ? palette.ribbon : (day.seconds > 0 ? palette.muted.opacity(0.45) : palette.surfaceAlt))
                    .frame(
                        width: 5,
                        height: day.seconds == 0 ? 4 : max(6, 26 * min(1, Double(day.seconds) / Double(scale)))
                    )
            }
        }
        .frame(height: 26, alignment: .bottom)
    }
}

struct BookShelf: View {
    @Environment(\.palette) private var palette
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let books: [Book]
    let gutter: CGFloat
    var showsProgress = false
    var actionLabel: String? = nil
    var onAction: (() -> Void)? = nil
    @State private var position = ScrollPosition(edge: .leading)
    @State private var scroll = ShelfScroll()
    @State private var hovering = false

    private var shelfHeight: CGFloat { sizeClass == .compact ? 192 : 236 }
    private var headroom: CGFloat { Platform.isMac ? 8 : 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14 - headroom) {
            ShelfSectionHeader(
                title: title,
                count: books.count,
                actionLabel: actionLabel,
                action: onAction
            )
            .padding(.horizontal, gutter)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .bottom, spacing: sizeClass == .compact ? 16 : 24) {
                    ForEach(books) { book in
                        BookObjectView(
                            book: book,
                            surface: .shelf,
                            shelfHeight: shelfHeight,
                            showsProgressOverlay: showsProgress || book.progress > 0
                        )
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.never)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition($position)
            .onScrollGeometryChange(for: ShelfScroll.self) { geometry in
                ShelfScroll(
                    offset: geometry.contentOffset.x + geometry.contentInsets.leading,
                    visible: geometry.containerSize.width,
                    content: geometry.contentSize.width + geometry.contentInsets.leading + geometry.contentInsets.trailing
                )
            } action: { _, new in
                scroll = new
            }
            .contentMargins(.horizontal, gutter, for: .scrollContent)
            .contentMargins(.top, headroom, for: .scrollContent)
            .scrollClipDisabled(!Platform.isMac)
            #if os(macOS)
            .overlay { pageButtons }
            .onHover { hovering = $0 }
            #endif
            .coverCollection("shelf-\(title)", books: books.map(\.id))
        }
    }

    #if os(macOS)
    private var pageButtons: some View {
        HStack {
            pageButton(systemImage: "chevron.left", label: "Scroll back", enabled: scroll.canGoBack) {
                page(by: -1)
            }
            Spacer()
            pageButton(systemImage: "chevron.right", label: "Scroll forward", enabled: scroll.canGoForward) {
                page(by: 1)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: shelfHeight)
        .padding(.top, headroom)
        .frame(maxHeight: .infinity, alignment: .top)
        .opacity(hovering ? 1 : 0)
        .animation(reduceMotion ? nil : ChickenMotion.micro, value: hovering)
    }

    private func pageButton(systemImage: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        CircularGlassButton(
            title: label,
            systemImage: systemImage,
            diameter: 40,
            iconSize: 16,
            action: action
        )
        .opacity(enabled ? 1 : 0)
        .allowsHitTesting(enabled)
    }

    private func page(by direction: CGFloat) {
        let stepWidth = shelfHeight * 0.67
        let step = max(scroll.visible - stepWidth, stepWidth)
        let target = min(max(0, scroll.offset + direction * step), max(0, scroll.content - scroll.visible))
        withAnimation(reduceMotion ? nil : ChickenMotion.standard) { position.scrollTo(x: target) }
    }
    #endif
}

nonisolated struct ShelfScroll: Equatable {
    var offset: CGFloat = 0
    var visible: CGFloat = 0
    var content: CGFloat = 0

    var canGoBack: Bool { offset > 2 }
    var canGoForward: Bool { offset + visible < content - 2 }
}

struct MigrationNotice: View {
    @Environment(\.palette) private var palette
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            BrandBadge(size: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome back")
                    .font(.chickenDisplay(16))
                    .foregroundStyle(palette.text)
                Text(text)
                    .font(.chickenUI(13))
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            CircularGlassButton(
                title: "Dismiss",
                systemImage: "xmark",
                diameter: 34,
                iconSize: 13.5,
                foreground: palette.muted,
                action: onDismiss
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(palette.surface)
                .stroke(palette.border, lineWidth: 0.5)
        )
    }
}

struct ActivityToast: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingErrors = false
    @State private var dismissedMessage: String?
    @State private var dragOffset: CGFloat = 0

    private var visibleMessage: String? {
        guard let message, message != dismissedMessage else { return nil }
        return message
    }

    var body: some View {
        Group {
            if let message = visibleMessage {
                HStack(spacing: 10) {
                    if isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(palette.ribbon)
                    }
                    Text(message)
                        .font(.chickenUI(13, weight: .medium))
                        .monospacedDigit()
                    if !library.importErrors.isEmpty, !isWorking {
                        Button("Details") { showingErrors = true }
                            .font(.chickenUI(13, weight: .semibold))
                            .buttonStyle(TactilePressStyle(scale: 0.95))
                            .foregroundStyle(palette.muted)
                    }
                }
                .foregroundStyle(palette.text)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .glassEffect(.regular, in: .capsule)
                .offset(y: max(0, dragOffset))
                .gesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { value in
                            if !isWorking {
                                dragOffset = max(0, value.translation.height)
                            }
                        }
                        .onEnded { value in
                            let velocity = value.predictedEndTranslation.height - value.translation.height
                            if !isWorking && (value.translation.height > 28 || velocity > 180) {
                                dismissedMessage = message
                            }
                            withAnimation(reduceMotion ? nil : ChickenMotion.snappy) {
                                dragOffset = 0
                            }
                        }
                )
                .padding(.bottom, 92)
                .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(reduceMotion ? nil : ChickenMotion.standard, value: visibleMessage)
        .onChange(of: message) { _, newValue in
            if newValue != dismissedMessage { dismissedMessage = nil }
        }
        .alert("Import notes", isPresented: $showingErrors) {
            Button("OK") { library.importErrors = [] }
        } message: {
            Text(library.importErrors.prefix(8).joined(separator: "\n"))
        }
    }

    private var isWorking: Bool {
        library.importState.isImporting || library.coverRefreshState.isRefreshing || library.catalogEnrichState.isEnriching
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
            break
        }
        switch library.catalogEnrichState {
        case .enriching(let completed, let total):
            return "Fetching metadata \(completed) of \(total)"
        case .finished(let updated):
            guard updated > 0 else { return nil }
            return updated == 1 ? "Updated 1 book" : "Updated \(updated) books"
        case .idle:
            return nil
        }
    }
}
