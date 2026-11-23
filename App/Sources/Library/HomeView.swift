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
    var onOpenProfile: (() -> Void)? = nil

    @State private var heroHue: CoverHue?

    private var isCompact: Bool { sizeClass == .compact }
    private var gutter: CGFloat { isCompact ? 20 : 40 }

    private struct DerivedSections {
        let activeBook: Book?
        let featuredBook: Book?
        let deskBooks: [Book]
        let upNext: [Book]
        let quickReads: [Book]
        let finishedThisYearCount: Int
    }

    private var sections: DerivedSections {
        let now = Date()
        let calendar = Calendar.current
        var active: Book?
        var unfinished: [Book] = []
        var finishedRecent: [Book] = []
        var finishedCount = 0

        for book in books {
            if book.isFinished {
                finishedRecent.append(book)
                if let finishedAt = book.finishedAt, calendar.isDate(finishedAt, equalTo: now, toGranularity: .year) {
                    finishedCount += 1
                }
            } else {
                if active == nil && book.lastOpenedAt != nil {
                    active = book
                }
                unfinished.append(book)
            }
        }

        let featured = active ?? unfinished.max(by: { lhs, rhs in
            if lhs.importedAt != rhs.importedAt { return lhs.importedAt < rhs.importedAt }
            return lhs.title > rhs.title
        }) ?? books.first

        let featuredID = featured?.id
        var desk: [Book] = []
        var nextCandidates: [Book] = []
        var quickCandidates: [Book] = []
        for book in unfinished where book.id != featuredID {
            if book.progress > 0 {
                desk.append(book)
            } else {
                nextCandidates.append(book)
                if let pages = book.pageCount, pages > 0, pages <= 250 {
                    quickCandidates.append(book)
                }
            }
        }
        var sequelIDs: Set<UUID> = []
        var sequels: [Book] = []
        for doneBook in finishedRecent.prefix(8) {
            if let sequel = library.nextInSeries(after: doneBook),
               sequel.id != featuredID,
               sequel.progress == 0,
               sequelIDs.insert(sequel.id).inserted {
                sequels.append(sequel)
            }
        }
        nextCandidates.sort { lhs, rhs in
            if lhs.importedAt != rhs.importedAt { return lhs.importedAt > rhs.importedAt }
            return lhs.title < rhs.title
        }
        let orderedNext = sequels + nextCandidates.filter { !sequelIDs.contains($0.id) }
        quickCandidates.sort { lhs, rhs in
            let lr = lhs.catalogRating ?? 0
            let rr = rhs.catalogRating ?? 0
            if lr != rr { return lr > rr }
            return lhs.importedAt > rhs.importedAt
        }

        return DerivedSections(
            activeBook: active,
            featuredBook: featured,
            deskBooks: desk,
            upNext: Array(orderedNext.prefix(16)),
            quickReads: Array(quickCandidates.prefix(12)),
            finishedThisYearCount: finishedCount
        )
    }

    var body: some View {
        let s = sections
        let hero = s.featuredBook
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let summary = library.migrationSummary {
                    MigrationNotice(text: summary) { library.migrationSummary = nil }
                        .padding(.horizontal, gutter)
                        .padding(.top, 12)
                        .padding(.bottom, 16)
                }

                if books.isEmpty {
                    EmptyLibraryView()
                        .padding(.horizontal, gutter)
                        .padding(.top, 20)
                } else if let hero {
                    ReadingDeskStage(
                        book: hero,
                        isContinuing: s.activeBook != nil,
                        coverHue: heroHue,
                        gutter: gutter,
                        onRead: {
                            Haptics.impact(.light)
                            openBook(hero.id, from: CoverSource(context: "hero", bookID: hero.id))
                        },
                        onDetails: {
                            router.showDetails(hero.id, in: [hero.id])
                        }
                    )

                    VStack(alignment: .leading, spacing: isCompact ? 34 : 42) {
                        if !s.deskBooks.isEmpty {
                            BookShelf(title: "Also reading", books: s.deskBooks, gutter: gutter, showsProgress: true)
                        }

                        if !s.upNext.isEmpty {
                            BookShelf(title: "Up next", books: s.upNext, gutter: gutter)
                        }

                        if s.quickReads.count >= 2 {
                            BookShelf(title: "Quick reads", books: s.quickReads, gutter: gutter)
                        }

                        NavigationLink {
                            ProfileView()
                        } label: {
                            ReadingPulseStrip(
                                finishedCount: s.finishedThisYearCount,
                                annualGoal: library.preferences.annualBookGoal
                            )
                        }
                        .buttonStyle(TactilePressStyle())
                        .padding(.horizontal, gutter)
                    }
                    .padding(.top, isCompact ? 48 : 36)
                }
            }
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
                    HomeAtmosphereBackdrop(coverHue: heroHue, isCompact: isCompact)
                        .frame(height: isCompact ? 560 : 460)
                        .ignoresSafeArea(edges: .top)
                }
            }
        }
        .pageTitle("Home")
        .task(id: "\(hero?.id.uuidString ?? "none")-\(hero?.coverImageName ?? "")") {
            guard let hero else {
                heroHue = nil
                return
            }
            heroHue = await CoverTintModifier.hue(for: hero, library: library)
        }
        .toolbar {
            LibraryToolbar(onOpenProfile: onOpenProfile)
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
                    (coverHue?.wash(for: theme) ?? palette.surfaceAlt).opacity(palette.isDark ? 0.52 : 0.54),
                    (coverHue?.wash(for: theme) ?? palette.surfaceAlt).opacity(palette.isDark ? 0.14 : 0.12),
                    palette.background,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [
                    (coverHue?.wash(for: theme) ?? palette.surfaceAlt).opacity(palette.isDark ? 0.30 : 0.22),
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

private struct ReadingDeskStage: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.palette) private var palette
    @Environment(\.readingTheme) private var theme
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let book: Book
    let isContinuing: Bool
    let coverHue: CoverHue?
    let gutter: CGFloat
    let onRead: () -> Void
    let onDetails: () -> Void

    @State private var hovering = false

    private var isCompact: Bool { sizeClass == .compact }

    private var heroPrimaryTitle: String {
        if book.isPhysical {
            return book.isFinished ? "Update Log" : "Log Progress"
        }
        return isContinuing ? "Continue Reading" : "Begin Reading"
    }

    var body: some View {
        Group {
            if isCompact { compactStage } else { regularStage }
        }
        .padding(.horizontal, gutter)
        .padding(.top, isCompact ? 18 : 24)
        .padding(.bottom, isCompact ? 6 : 24)
        .bookContextMenu(book)
    }

    private var compactStage: some View {
        VStack(spacing: 0) {
            sculptedCover(width: 158)
                .padding(.bottom, 22)

            if book.coverImageName == nil {
                VStack(spacing: 5) {
                    if let seriesBadge = book.seriesBadgeText {
                        Text(seriesBadge)
                            .chickenEyebrow(palette, color: palette.ribbon)
                            .lineLimit(1)
                    }
                    Text(book.displayTitle)
                        .font(.chickenDisplay(24))
                        .tracking(-0.5)
                        .foregroundStyle(palette.text)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .fixedSize(horizontal: false, vertical: true)

                    if let author = book.author, !author.isEmpty {
                        Text(book.releaseYear.map { "\(author) · \($0)" } ?? author)
                            .font(.chickenSerif(15.5, italic: true))
                            .foregroundStyle(palette.muted)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: 300)
                .padding(.bottom, 16)
            } else if let seriesBadge = book.seriesBadgeText {
                Text(seriesBadge)
                    .chickenEyebrow(palette, color: palette.ribbon)
                    .lineLimit(1)
                    .padding(.bottom, 12)
            }

            if isContinuing {
                VStack(spacing: 7) {
                    ProgressLine(progress: book.progress, height: 3)
                    HStack(spacing: 6) {
                        Text("\(Int((book.progress * 100).rounded()))%")
                            .foregroundStyle(palette.text)
                            .fontWeight(.semibold)
                        if let left = book.estimatedPagesLeft {
                            Text("·")
                                .foregroundStyle(palette.faint)
                            Text(ReadingEstimate.duration(forPages: left, minutesPerPage: library.preferences.minutesPerPage) + " left")
                        }
                    }
                    .font(.chickenMono(11.5))
                    .foregroundStyle(palette.muted)
                }
                .frame(maxWidth: 210)
                .padding(.bottom, 22)
            } else if let pages = book.pageCount, pages > 0 {
                Text("\(pages) pages · \(ReadingEstimate.duration(forPages: pages, minutesPerPage: library.preferences.minutesPerPage))")
                    .font(.chickenMono(11.5))
                    .foregroundStyle(palette.muted)
                    .padding(.bottom, 22)
            }

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    PrimaryHeroButton(
                        title: heroPrimaryTitle,
                        systemImage: book.isPhysical ? "book.closed" : "arrow.right",
                        height: 50,
                        action: onRead
                    )

                    CircularGlassButton(
                        title: "Details",
                        systemImage: "info",
                        diameter: 50,
                        iconSize: 20,
                        action: onDetails
                    )
                }
            }
            .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity)
    }

    private var regularStage: some View {
        HStack(alignment: .center, spacing: 44) {
            sculptedCover(width: 196)

            VStack(alignment: .leading, spacing: 0) {
                if let seriesBadge = book.seriesBadgeText {
                    Text(seriesBadge)
                        .chickenEyebrow(palette, color: palette.ribbon)
                        .padding(.bottom, book.coverImageName == nil ? 6 : 14)
                }
                if book.coverImageName == nil {
                    Text(book.displayTitle)
                        .font(.chickenDisplay(38))
                        .tracking(-0.9)
                        .foregroundStyle(palette.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 6)

                    if let author = book.author, !author.isEmpty {
                        Text(book.releaseYear.map { "\(author) · \($0)" } ?? author)
                            .font(.chickenSerif(18, italic: true))
                            .foregroundStyle(palette.muted)
                            .lineLimit(1)
                            .padding(.bottom, 24)
                    } else {
                        Spacer().frame(height: 18)
                    }
                }

                if isContinuing {
                    regularProgress
                        .frame(maxWidth: 440)
                        .padding(.bottom, 26)
                }

                HStack(spacing: 12) {
                    PrimaryHeroButton(
                        title: heroPrimaryTitle,
                        systemImage: book.isPhysical ? "book.closed" : "arrow.right",
                        height: 46,
                        action: onRead
                    )
                    .frame(maxWidth: 240)
                    CircularGlassButton(
                        title: "Details",
                        systemImage: "info",
                        diameter: 46,
                        iconSize: 18,
                        action: onDetails
                    )
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func sculptedCover(width: CGFloat) -> some View {
        Button(action: onRead) {
            BookCover(book: book, style: isCompact ? .tile : .hero, showsClothText: true)
                .frame(width: width, height: width * 1.5)
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
        #endif
        .accessibilityLabel("Continue reading \(book.displayTitle)")
    }

    private var regularProgress: some View {
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
        .accessibilityHint("Opens Your Reading")
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
    @State private var position = ScrollPosition(edge: .leading)
    @State private var scroll = ShelfScroll()
    @State private var hovering = false

    private var coverWidth: CGFloat { sizeClass == .compact ? 112 : 136 }
    private var headroom: CGFloat { Platform.isMac ? 8 : 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14 - headroom) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.chickenDisplay(sizeClass == .compact ? 19 : 21))
                    .tracking(-0.3)
                    .foregroundStyle(palette.text)
                Spacer(minLength: 8)
                Text("\(books.count)")
                    .font(.chickenMono(11.5, weight: .medium))
                    .foregroundStyle(palette.faint)
            }
            .padding(.horizontal, gutter)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: sizeClass == .compact ? 16 : 24) {
                    ForEach(books) { book in
                        ShelfItem(book: book, width: coverWidth, showsProgress: showsProgress)
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
        .frame(height: coverWidth * 1.5)
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
        let step = max(scroll.visible - coverWidth, coverWidth)
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

private struct ShelfItem: View {
    @Environment(\.palette) private var palette
    @Environment(\.coverContext) private var coverContext
    @Environment(\.bookSequence) private var bookSequence
    @Environment(\.selectBook) private var selectBook
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let book: Book
    let width: CGFloat
    let showsProgress: Bool
    @State private var hovering = false

    private var inProgress: Bool { book.progress > 0 && !book.isFinished }

    var body: some View {
        Button {
            Haptics.selection()
            selectBook(book.id, in: bookSequence, from: CoverSource(context: coverContext, bookID: book.id))
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                BookCover(book: book, style: .tile)
                    .frame(width: width, height: width * 1.5)
                    .coverTransitionSource(book.id)
                    .downloadBadge(book)
                    .shadow(color: palette.shadow, radius: hovering ? 14 : 6, x: 0, y: hovering ? 8 : 4)
                    #if os(macOS)
                    .offset(y: hovering && !reduceMotion ? -4 : 0)
                    #endif
                    .coverRibbon(inProgress)
                if book.coverImageName == nil || showsProgress {
                    VStack(alignment: .leading, spacing: 2) {
                        if book.coverImageName == nil {
                            Text(book.displayTitle)
                                .font(.chickenUI(13.5, weight: .semibold))
                                .foregroundStyle(palette.text)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            if let author = book.author, !author.isEmpty {
                                Text(author)
                                    .font(.chickenUI(12))
                                    .foregroundStyle(palette.muted)
                                    .lineLimit(1)
                            }
                        }
                        if showsProgress {
                            HStack(spacing: 6) {
                                ProgressLine(progress: book.progress, height: 2.5)
                                Text("\(Int((book.progress * 100).rounded()))%")
                                    .font(.chickenMono(10.5, weight: .medium))
                                    .foregroundStyle(palette.ribbon)
                                    .fixedSize()
                            }
                            .padding(.top, 3)
                        }
                    }
                }
            }
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(TactilePressStyle())
        #if os(macOS)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : ChickenMotion.micro, value: hovering)
        #endif
        .bookContextMenu(book)
        .accessibilityLabel("\(book.displayTitle) by \(book.displayAuthor)")
    }
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
