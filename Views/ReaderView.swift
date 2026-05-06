import AppKit
import PDFKit
import SwiftUI
import WebKit

// MARK: - Reader root

struct ReaderView: View {
    @EnvironmentObject private var library: LocalLibraryStore
    let book: Book
    let onClose: () -> Void

    @State private var chapterIndex: Int = 0
    @State private var bodyState = ReaderBodyState()
    @State private var selection: ReaderSelection?
    @State private var fontSize: CGFloat = 17
    @State private var lineHeight: CGFloat = 1.78
    @State private var columnWidth: CGFloat = 620
    @State private var showChapters = true
    @State private var showHighlights = false
    @State private var showTypography = false
    @State private var showSearch = false
    @State private var searchQuery = ""
    @State private var searchRequest: ReaderSearchRequest?
    @State private var chromeDimmed = false
    @State private var isZenMode = false
    @State private var readingMode: EPUBReadingMode = .scroll
    @State private var currentLocation: String?

    private var palette: ReaderPalette { library.readingTheme.palette }
    private var bookHighlights: [Highlight] { library.highlights(for: book) }
    private var chapterHighlights: [Highlight] {
        library.highlights(for: book, chapterIndex: chapterIndex)
    }

    var body: some View {
        VStack(spacing: 0) {
            ReaderTopBar(
                palette: palette,
                book: book,
                chapterTitle: bodyState.chapterTitle(at: chapterIndex),
                chapterCount: bodyState.chapters.count,
                chapterIndex: chapterIndex,
                showChapters: $showChapters,
                showHighlights: $showHighlights,
                showTypography: $showTypography,
                showSearch: $showSearch,
                isZenMode: $isZenMode,
                theme: $library.readingTheme,
                isBookmarked: library.hasBookmark(book: book, chapterIndex: chapterIndex),
                onToggleBookmark: {
                    _ = library.toggleBookmark(
                        book: book,
                        chapterIndex: chapterIndex,
                        title: bodyState.chapterTitle(at: chapterIndex),
                        location: currentLocation ?? book.lastLocation
                    )
                },
                onClose: onClose
            )
            .opacity(chromeDimmed && !hasDismissibleReaderChrome ? 0.34 : 1)

            ZStack(alignment: .bottom) {
                HStack(spacing: 0) {
                    if showChapters && !isZenMode {
                        ChaptersPanel(
                            palette: palette,
                            chapters: bodyState.chapters,
                            selectedIndex: $chapterIndex
                        )
                        .frame(width: 220)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    }

                    ZStack(alignment: .topTrailing) {
                        ReaderBody(
                            book: book,
                            palette: palette,
                            chapterIndex: $chapterIndex,
                            bodyState: $bodyState,
                            selection: $selection,
                            highlights: chapterHighlights,
                            fontSize: fontSize,
                            lineHeight: lineHeight,
                            columnWidth: columnWidth,
                            readingMode: readingMode,
                            searchRequest: searchRequest,
                            onLocationChange: { currentLocation = $0 }
                        )

                        if hasDismissibleReaderChrome {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { dismissReaderChrome() }
                                .transition(.opacity)
                        }

                        if showTypography {
                            TypographyPopover(
                                palette: palette,
                                fontSize: $fontSize,
                                lineHeight: $lineHeight,
                                columnWidth: $columnWidth,
                                readingMode: $readingMode,
                                supportsFlow: book.format == .epub || book.format == .pdf,
                                theme: $library.readingTheme,
                                onClose: { showTypography = false },
                                onReset: {
                                    fontSize = 17
                                    lineHeight = 1.78
                                    columnWidth = 620
                                }
                            )
                            .padding(16)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        if showSearch {
                            ReaderSearchPopover(
                                palette: palette,
                                query: $searchQuery,
                                onPrevious: { submitSearch(backwards: true) },
                                onNext: { submitSearch(backwards: false) },
                                onClose: { showSearch = false }
                            )
                            .padding(16)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if showHighlights && !isZenMode {
                        HighlightsPanel(
                            palette: palette,
                            book: book,
                            bookHighlights: bookHighlights,
                            bookBookmarks: library.bookmarks(for: book),
                            bodyState: bodyState,
                            onJumpTo: { chapterIndex = $0 }
                        )
                        .frame(width: 280)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }

                if !isZenMode {
                    ReaderBottomBar(
                        palette: palette,
                        progress: bodyState.progress(at: chapterIndex),
                        pageReadout: bodyState.pageReadout(at: chapterIndex),
                        progressReadout: bodyState.progressReadout(at: chapterIndex),
                        timeReadout: bodyState.timeReadout(at: chapterIndex),
                        isOnLastPage: bodyState.isOnLastPage(at: chapterIndex)
                    )
                    .opacity(chromeDimmed && !hasDismissibleReaderChrome ? 0.34 : 1)
                    .allowsHitTesting(false)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onHover { hovering in
            if hovering { wakeChromeBriefly() }
        }
        .background(palette.background.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.4), value: library.readingTheme)
        .animation(.easeInOut(duration: 0.18), value: showChapters)
        .animation(.easeInOut(duration: 0.18), value: showHighlights)
        .animation(.easeInOut(duration: 0.18), value: showTypography)
        .animation(.easeInOut(duration: 0.18), value: showSearch)
        .animation(.easeInOut(duration: 0.25), value: chromeDimmed)
        .animation(.easeInOut(duration: 0.2), value: isZenMode)
        .overlay(alignment: .topLeading) {
            if let selection {
                HighlightSelectionPopover(
                    palette: palette,
                    anchor: selection.anchor,
                    onPick: { color in
                        _ = library.addHighlight(
                            book: book,
                            chapterIndex: chapterIndex,
                            text: selection.text,
                            color: color,
                            location: currentLocation ?? book.lastLocation
                        )
                        self.selection = nil
                        bodyState.clearSelectionRequest = UUID()
                    }
                )
            }
        }
        .onAppear {
            library.markOpened(book)
            library.beginReadingSession()
            wakeChromeBriefly()
        }
        .onDisappear { library.endReadingSession() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            library.beginReadingSession()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            library.endReadingSession()
        }
        .onChange(of: chapterIndex) { _, _ in selection = nil }
        .onChange(of: isZenMode) { _, isZen in
            if isZen {
                selection = nil
                showHighlights = false
                showSearch = false
            }
        }
        .onChange(of: book.id) { _, _ in
            chapterIndex = 0
            selection = nil
            bodyState.readerError = nil
            showHighlights = false
            showSearch = false
            isZenMode = false
        }
    }

    private var hasDismissibleReaderChrome: Bool {
        showTypography || showSearch || selection != nil || (showHighlights && !isZenMode)
    }

    private func dismissReaderChrome() {
        showTypography = false
        showSearch = false
        showHighlights = false
        selection = nil
        bodyState.clearSelectionRequest = UUID()
    }

    private func submitSearch(backwards: Bool) {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        searchRequest = ReaderSearchRequest(query: query, backwards: backwards)
    }

    private func wakeChromeBriefly() {
        chromeDimmed = false
        let token = UUID()
        bodyState.chromeDimToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            if bodyState.chromeDimToken == token,
               !showTypography,
               !showSearch,
               !showHighlights,
               selection == nil {
                chromeDimmed = true
            }
        }
    }
}

// MARK: - Body state

struct ReaderBodyState {
    var chapters: [ReaderChapter] = []
    var totalPages: Int? = nil
    /// 1-indexed page number for the page currently in view. When set together
    /// with `totalPages`, the bottom bar reads from these directly instead of
    /// deriving page from chapter index.
    var currentPage: Int? = nil
    var chapterProgress: Double? = nil
    var currentChapterPage: Int? = nil
    var currentChapterPageCount: Int? = nil
    var chromeDimToken: UUID? = nil
    var clearSelectionRequest: UUID = UUID()
    var readerError: String? = nil

    func chapterTitle(at index: Int) -> String {
        guard chapters.indices.contains(index) else { return "—" }
        return chapters[index].title
    }

    func progress(at index: Int) -> Double {
        if let total = totalPages, total > 0, let current = currentPage {
            return min(1.0, max(0.0, Double(current) / Double(total)))
        }
        guard !chapters.isEmpty else { return 0 }
        return Double(index + 1) / Double(chapters.count)
    }

    func chapterProgressValue(at index: Int) -> Double {
        if let chapterProgress {
            return min(1.0, max(0.0, chapterProgress))
        }
        if let currentChapterPage, let currentChapterPageCount, currentChapterPageCount > 0 {
            return min(1.0, max(0.0, Double(currentChapterPage) / Double(currentChapterPageCount)))
        }
        guard !chapters.isEmpty else { return 0 }
        return chapters.indices.contains(index) ? 0 : progress(at: index)
    }

    func progressReadout(at index: Int) -> String {
        let chapterPercent = Int(round(chapterProgressValue(at: index) * 100))
        return "chapter \(chapterPercent)%"
    }

    func timeReadout(at index: Int) -> String {
        var parts: [String] = []
        if let chapterPagesLeft = chapterPagesRemaining {
            parts.append("\(Self.timeString(forPageCount: chapterPagesLeft)) left in chapter")
        }
        if let total = totalPages, total > 0, let current = currentPage {
            let pagesLeft = max(0, total - current)
            parts.append("\(Self.timeString(forPageCount: pagesLeft)) left in book")
        }
        return parts.joined(separator: " · ")
    }

    private var chapterPagesRemaining: Int? {
        if let currentChapterPage, let currentChapterPageCount, currentChapterPageCount > 0 {
            return max(0, currentChapterPageCount - currentChapterPage)
        }
        if let currentChapterPageCount, currentChapterPageCount > 0, let chapterProgress {
            let progress = min(1.0, max(0.0, chapterProgress))
            return max(0, Int(ceil(Double(currentChapterPageCount) * (1 - progress))))
        }
        return nil
    }

    private static func timeString(forPageCount pages: Int) -> String {
        if pages <= 0 { return "under 1 min" }
        let minutes = max(1, Int(ceil(Double(pages) * 1.25)))
        if minutes < 60 { return minutes == 1 ? "1 min" : "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 { return hours == 1 ? "1 hr" : "\(hours) hr" }
        return "\(hours)h \(remainder)m"
    }

    func pageReadout(at index: Int) -> String {
        guard !chapters.isEmpty else { return "" }
        if let total = totalPages, total > 0, let current = currentPage {
            return current >= total ? "the last page" : "page \(current) of \(total)"
        }
        if let total = totalPages, total > 0 {
            let approxPage = max(1, Int(round(Double(total) * progress(at: index))))
            return approxPage >= total ? "the last page" : "page \(approxPage) of \(total)"
        }
        return "section \(index + 1) of \(chapters.count)"
    }

    /// True when the current readout is "the last page" — lets the bottom bar
    /// switch to a serif italic for that one moment of arrival.
    func isOnLastPage(at index: Int) -> Bool {
        if let total = totalPages, total > 0, let current = currentPage, current >= total { return true }
        if let total = totalPages, total > 0 {
            let approxPage = max(1, Int(round(Double(total) * progress(at: index))))
            return approxPage >= total
        }
        return false
    }
}

struct ReaderChapter: Identifiable, Hashable {
    let id: Int
    let title: String
    let subtitle: String?
    let level: Int

    nonisolated init(id: Int, title: String, subtitle: String? = nil, level: Int = 0) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.level = level
    }
}

struct ReaderSelection {
    let text: String
    let anchor: CGPoint
}

private enum EPUBReadingMode: String, CaseIterable, Identifiable {
    case scroll
    case spread
    case paged

    var id: String { rawValue }

    var label: String {
        switch self {
        case .scroll: return "Scroll"
        case .spread: return "Spread"
        case .paged: return "Pages"
        }
    }
}

private struct EPUBLocation: Codable, Hashable {
    let type: String
    let href: String
    let spineIndex: Int
    let progression: Double
    let globalProgression: Double
    /// Global 1-indexed page when the location was captured. Restoring uses
    /// this first, falling back to spine + progression if the page count has
    /// changed (typography or window resize since the save).
    let pageNumber: Int?
    /// 0-indexed page offset within the active spine. Reserved for the per-
    /// spine pagination cache in Phase 3; harmless to carry now.
    let pageWithinSpine: Int?

    init(
        href: String,
        spineIndex: Int,
        progression: Double,
        globalProgression: Double,
        pageNumber: Int? = nil,
        pageWithinSpine: Int? = nil
    ) {
        self.type = "epub"
        self.href = href
        self.spineIndex = spineIndex
        self.progression = progression
        self.globalProgression = globalProgression
        self.pageNumber = pageNumber
        self.pageWithinSpine = pageWithinSpine
    }

    var encoded: String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(_ value: String?) -> EPUBLocation? {
        guard let value, let data = value.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(EPUBLocation.self, from: data)
    }
}

private struct ReaderSearchRequest: Equatable {
    let id = UUID()
    let query: String
    let backwards: Bool
}

// MARK: - Top bar

private struct ReaderTopBar: View {
    let palette: ReaderPalette
    let book: Book
    let chapterTitle: String
    let chapterCount: Int
    let chapterIndex: Int
    @Binding var showChapters: Bool
    @Binding var showHighlights: Bool
    @Binding var showTypography: Bool
    @Binding var showSearch: Bool
    @Binding var isZenMode: Bool
    @Binding var theme: ReadingTheme
    let isBookmarked: Bool
    let onToggleBookmark: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            VStack(spacing: 2) {
                Text(book.title)
                    .font(.chickenSerif(14, weight: .medium))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                Text(chapterReadout)
                    .font(.chickenUI(11))
                    .tracking(0.4)
                    .foregroundStyle(palette.faint)
                    .lineLimit(1)
            }
            .frame(maxWidth: 560)

            HStack(spacing: 16) {
                Button(action: onClose) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left").font(.system(size: 12, weight: .medium))
                        Text("Library").font(.chickenUI(12))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .foregroundStyle(palette.muted)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    ToolbarToggle(palette: palette, system: "list.bullet", isOn: showChapters, help: "Chapters") {
                        showChapters.toggle()
                    }
                    ToolbarToggle(palette: palette, system: "textformat.size", isOn: showTypography, help: "Typography") {
                        showTypography.toggle()
                    }
                    ToolbarToggle(palette: palette, system: "magnifyingglass", isOn: showSearch, help: "Search") {
                        showSearch.toggle()
                    }
                    ToolbarToggle(palette: palette, system: "rectangle.compress.vertical", isOn: isZenMode, help: isZenMode ? "Exit zen mode" : "Zen mode") {
                        isZenMode.toggle()
                    }
                    ThemeCycleButton(palette: palette, theme: $theme)
                    BookmarkFoldButton(
                        palette: palette,
                        isBookmarked: isBookmarked,
                        action: onToggleBookmark
                    )
                    ToolbarToggle(palette: palette, system: "quote.bubble", isOn: showHighlights, help: "Highlights") {
                        showHighlights.toggle()
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(
            palette.background
                .overlay(alignment: .bottom) {
                    Rectangle().fill(palette.border).frame(height: 0.5)
                }
        )
    }

    private var chapterReadout: String {
        let author = book.displayAuthor
        guard chapterCount > 0 else { return author }
        return "\(author) · Chapter \(chapterIndex + 1) of \(chapterCount) · \(chapterTitle)"
    }
}

private struct ToolbarToggle: View {
    let palette: ReaderPalette
    let system: String
    let isOn: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(isOn ? palette.text : palette.muted)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isOn ? palette.surfaceAlt : .clear)
                        .stroke(isOn ? palette.borderStrong : .clear, lineWidth: 0.5)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Bookmark toggle that does a small "dog-ear" gesture on tap — a brief tilt
/// and scale, like folding a page corner. Reduce-motion users see only the
/// icon swap.
private struct BookmarkFoldButton: View {
    let palette: ReaderPalette
    let isBookmarked: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var foldStage: Int = 0  // 0 = idle, 1 = folding, 2 = settled

    var body: some View {
        Button {
            action()
            guard !reduceMotion else { return }
            withAnimation(.spring(response: 0.18, dampingFraction: 0.55)) {
                foldStage = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.7)) {
                    foldStage = 0
                }
            }
        } label: {
            Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(isBookmarked ? palette.text : palette.muted)
                .rotationEffect(.degrees(reduceMotion ? 0 : (foldStage == 1 ? -14 : 0)),
                                anchor: .topLeading)
                .scaleEffect(reduceMotion ? 1 : (foldStage == 1 ? 0.88 : 1.0),
                             anchor: .topLeading)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isBookmarked ? palette.surfaceAlt : .clear)
                        .stroke(isBookmarked ? palette.borderStrong : .clear, lineWidth: 0.5)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(isBookmarked ? "Remove bookmark" : "Bookmark this page")
    }
}

private struct ThemeCycleButton: View {
    let palette: ReaderPalette
    @Binding var theme: ReadingTheme

    var body: some View {
        Button {
            let order = ReadingTheme.allCases
            let next = order[(order.firstIndex(of: theme).map { ($0 + 1) % order.count } ?? 0)]
            theme = next
        } label: {
            Image(systemName: themeIcon)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(palette.muted)
                .frame(width: 30, height: 30)
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help("Theme: \(theme.label)")
    }

    private var themeIcon: String {
        switch theme {
        case .paper: return "sun.max"
        case .sepia: return "book.closed"
        case .ink:   return "moon"
        }
    }
}

// MARK: - Chapters panel

private struct ChaptersPanel: View {
    let palette: ReaderPalette
    let chapters: [ReaderChapter]
    @Binding var selectedIndex: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Chapters")
                .font(.chickenUI(11, weight: .medium))
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(palette.faint)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 14)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if chapters.isEmpty {
                            Text("This book has no parsed chapters yet.")
                                .font(.chickenUI(12))
                                .foregroundStyle(palette.faint)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                        }
                        ForEach(chapters) { chapter in
                            ChapterRow(
                                palette: palette,
                                index: chapter.id,
                                title: chapter.title,
                                subtitle: chapter.subtitle,
                                level: chapter.level,
                                isActive: chapter.id == selectedIndex
                            ) {
                                selectedIndex = chapter.id
                            }
                            .id(chapter.id)
                        }
                    }
                }
                .onChange(of: selectedIndex) { _, new in
                    withAnimation(.easeInOut(duration: 0.18)) {
                        proxy.scrollTo(new, anchor: .center)
                    }
                }
            }
        }
        .background(
            palette.background
                .overlay(alignment: .trailing) {
                    Rectangle().fill(palette.border).frame(width: 0.5)
                }
        )
    }
}

private struct ChapterRow: View {
    let palette: ReaderPalette
    let index: Int
    let title: String
    let subtitle: String?
    let level: Int
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(isActive ? palette.text : .clear)
                    .frame(width: 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(level > 0 ? "Section \(index + 1)" : "Chapter \(index + 1)")
                        .font(.chickenUI(10, weight: .medium))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(palette.faint)

                    Text(title)
                        .font(.chickenSerif(14, weight: isActive ? .medium : .regular))
                        .foregroundStyle(isActive ? palette.text : palette.muted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.chickenUI(10))
                            .tracking(0.2)
                            .foregroundStyle(palette.faint)
                    }
                }
                .padding(.leading, 18 + CGFloat(min(level, 3)) * 14)
                .padding(.trailing, 18)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Highlights panel

private struct HighlightsPanel: View {
    @EnvironmentObject private var library: LocalLibraryStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let palette: ReaderPalette
    let book: Book
    let bookHighlights: [Highlight]
    let bookBookmarks: [Bookmark]
    let bodyState: ReaderBodyState
    let onJumpTo: (Int) -> Void

    /// New rail entries slide in from above with a fade; removals fade and
    /// collapse upward. Reduce-motion users see opacity only.
    private var railRowTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal:   .move(edge: .top).combined(with: .opacity)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Highlights")
                    .font(.chickenUI(11, weight: .medium))
                    .tracking(1.5)
                    .textCase(.uppercase)
                    .foregroundStyle(palette.faint)
                Spacer()
                Text("\(bookHighlights.count + bookBookmarks.count)")
                    .font(.chickenMono(11))
                    .foregroundStyle(palette.faint)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 14)

            if bookHighlights.isEmpty && bookBookmarks.isEmpty {
                Text("Select any text to add a highlight, or tap the bookmark button to save your place.")
                    .font(.chickenUI(12))
                    .foregroundStyle(palette.faint)
                    .lineSpacing(2)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if !bookBookmarks.isEmpty {
                            ForEach(bookBookmarks) { bookmark in
                                BookmarkRow(
                                    palette: palette,
                                    bookmark: bookmark,
                                    onJump: { onJumpTo(bookmark.chapterIndex) },
                                    onRemove: { library.removeBookmark(bookmark) }
                                )
                                .transition(railRowTransition)
                                Divider().background(palette.border)
                            }
                        }
                        ForEach(bookHighlights) { highlight in
                            HighlightRow(
                                palette: palette,
                                highlight: highlight,
                                chapterTitle: bodyState.chapterTitle(at: highlight.chapterIndex),
                                onJump: { onJumpTo(highlight.chapterIndex) },
                                onRemove: { library.removeHighlight(highlight) }
                            )
                            .transition(railRowTransition)
                            Divider().background(palette.border)
                        }
                    }
                    .animation(reduceMotion ? .none : .timingCurve(0.22, 1, 0.36, 1, duration: 0.26),
                               value: bookHighlights.map(\.id))
                    .animation(reduceMotion ? .none : .timingCurve(0.22, 1, 0.36, 1, duration: 0.26),
                               value: bookBookmarks.map(\.id))
                }
            }
        }
        .background(
            palette.surfaceAlt
                .overlay(alignment: .leading) {
                    Rectangle().fill(palette.border).frame(width: 0.5)
                }
        )
    }
}

private struct BookmarkRow: View {
    let palette: ReaderPalette
    let bookmark: Bookmark
    let onJump: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.muted)
                .frame(width: 14, height: 20)

            Button(action: onJump) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(bookmark.title)
                        .font(.chickenSerif(13, weight: .medium))
                        .foregroundStyle(palette.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text("Ch. \(bookmark.chapterIndex + 1) · \(timeAgo(bookmark.createdAt))")
                        .font(.chickenUI(10))
                        .tracking(0.3)
                        .foregroundStyle(palette.faint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.faint)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove bookmark")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func timeAgo(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct HighlightRow: View {
    let palette: ReaderPalette
    let highlight: Highlight
    let chapterTitle: String
    let onJump: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onJump) {
                HStack(alignment: .top, spacing: 11) {
                    Rectangle()
                        .fill(highlight.color.bar)
                        .frame(width: 2)
                    Text(highlight.text)
                        .font(.chickenSerif(13))
                        .foregroundStyle(palette.text)
                        .lineSpacing(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)

            if !highlight.note.isEmpty {
                Text(highlight.note)
                    .font(.chickenSerif(11, italic: true))
                    .foregroundStyle(palette.muted)
                    .lineSpacing(2)
                    .padding(.leading, 13)
            }

            HStack {
                Text("Ch. \(highlight.chapterIndex + 1) · \(timeAgo(highlight.createdAt))")
                    .font(.chickenUI(10))
                    .tracking(0.3)
                    .foregroundStyle(palette.faint)

                Spacer()

                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.faint)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove highlight")
            }
            .padding(.leading, 13)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func timeAgo(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Typography popover

private struct TypographyPopover: View {
    let palette: ReaderPalette
    @Binding var fontSize: CGFloat
    @Binding var lineHeight: CGFloat
    @Binding var columnWidth: CGFloat
    @Binding var readingMode: EPUBReadingMode
    let supportsFlow: Bool
    @Binding var theme: ReadingTheme
    let onClose: () -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Typography")
                    .font(.chickenUI(11, weight: .medium))
                    .tracking(1.5)
                    .textCase(.uppercase)
                    .foregroundStyle(palette.muted)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.muted)
                }
                .buttonStyle(.plain)
            }

            ControlRow(palette: palette, label: "Size", value: "\(Int(fontSize))pt") {
                Stepper(palette: palette,
                        canMinus: fontSize > 13,
                        canPlus: fontSize < 24,
                        onMinus: { fontSize = max(13, fontSize - 1) },
                        onPlus:  { fontSize = min(24, fontSize + 1) })
            }

            ControlRow(palette: palette, label: "Spacing", value: String(format: "%.2f", lineHeight)) {
                Stepper(palette: palette,
                        canMinus: lineHeight > 1.4,
                        canPlus: lineHeight < 2.2,
                        onMinus: { lineHeight = max(1.4, (lineHeight - 0.1).rounded(toPlaces: 2)) },
                        onPlus:  { lineHeight = min(2.2, (lineHeight + 0.1).rounded(toPlaces: 2)) })
            }

            ControlRow(palette: palette, label: "Width", value: "\(Int(columnWidth))pt") {
                Stepper(palette: palette,
                        canMinus: columnWidth > 480,
                        canPlus: columnWidth < 820,
                        onMinus: { columnWidth = max(480, columnWidth - 40) },
                        onPlus:  { columnWidth = min(820, columnWidth + 40) })
            }

            if supportsFlow {
                ControlRow(palette: palette, label: "Flow", value: readingMode.label) {
                    HStack(spacing: 4) {
                        ForEach(EPUBReadingMode.allCases) { mode in
                            Button { readingMode = mode } label: {
                                Text(mode.label)
                                    .font(.chickenUI(10, weight: readingMode == mode ? .medium : .regular))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(readingMode == mode ? palette.surfaceAlt : palette.surface)
                                            .stroke(readingMode == mode ? palette.borderStrong : palette.border, lineWidth: 0.5)
                                    )
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(readingMode == mode ? palette.text : palette.muted)
                        }
                    }
                }
            }

            Divider().background(palette.border)

            VStack(alignment: .leading, spacing: 10) {
                Text("Theme")
                    .font(.chickenUI(11))
                    .tracking(0.4)
                    .foregroundStyle(palette.muted)
                HStack(spacing: 8) {
                    ForEach(ReadingTheme.allCases) { t in
                        Button { theme = t } label: {
                            Text(t.label)
                                .font(.chickenSerif(11, italic: true))
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(t.palette.background)
                                        .stroke(theme == t ? t.palette.text : t.palette.border, lineWidth: theme == t ? 1.0 : 0.5)
                                )
                                .foregroundStyle(t.palette.text)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button(action: onReset) {
                Text("Reset to defaults")
                    .font(.chickenUI(11))
                    .tracking(0.4)
                    .foregroundStyle(palette.muted)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(palette.border, lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.surface)
                .stroke(palette.borderStrong, lineWidth: 0.5)
                .shadow(color: palette.shadow, radius: 12, x: 0, y: 6)
        )
    }
}

private struct ReaderSearchPopover: View {
    let palette: ReaderPalette
    @Binding var query: String
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onClose: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(palette.faint)

            TextField("Search in book", text: $query)
                .textFieldStyle(.plain)
                .font(.chickenUI(12))
                .foregroundStyle(palette.text)
                .focused($focused)
                .onSubmit(onNext)

            Button(action: onPrevious) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.muted)
            .help("Previous match")

            Button(action: onNext) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.muted)
            .help("Next match")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.faint)
            .help("Close search")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 340)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.surface)
                .stroke(palette.borderStrong, lineWidth: 0.5)
                .shadow(color: palette.shadow, radius: 12, x: 0, y: 6)
        )
        .onAppear {
            DispatchQueue.main.async { focused = true }
        }
    }
}

private struct ControlRow<Right: View>: View {
    let palette: ReaderPalette
    let label: String
    let value: String
    @ViewBuilder var right: () -> Right

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.chickenUI(12)).foregroundStyle(palette.text)
                Text(value).font(.chickenMono(11)).foregroundStyle(palette.faint)
            }
            Spacer()
            right()
        }
    }
}

private struct Stepper: View {
    let palette: ReaderPalette
    let canMinus: Bool
    let canPlus: Bool
    let onMinus: () -> Void
    let onPlus: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            stepperButton("minus", enabled: canMinus, action: onMinus)
            stepperButton("plus", enabled: canPlus, action: onPlus)
        }
    }

    private func stepperButton(_ system: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 28, height: 28)
                .foregroundStyle(enabled ? palette.text : palette.faint)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(palette.surface)
                        .stroke(palette.border, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

private extension CGFloat {
    func rounded(toPlaces places: Int) -> CGFloat {
        let m = pow(10.0, Double(places))
        return CGFloat((Double(self) * m).rounded() / m)
    }
}

// MARK: - Highlight selection popover

private struct HighlightSelectionPopover: View {
    let palette: ReaderPalette
    let anchor: CGPoint
    let onPick: (HighlightColor) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(HighlightColor.allCases) { c in
                Button { onPick(c) } label: {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(c.bar)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(c.rawValue.capitalized)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.sRGB, red: 0.10, green: 0.10, blue: 0.105, opacity: 1))
                .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 4)
        )
        .position(x: anchor.x, y: max(36, anchor.y - 28))
        .allowsHitTesting(true)
    }
}

// MARK: - Bottom progress

private struct ReaderBottomBar: View {
    let palette: ReaderPalette
    let progress: Double
    let pageReadout: String
    let progressReadout: String
    let timeReadout: String
    let isOnLastPage: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 14) {
            Text("\(Int(round(progress * 100)))%")
                .font(.chickenMono(11))
                .foregroundStyle(palette.faint)
                .frame(minWidth: 32, alignment: .leading)
                .contentTransition(.numericText())
                .animation(reduceMotion ? .none : .timingCurve(0.25, 1, 0.5, 1, duration: 0.28),
                           value: progress)

            ZStack(alignment: .leading) {
                Capsule().fill(palette.surfaceAlt).frame(height: 2)
                GeometryReader { g in
                    Capsule().fill(palette.muted)
                        .frame(width: max(0, g.size.width * progress), height: 2)
                        .animation(reduceMotion ? .none : .timingCurve(0.25, 1, 0.5, 1, duration: 0.28),
                                   value: progress)
                }
                .frame(height: 2)
            }

            VStack(alignment: .trailing, spacing: 3) {
                // The arrival moment: at the final page the readout switches to a
                // serif italic "the last page" to break the "page N of M" cadence
                // and quietly mark that the book has ended.
                Group {
                    if isOnLastPage {
                        Text(pageReadout)
                            .font(.chickenSerif(12, italic: true))
                            .foregroundStyle(palette.muted)
                            .transition(.opacity)
                    } else {
                        Text(pageReadout)
                            .font(.chickenMono(11))
                            .foregroundStyle(palette.faint)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: isOnLastPage)

                HStack(spacing: 8) {
                    Text(progressReadout)
                    if !timeReadout.isEmpty {
                        Text("·")
                        Text(timeReadout)
                            .lineLimit(1)
                    }
                }
                .font(.chickenMono(10))
                .foregroundStyle(palette.faint.opacity(0.82))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(
            palette.background
                .overlay(alignment: .top) {
                    Rectangle().fill(palette.border).frame(height: 0.5)
                }
        )
    }
}

// MARK: - Body switcher

private struct ReaderBody: View {
    @EnvironmentObject private var library: LocalLibraryStore
    let book: Book
    let palette: ReaderPalette
    @Binding var chapterIndex: Int
    @Binding var bodyState: ReaderBodyState
    @Binding var selection: ReaderSelection?
    let highlights: [Highlight]
    let fontSize: CGFloat
    let lineHeight: CGFloat
    let columnWidth: CGFloat
    let readingMode: EPUBReadingMode
    let searchRequest: ReaderSearchRequest?
    let onLocationChange: (String?) -> Void

    var body: some View {
        Group {
            if let error = bodyState.readerError {
                ReaderUnavailableView(palette: palette, title: book.title, message: error)
            } else {
                switch book.format {
                case .pdf:
                    PDFReaderBody(
                        book: book,
                        palette: palette,
                        chapterIndex: $chapterIndex,
                        bodyState: $bodyState,
                        readingMode: readingMode,
                        searchRequest: searchRequest
                    )
                case .text, .document, .unknown:
                    TextReaderBody(
                        book: book,
                        palette: palette,
                        chapterIndex: $chapterIndex,
                        bodyState: $bodyState,
                        selection: $selection,
                        highlights: highlights,
                        fontSize: fontSize,
                        lineHeight: lineHeight,
                        columnWidth: columnWidth
                    )
                case .epub:
                    EPUBReaderBody(
                        book: book,
                        palette: palette,
                        chapterIndex: $chapterIndex,
                        bodyState: $bodyState,
                        fontSize: fontSize,
                        lineHeight: lineHeight,
                        columnWidth: columnWidth,
                        readingMode: readingMode,
                        searchRequest: searchRequest,
                        onLocationChange: onLocationChange
                    )
                }
            }
        }
    }
}

private struct ReaderUnavailableView: View {
    let palette: ReaderPalette
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(palette.faint)
            Text(title)
                .font(.chickenSerif(22, weight: .medium))
                .foregroundStyle(palette.text)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.chickenUI(13))
                .foregroundStyle(palette.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 420)
        }
        .padding(44)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
    }
}

// MARK: - PDF body

private struct PDFReaderBody: NSViewRepresentable {
    let book: Book
    let palette: ReaderPalette
    @Binding var chapterIndex: Int
    @Binding var bodyState: ReaderBodyState
    let readingMode: EPUBReadingMode
    let searchRequest: ReaderSearchRequest?
    @EnvironmentObject private var library: LocalLibraryStore

    func makeNSView(context: Context) -> PDFView {
        let view = ChickenPDFView()
        view.autoScales = true
        view.displayDirection = .vertical
        view.backgroundColor = NSColor.clear
        applyDisplayMode(to: view)
        let url = library.fileURL(for: book)
        let document = PDFDocument(url: url)
        view.document = document
        context.coordinator.attach(view: view)
        DispatchQueue.main.async {
            context.coordinator.updateReaderState(for: document, url: url)
        }
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        applyDisplayMode(to: view)
        let url = library.fileURL(for: book)
        if view.document?.documentURL != url {
            let document = PDFDocument(url: url)
            view.document = document
            DispatchQueue.main.async {
                context.coordinator.updateReaderState(for: document, url: url)
            }
        }
        context.coordinator.go(toIndex: chapterIndex)
        context.coordinator.performSearchIfNeeded(searchRequest)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    private func applyDisplayMode(to view: PDFView) {
        if let view = view as? ChickenPDFView {
            view.usesDiscreteTurns = readingMode == .spread || readingMode == .paged
        }
        view.displaysAsBook = true
        switch readingMode {
        case .scroll:
            view.displayMode = .singlePageContinuous
            view.displayDirection = .vertical
        case .spread:
            view.displayMode = .twoUp
            view.displayDirection = .horizontal
        case .paged:
            view.displayMode = .singlePage
            view.displayDirection = .horizontal
        }
        view.autoScales = true
    }

    final class ChickenPDFView: PDFView {
        var usesDiscreteTurns = false
        private var lastTurnAt = Date.distantPast

        // PDFView ships with arrow-key bindings (←/→ for previous/next page,
        // ↑/↓ for scroll). Those only fire when the view is the window's
        // first responder, and SwiftUI's NSViewRepresentable wrapping doesn't
        // automatically promote it. Take focus the moment we land in a window.
        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                if window.firstResponder !== self {
                    window.makeFirstResponder(self)
                }
            }
        }

        override func scrollWheel(with event: NSEvent) {
            guard usesDiscreteTurns else {
                super.scrollWheel(with: event)
                return
            }

            let dominantDelta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
                ? event.scrollingDeltaX
                : -event.scrollingDeltaY
            guard abs(dominantDelta) > 6 else { return }
            guard Date().timeIntervalSince(lastTurnAt) > 0.28 else { return }
            lastTurnAt = Date()

            if dominantDelta > 0 {
                goToNextPage(nil)
            } else {
                goToPreviousPage(nil)
            }
        }

        override func keyDown(with event: NSEvent) {
            guard !event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
                switch event.keyCode {
                case 123, 126: // left/up
                    goToPreviousPage(nil)
                    return
                case 124, 125, 121, 49: // right/down/page down/space
                    goToNextPage(nil)
                    return
                case 116: // page up
                    goToPreviousPage(nil)
                    return
                default:
                    break
                }
                super.keyDown(with: event)
                return
            }
            super.keyDown(with: event)
        }

        // MARK: Page navigation
        //
        // PDFKit's default `goToNextPage` advances by exactly one page even in
        // two-up display mode, so a "next" turn from the [2,3] spread lands on
        // [3,4] — overlapping the page you just read. Apple Books treats a
        // spread as one unit and advances by the whole pair, with the very
        // first page (when `displaysAsBook` is on) sitting alone on the right
        // like a real book's recto. We model that with a "group index": group
        // 0 is the lone first page, group 1 is the [1,2] spread, group 2 is
        // [3,4], etc. Navigation moves between groups, not raw pages.

        private var isPaired: Bool {
            displayMode == .twoUp || displayMode == .twoUpContinuous
        }

        private func currentGroupIndex() -> Int {
            guard let doc = document, let current = currentPage else { return 0 }
            let pageIndex = doc.index(for: current)
            guard isPaired else { return pageIndex }
            if displaysAsBook {
                return pageIndex == 0 ? 0 : (pageIndex + 1) / 2
            } else {
                return pageIndex / 2
            }
        }

        private func pageIndex(forGroup groupIndex: Int) -> Int {
            guard isPaired else { return groupIndex }
            if displaysAsBook {
                return groupIndex == 0 ? 0 : 2 * groupIndex - 1
            } else {
                return 2 * groupIndex
            }
        }

        override func goToNextPage(_ sender: Any?) {
            guard isPaired else { super.goToNextPage(sender); return }
            guard let doc = document, doc.pageCount > 0 else { return }
            let target = pageIndex(forGroup: currentGroupIndex() + 1)
            let clamped = min(doc.pageCount - 1, target)
            guard let next = doc.page(at: clamped), next != currentPage else { return }
            go(to: next)
        }

        override func goToPreviousPage(_ sender: Any?) {
            guard isPaired else { super.goToPreviousPage(sender); return }
            guard let doc = document, doc.pageCount > 0 else { return }
            let target = pageIndex(forGroup: max(0, currentGroupIndex() - 1))
            let clamped = max(0, min(doc.pageCount - 1, target))
            guard let prev = doc.page(at: clamped), prev != currentPage else { return }
            go(to: prev)
        }
    }

    final class Coordinator: NSObject {
        let parent: PDFReaderBody
        weak var view: PDFView?
        private var pageMap: [(Int, String)] = []  // chapter id -> destination page index, title
        private var lastSearchID: UUID?
        private var lastSearchQuery = ""
        private var searchMatches: [PDFSelection] = []
        private var searchIndex = -1

        init(_ parent: PDFReaderBody) {
            self.parent = parent
        }

        func attach(view: PDFView) {
            self.view = view
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(pageChanged(_:)),
                name: .PDFViewPageChanged,
                object: view
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func updateReaderState(for document: PDFDocument?, url: URL) {
            guard let document else {
                if FileManager.default.fileExists(atPath: url.path) {
                    parent.bodyState.readerError = "Chicken could not open this file as a valid PDF. It may be corrupt, incomplete, encrypted, or mislabeled."
                } else {
                    parent.bodyState.readerError = "This book file is missing from Chicken's local library folder."
                }
                parent.bodyState.chapters = []
                parent.bodyState.totalPages = nil
                parent.bodyState.currentPage = nil
                parent.bodyState.chapterProgress = nil
                parent.bodyState.currentChapterPage = nil
                parent.bodyState.currentChapterPageCount = nil
                return
            }

            parent.bodyState.readerError = nil
            refreshOutline(document: document)
        }

        func refreshOutline() {
            guard let view, let doc = view.document else { return }
            refreshOutline(document: doc)
        }

        private func refreshOutline(document doc: PDFDocument) {
            var entries: [(Int, String)] = []
            if let outline = doc.outlineRoot, outline.numberOfChildren > 0 {
                walk(outline, into: &entries, doc: doc)
            }
            if entries.isEmpty {
                let limit = min(doc.pageCount, 200)
                entries = (0..<limit).map { ($0, "Page \($0 + 1)") }
            }
            pageMap = entries
            let chapters = entries.enumerated().map { idx, item in
                ReaderChapter(id: idx, title: item.1, subtitle: "Page \(item.0 + 1)")
            }
            DispatchQueue.main.async {
                self.parent.bodyState.chapters = chapters
                self.parent.bodyState.totalPages = doc.pageCount
                if let view = self.view, let page = view.currentPage {
                    let pageIndex = doc.index(for: page)
                    self.updatePageState(pageIndex: pageIndex, document: doc)
                }
            }
        }

        private func walk(_ node: PDFOutline, into entries: inout [(Int, String)], doc: PDFDocument) {
            for i in 0..<node.numberOfChildren {
                guard let child = node.child(at: i) else { continue }
                let title = child.label ?? "Untitled"
                if let dest = child.destination, let page = dest.page {
                    let pageIndex = doc.index(for: page)
                    entries.append((pageIndex, title))
                }
                if child.numberOfChildren > 0 {
                    walk(child, into: &entries, doc: doc)
                }
            }
        }

        func go(toIndex index: Int) {
            guard let view, let doc = view.document, pageMap.indices.contains(index) else { return }
            let pageIndex = pageMap[index].0
            guard let page = doc.page(at: pageIndex) else { return }
            if view.currentPage != page {
                view.go(to: page)
            }
        }

        @objc private func pageChanged(_ note: Notification) {
            guard let view, let page = view.currentPage, let doc = view.document else { return }
            let pageIndex = doc.index(for: page)
            guard let nearest = pageMap.lastIndex(where: { $0.0 <= pageIndex }) else { return }
            DispatchQueue.main.async {
                if self.parent.chapterIndex != nearest {
                    self.parent.chapterIndex = nearest
                }
                self.updatePageState(pageIndex: pageIndex, document: doc)
                let progress = doc.pageCount > 0 ? Double(pageIndex + 1) / Double(doc.pageCount) : 0
                self.parent.library.updateProgress(for: self.parent.book, progress: progress)
            }
        }

        private func updatePageState(pageIndex: Int, document doc: PDFDocument) {
            guard doc.pageCount > 0 else {
                parent.bodyState.currentPage = nil
                parent.bodyState.chapterProgress = nil
                parent.bodyState.currentChapterPage = nil
                parent.bodyState.currentChapterPageCount = nil
                return
            }
            let nearest = pageMap.lastIndex(where: { $0.0 <= pageIndex }) ?? 0
            let chapterStart = pageMap.indices.contains(nearest) ? pageMap[nearest].0 : 0
            let chapterEnd = pageMap.indices.contains(nearest + 1) ? pageMap[nearest + 1].0 : doc.pageCount
            let chapterPageCount = max(1, chapterEnd - chapterStart)
            let currentChapterPage = max(1, min(chapterPageCount, pageIndex - chapterStart + 1))
            parent.bodyState.currentPage = max(1, min(doc.pageCount, pageIndex + 1))
            parent.bodyState.currentChapterPage = currentChapterPage
            parent.bodyState.currentChapterPageCount = chapterPageCount
            parent.bodyState.chapterProgress = Double(currentChapterPage) / Double(chapterPageCount)
        }

        func performSearchIfNeeded(_ request: ReaderSearchRequest?) {
            guard let request, lastSearchID != request.id else { return }
            lastSearchID = request.id
            performSearch(query: request.query, backwards: request.backwards)
        }

        private func performSearch(query: String, backwards: Bool) {
            guard let view, let doc = view.document else { return }
            if query != lastSearchQuery {
                lastSearchQuery = query
                searchMatches = doc.findString(query, withOptions: [.caseInsensitive])
                searchIndex = backwards ? searchMatches.count : -1
            }
            guard !searchMatches.isEmpty else { return }
            if backwards {
                searchIndex = max(0, searchIndex - 1)
            } else {
                searchIndex = min(searchMatches.count - 1, searchIndex + 1)
            }
            let selection = searchMatches[searchIndex]
            view.setCurrentSelection(selection, animate: true)
            view.go(to: selection)
        }
    }
}

// MARK: - EPUB body

private struct EPUBReaderBody: View {
    @EnvironmentObject private var library: LocalLibraryStore
    let book: Book
    let palette: ReaderPalette
    @Binding var chapterIndex: Int
    @Binding var bodyState: ReaderBodyState
    let fontSize: CGFloat
    let lineHeight: CGFloat
    let columnWidth: CGFloat
    let readingMode: EPUBReadingMode
    let searchRequest: ReaderSearchRequest?
    let onLocationChange: (String?) -> Void

    var body: some View {
        EPUBWebReader(
            book: book,
            bookURL: library.fileURL(for: book),
            palette: palette,
            chapterIndex: $chapterIndex,
            bodyState: $bodyState,
            fontSize: fontSize,
            lineHeight: lineHeight,
            columnWidth: columnWidth,
            readingMode: readingMode,
            searchRequest: searchRequest,
            onProgress: { progress, location in
                onLocationChange(location)
                library.updateProgress(for: book, progress: progress, location: location)
            }
        )
        .background(palette.background)
    }
}

private struct EPUBWebReader: NSViewRepresentable {
    let book: Book
    let bookURL: URL
    let palette: ReaderPalette
    @Binding var chapterIndex: Int
    @Binding var bodyState: ReaderBodyState
    let fontSize: CGFloat
    let lineHeight: CGFloat
    let columnWidth: CGFloat
    let readingMode: EPUBReadingMode
    let searchRequest: ReaderSearchRequest?
    let onProgress: (Double, String?) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "chickenProgress")
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.attach(webView)
        context.coordinator.loadPublication(from: bookURL)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyTheme()
        context.coordinator.go(to: chapterIndex)
        context.coordinator.performSearchIfNeeded(searchRequest)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.prepareForDismantle()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: EPUBWebReader
        private weak var webView: WKWebView?
        private var publication: EPUBPublication?
        private var currentChapterIndex: Int?
        private var preparedURL: URL?
        private var hasLoadedCombinedDocument = false
        private var restoredInitialLocation = false
        private var lastSearchID: UUID?
        private var isTornDown = false

        init(parent: EPUBWebReader) {
            self.parent = parent
        }

        func attach(_ webView: WKWebView) {
            isTornDown = false
            self.webView = webView
        }

        func prepareForDismantle() {
            isTornDown = true
            webView?.stopLoading()
            webView?.navigationDelegate = nil
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: "chickenProgress")
            webView = nil
        }

        func loadPublication(from url: URL) {
            guard preparedURL != url else { return }
            preparedURL = url

            Task.detached(priority: .utility) {
                let publication = EPUBPublication.load(from: url)
                await MainActor.run {
                    guard let publication else {
                        self.publication = nil
                        self.currentChapterIndex = nil
                        self.parent.bodyState.chapters = []
                        self.parent.bodyState.totalPages = nil
                        self.parent.bodyState.currentPage = nil
                        self.parent.bodyState.chapterProgress = nil
                        self.parent.bodyState.currentChapterPage = nil
                        self.parent.bodyState.currentChapterPageCount = nil
                        self.parent.bodyState.readerError = FileManager.default.fileExists(atPath: url.path)
                            ? "Chicken could not open this file as a valid EPUB. It may be corrupt, incomplete, DRM-protected, or mislabeled."
                            : "This book file is missing from Chicken's local library folder."
                        return
                    }
                    self.publication = publication
                    self.currentChapterIndex = nil
                    self.parent.bodyState.chapters = publication.chapters
                    self.parent.bodyState.totalPages = nil
                    self.parent.bodyState.currentPage = nil
                    self.parent.bodyState.chapterProgress = nil
                    self.parent.bodyState.currentChapterPage = nil
                    self.parent.bodyState.currentChapterPageCount = nil
                    self.parent.bodyState.readerError = nil
                    self.hasLoadedCombinedDocument = false
                    self.restoredInitialLocation = false
                    let restored = self.restoreIndex(for: publication)
                    self.parent.chapterIndex = restored
                    self.go(to: restored, force: true)
                }
            }
        }

        func go(to index: Int, force: Bool = false) {
            guard let webView, let publication, publication.spine.indices.contains(index) else { return }
            let chapter = publication.spine[index]

            if !hasLoadedCombinedDocument {
                hasLoadedCombinedDocument = true
                currentChapterIndex = index
                webView.loadFileURL(publication.combinedHTMLURL, allowingReadAccessTo: publication.rootURL)
                return
            }

            guard force || currentChapterIndex != index else { return }
            currentChapterIndex = index
            let script = "window.__chickenScrollToLocation ? window.__chickenScrollToLocation(\(index), 0) : document.getElementById('chapter-\(index)')?.scrollIntoView({ block: 'start' });"
            webView.evaluateJavaScript(script, completionHandler: nil)
            let progress = Double(index) / Double(max(publication.spine.count, 1))
            parent.onProgress(progress, EPUBLocation(href: chapter.relativePath, spineIndex: index, progression: 0, globalProgression: progress).encoded)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            applyTheme()
            // Promote the web view to first responder so its keydown listener
            // gets ←/→/Space immediately, without the user having to click
            // into the page first.
            DispatchQueue.main.async { [weak webView] in
                guard let webView, let window = webView.window else { return }
                if window.firstResponder !== webView {
                    window.makeFirstResponder(webView)
                }
            }
            if let currentChapterIndex {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    if !self.restoredInitialLocation, let location = EPUBLocation.decode(self.parent.book.lastLocation), self.locationIsValid(location) {
                        self.restoredInitialLocation = true
                        self.currentChapterIndex = location.spineIndex
                        self.parent.chapterIndex = location.spineIndex
                        self.scroll(to: location)
                    } else {
                        self.go(to: currentChapterIndex, force: true)
                    }
                }
            }
        }

        func applyTheme() {
            guard let webView else { return }
            let css = parent.makeReaderCSS()
            let isHorizontal = parent.readingMode == .paged || parent.readingMode == .spread
            let script =
                """
                (() => {
                  if (window.__chickenProgressListener) {
                    window.removeEventListener('scroll', window.__chickenProgressListener);
                  }
                  if (window.__chickenWheelTurnListener) {
                    window.removeEventListener('wheel', window.__chickenWheelTurnListener);
                  }
                  const isHorizontalReader = \(isHorizontal ? "true" : "false");
                  const isSpreadReader = \(parent.readingMode == .spread ? "true" : "false");
                  var lastWheelTurnAt = 0;

                  // The EPUB WebView renders flowable content into CSS columns,
                  // but the reader treats those columns as virtual pages. Spread
                  // mode advances by two virtual pages at a time, matching a
                  // physical open book instead of allowing free horizontal pan.
                  const __chickenPageMetrics = () => {
                    const cs = window.getComputedStyle(document.body);
                    const columnWidth = parseFloat(cs.getPropertyValue('--chicken-page-width')) || parseFloat(cs.columnWidth) || window.innerWidth;
                    const columnGap = parseFloat(cs.getPropertyValue('--chicken-column-gap')) || parseFloat(cs.columnGap) || 64;
                    const pageUnit = Math.max(320, columnWidth + columnGap);
                    const turnPages = isSpreadReader ? 2 : 1;
                    const turnUnit = isSpreadReader ? pageUnit * 2 : pageUnit;
                    const maxX = Math.max(0, Math.max(
                      document.documentElement.scrollWidth || 0,
                      document.body.scrollWidth || 0
                    ) - window.innerWidth);
                    const pageCount = Math.max(1, Math.ceil((maxX + pageUnit) / pageUnit));
                    const turnCount = Math.max(1, Math.ceil((maxX + turnUnit) / turnUnit));
                    return { pageUnit, turnPages, turnUnit, maxX, pageCount, turnCount };
                  };
                  const __chickenCurrentPage = () => {
                    const { pageUnit, pageCount } = __chickenPageMetrics();
                    return Math.max(0, Math.min(pageCount - 1, Math.round(window.scrollX / pageUnit)));
                  };
                  const __chickenCurrentTurn = () => {
                    const { turnUnit, turnCount } = __chickenPageMetrics();
                    if (Number.isFinite(window.__chickenTurnIndex)) {
                      return Math.max(0, Math.min(turnCount - 1, Math.round(window.__chickenTurnIndex)));
                    }
                    return Math.max(0, Math.min(turnCount - 1, Math.round(window.scrollX / turnUnit)));
                  };
                  const __chickenScrollToTurn = (turn, behavior = 'smooth') => {
                    const { turnUnit, maxX, turnCount } = __chickenPageMetrics();
                    const targetTurn = Math.max(0, Math.min(turnCount - 1, Math.round(turn)));
                    window.__chickenTurnIndex = targetTurn;
                    window.scrollTo({ left: Math.min(maxX, targetTurn * turnUnit), top: 0, behavior });
                  };
                  const __chickenTargetPageForTurn = (direction) => {
                    const { turnPages, pageCount, turnUnit, turnCount } = __chickenPageMetrics();
                    const current = __chickenCurrentPage();
                    if (!isSpreadReader) {
                      return Math.max(0, Math.min(pageCount - 1, current + direction));
                    }
                    const currentSpread = __chickenCurrentTurn();
                    const targetSpread = Math.max(0, Math.min(turnCount - 1, currentSpread + direction));
                    return Math.round((targetSpread * turnUnit) / __chickenPageMetrics().pageUnit);
                  };
                  const __chickenScrollToPage = (page, behavior = 'smooth') => {
                    const { pageUnit, turnUnit, maxX, pageCount, turnCount } = __chickenPageMetrics();
                    let targetPage = Math.max(0, Math.min(pageCount - 1, Math.round(page)));
                    if (isSpreadReader) {
                      const spread = Math.max(0, Math.min(turnCount - 1, Math.round((targetPage * pageUnit) / turnUnit)));
                      __chickenScrollToTurn(spread, behavior);
                    } else {
                      window.__chickenTurnIndex = Math.max(0, Math.min(turnCount - 1, Math.round((targetPage * pageUnit) / turnUnit)));
                      window.scrollTo({ left: Math.min(maxX, targetPage * pageUnit), top: 0, behavior });
                    }
                  };
                  // Bridge: also expose page metrics + jump on `window` so the
                  // Swift-side restore path and the dismantle-time progress
                  // capture can reach them via evaluateJavaScript.
                  window.__chickenScrollToPage = __chickenScrollToPage;
                  window.__chickenPageMetrics = __chickenPageMetrics;
                  window.__chickenCurrentPage = __chickenCurrentPage;
                  window.__chickenCurrentTurn = __chickenCurrentTurn;

                  window.__chickenTurnPage = (direction) => {
                    if (!isHorizontalReader) return;
                    __chickenScrollToPage(__chickenTargetPageForTurn(direction), 'smooth');
                  };

                  // Discrete page turn: opacity dip → instant scroll → fade
                  // back. Hides the column-scroll mechanic so an arrow-key or
                  // edge-tap turn feels like a page swap instead of a slide.
                  // Wheel events keep the smooth path because a trackpad
                  // swipe is a continuous gesture and shouldn't be interrupted.
                  let __chickenVeil = document.getElementById('chicken-page-veil');
                  if (!__chickenVeil) {
                    __chickenVeil = document.createElement('div');
                    __chickenVeil.id = 'chicken-page-veil';
                    __chickenVeil.setAttribute('aria-hidden', 'true');
                    document.body.appendChild(__chickenVeil);
                  }
                  __chickenVeil.style.cssText = "position: fixed; inset: 0; z-index: 9999; pointer-events: none; opacity: 0; background: " + \(Self.javascriptString(parent.palette.background.webHex)) + ";";
                  let __chickenTurnInFlight = false;
                  const __chickenReduceMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

                  window.__chickenTurnPageDiscrete = async (direction) => {
                    if (!isHorizontalReader) return;
                    if (__chickenTurnInFlight) return;
                    const target = __chickenTargetPageForTurn(direction);
                    if (__chickenReduceMotion) {
                      __chickenScrollToPage(target, 'auto');
                      return;
                    }
                    __chickenTurnInFlight = true;
                    __chickenVeil.style.transition = 'opacity 110ms cubic-bezier(0.25, 1, 0.5, 1)';
                    __chickenVeil.style.opacity = '0.92';
                    await new Promise(r => setTimeout(r, 110));
                    __chickenScrollToPage(target, 'auto');
                    // Wait one frame so the new page paints before we lift.
                    await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
                    __chickenVeil.style.transition = 'opacity 150ms cubic-bezier(0.25, 1, 0.5, 1)';
                    __chickenVeil.style.opacity = '0';
                    setTimeout(() => { __chickenTurnInFlight = false; }, 160);
                  };
                  window.__chickenWheelTurnListener = (event) => {
                    if (!isHorizontalReader) return;
                    const dominantDelta = Math.abs(event.deltaX) > Math.abs(event.deltaY) ? event.deltaX : event.deltaY;
                    if (Math.abs(dominantDelta) < 8) return;
                    event.preventDefault();
                    const now = Date.now();
                    if (now - lastWheelTurnAt < 320) return;
                    lastWheelTurnAt = now;
                    window.__chickenTurnPageDiscrete(dominantDelta > 0 ? 1 : -1);
                  };
                  window.__chickenReportProgress = () => {
                    const doc = document.documentElement;
                    const body = document.body;
                    const position = isHorizontalReader
                      ? (window.scrollX || doc.scrollLeft || body.scrollLeft || 0)
                      : (window.scrollY || doc.scrollTop || body.scrollTop || 0);
                    const length = isHorizontalReader
                      ? Math.max(doc.scrollWidth || 0, body.scrollWidth || 0) - window.innerWidth
                      : Math.max(doc.scrollHeight || 0, body.scrollHeight || 0) - window.innerHeight;
                    return length <= 0 ? 0 : Math.max(0, Math.min(1, position / length));
                  };
                  window.__chickenSectionProgress = (section) => {
                    if (!section) return 0;
                    const position = isHorizontalReader
                      ? (window.scrollX || document.documentElement.scrollLeft || document.body.scrollLeft || 0)
                      : (window.scrollY || document.documentElement.scrollTop || document.body.scrollTop || 0);
                    const start = isHorizontalReader ? (section.offsetLeft || 0) : (section.offsetTop || 0);
                    const length = isHorizontalReader
                      ? Math.max(1, section.scrollWidth - window.innerWidth * 0.75)
                      : Math.max(1, section.scrollHeight - window.innerHeight * 0.75);
                    return Math.max(0, Math.min(1, (position - start) / length));
                  };
                  window.__chickenScrollToLocation = (index, sectionProgress) => {
                    const section = document.getElementById(`chapter-${index}`);
                    if (!section) return;
                    const safeProgress = Math.max(0, Math.min(1, sectionProgress || 0));
                    if (isHorizontalReader) {
                      const { pageUnit } = __chickenPageMetrics();
                      const target = section.offsetLeft + Math.max(0, section.scrollWidth - window.innerWidth * 0.75) * safeProgress;
                      __chickenScrollToPage(Math.round(target / pageUnit), 'auto');
                    } else {
                      const target = section.offsetTop + Math.max(0, section.scrollHeight - window.innerHeight * 0.75) * safeProgress;
                      window.scrollTo({ top: target, behavior: 'auto' });
                    }
                  };
                  var lastMessageAt = 0;
                  window.__chickenProgressListener = () => {
                    const now = Date.now();
                    if (now - lastMessageAt < 220) return;
                    lastMessageAt = now;
                    const doc = document.documentElement;
                    const body = document.body;
                    const sections = Array.from(document.querySelectorAll('[data-chicken-spine-index]'));
                    let active = 0;
                    for (let i = 0; i < sections.length; i++) {
                      const rect = sections[i].getBoundingClientRect();
                      const leading = isHorizontalReader ? rect.left : rect.top;
                      const threshold = isHorizontalReader ? window.innerWidth * 0.42 : window.innerHeight * 0.34;
                      if (leading <= threshold) {
                        active = Number(sections[i].dataset.chickenSpineIndex || 0);
                      } else {
                        break;
                      }
                    }
                    const section = sections.find((s) => Number(s.dataset.chickenSpineIndex || 0) === active);
                    const sectionIndex = sections.findIndex((s) => Number(s.dataset.chickenSpineIndex || 0) === active);
                    const nextSection = sectionIndex >= 0 ? sections[sectionIndex + 1] : null;
                    const progression = window.__chickenReportProgress();
                    const sectionProgression = window.__chickenSectionProgress(section);
                    const metrics = isHorizontalReader ? __chickenPageMetrics() : null;
                    const verticalUnit = Math.max(320, window.innerHeight * 0.86);
                    const page = isHorizontalReader ? __chickenCurrentPage() : Math.floor(window.scrollY / verticalUnit);
                    const pageCount = metrics ? metrics.pageCount : Math.max(1, Math.ceil(Math.max(doc.scrollHeight, body.scrollHeight) / verticalUnit));
                    let pageWithinSpine = null;
                    let chapterPageCount = null;
                    if (section) {
                      if (isHorizontalReader && metrics) {
                        const spineFirstPage = Math.round((section.offsetLeft || 0) / metrics.pageUnit);
                        const nextSpineFirstPage = nextSection ? Math.round((nextSection.offsetLeft || 0) / metrics.pageUnit) : pageCount;
                        chapterPageCount = Math.max(1, nextSpineFirstPage - spineFirstPage);
                        pageWithinSpine = Math.max(0, Math.min(chapterPageCount - 1, page - spineFirstPage));
                      } else {
                        const spineFirstPage = Math.floor((section.offsetTop || 0) / verticalUnit);
                        chapterPageCount = Math.max(1, Math.ceil((section.scrollHeight || verticalUnit) / verticalUnit));
                        pageWithinSpine = Math.max(0, Math.min(chapterPageCount - 1, Math.floor((window.scrollY - (section.offsetTop || 0)) / verticalUnit)));
                      }
                    }
                    window.webkit.messageHandlers.chickenProgress.postMessage({ index: active, progression, sectionProgression, page, pageCount, pageWithinSpine, chapterPageCount });
                  };
                  if (window.__chickenKeyTurnListener) {
                    window.removeEventListener('keydown', window.__chickenKeyTurnListener);
                  }
                  window.__chickenKeyTurnListener = (event) => {
                    const target = event.target;
                    const tag = target && target.tagName ? target.tagName : '';
                    if (target && (target.isContentEditable || tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT')) return;
                    if (event.metaKey || event.ctrlKey || event.altKey) return;
                    const key = event.key;
                    const goForward = key === 'ArrowRight' || key === 'PageDown' || (key === ' ' && !event.shiftKey);
                    const goBack = key === 'ArrowLeft' || key === 'PageUp' || (key === ' ' && event.shiftKey);
                    if (!goForward && !goBack) return;
                    event.preventDefault();
                    if (isHorizontalReader) {
                      // Discrete inputs (arrow keys, page-up/down, space) use
                      // the veil for a discrete page-swap feel.
                      window.__chickenTurnPageDiscrete(goForward ? 1 : -1);
                    } else {
                      const step = window.innerHeight * 0.92 * (goForward ? 1 : -1);
                      window.scrollBy({ top: step, behavior: 'smooth' });
                    }
                  };
                  if (window.__chickenSnapListener) {
                    window.removeEventListener('scroll', window.__chickenSnapListener);
                  }
                  // Safety-net snap. After any scroll settles, if the viewport
                  // is off a clean spread boundary (manual drag, momentum,
                  // resize, theme change), pull it back. This is the cheap
                  // CSS-scroll-snap equivalent for multi-column layouts where
                  // individual columns aren't real DOM nodes.
                  let __chickenSnapTimer = null;
                  let __chickenSnapPending = false;
                  window.__chickenSnapListener = () => {
                    if (!isHorizontalReader) return;
                    if (__chickenSnapPending) return;
                    if (__chickenSnapTimer) clearTimeout(__chickenSnapTimer);
                    __chickenSnapTimer = setTimeout(() => {
                      const { pageUnit, turnUnit } = __chickenPageMetrics();
                      let targetPage;
                      let target;
                      if (isSpreadReader) {
                        const targetSpread = Math.round(window.scrollX / turnUnit);
                        target = targetSpread * turnUnit;
                        targetPage = Math.round(target / pageUnit);
                        window.__chickenTurnIndex = targetSpread;
                      } else {
                        targetPage = Math.round(window.scrollX / pageUnit);
                        target = targetPage * pageUnit;
                        window.__chickenTurnIndex = Math.round(target / turnUnit);
                      }
                      if (Math.abs(window.scrollX - target) > 1) {
                        __chickenSnapPending = true;
                        __chickenScrollToPage(targetPage, 'smooth');
                        setTimeout(() => { __chickenSnapPending = false; }, 320);
                      }
                    }, 180);
                  };

                  if (window.__chickenEdgeTapListener) {
                    window.removeEventListener('click', window.__chickenEdgeTapListener);
                  }
                  // Edge-tap zones: clicking the left/right third of the reader
                  // turns a page, like Apple Books. The middle third is left
                  // alone so the user can interact with selections, footnotes,
                  // and links. Suppressed when there's an active text
                  // selection or the click hits an interactive element.
                  window.__chickenEdgeTapListener = (event) => {
                    if (!isHorizontalReader) return;
                    if (event.button !== 0) return;
                    if (event.detail !== 1) return;  // ignore double/triple clicks
                    const sel = window.getSelection && window.getSelection();
                    if (sel && !sel.isCollapsed) return;
                    const t = event.target;
                    if (t && t.closest && t.closest('a, button, input, textarea, select, [contenteditable], [role=button]')) return;
                    const x = event.clientX;
                    const w = window.innerWidth;
                    if (x < w * 0.30) {
                      event.preventDefault();
                      window.__chickenTurnPageDiscrete(-1);
                    } else if (x > w * 0.70) {
                      event.preventDefault();
                      window.__chickenTurnPageDiscrete(1);
                    }
                  };

                  window.addEventListener('scroll', window.__chickenProgressListener, { passive: true });
                  window.addEventListener('scroll', window.__chickenSnapListener, { passive: true });
                  window.addEventListener('wheel', window.__chickenWheelTurnListener, { passive: false });
                  window.addEventListener('keydown', window.__chickenKeyTurnListener);
                  window.addEventListener('click', window.__chickenEdgeTapListener);
                  let style = document.getElementById('chicken-reader-style');
                  if (!style) {
                    style = document.createElement('style');
                    style.id = 'chicken-reader-style';
                    document.head.appendChild(style);
                  }
                  style.textContent = \(Self.javascriptString(css));
                  document.documentElement.style.background = \(Self.javascriptString(parent.palette.background.webHex));
                  document.body.style.background = \(Self.javascriptString(parent.palette.background.webHex));
                })();
            """
            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        func performSearchIfNeeded(_ request: ReaderSearchRequest?) {
            guard let request, lastSearchID != request.id, let webView else { return }
            lastSearchID = request.id
            let query = Self.javascriptString(request.query)
            let backwards = request.backwards ? "true" : "false"
            let script = """
            (() => {
              const query = \(query);
              if (!query) return false;
              const found = window.find(query, false, \(backwards), true, false, false, false);
              if (found && window.__chickenProgressListener) {
                window.__chickenProgressListener();
              }
              return found;
            })();
            """
            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let publication,
                  let body = message.body as? [String: Any],
                  let index = body["index"] as? Int,
                  publication.spine.indices.contains(index) else { return }

            currentChapterIndex = index
            if parent.chapterIndex != index {
                parent.chapterIndex = index
            }
            let progression = (body["progression"] as? Double) ?? 0
            let sectionProgression = (body["sectionProgression"] as? Double) ?? 0

            // JS sends `page` as 0-indexed (matching the column layout) and
            // `pageCount` as the total. Convert to a 1-indexed display value
            // here so the body state and persisted location agree on what
            // "page 47" means.
            let zeroIndexedPage = body["page"] as? Int
            let pageCount = body["pageCount"] as? Int
            let pageWithinSpine = body["pageWithinSpine"] as? Int
            let chapterPageCount = body["chapterPageCount"] as? Int
            let displayPage: Int? = zeroIndexedPage.map { max(1, $0 + 1) }
            let displayChapterPage: Int? = pageWithinSpine.map { max(1, $0 + 1) }

            if parent.bodyState.totalPages != pageCount {
                parent.bodyState.totalPages = pageCount
            }
            if parent.bodyState.currentPage != displayPage {
                parent.bodyState.currentPage = displayPage
            }
            if parent.bodyState.chapterProgress != sectionProgression {
                parent.bodyState.chapterProgress = sectionProgression
            }
            if parent.bodyState.currentChapterPage != displayChapterPage {
                parent.bodyState.currentChapterPage = displayChapterPage
            }
            if parent.bodyState.currentChapterPageCount != chapterPageCount {
                parent.bodyState.currentChapterPageCount = chapterPageCount
            }

            let location = EPUBLocation(
                href: publication.spine[index].relativePath,
                spineIndex: index,
                progression: sectionProgression,
                globalProgression: progression,
                pageNumber: displayPage,
                pageWithinSpine: pageWithinSpine
            ).encoded
            parent.onProgress(progression, location)
        }

        func captureProgress() {
            guard !isTornDown, let webView, let publication, let currentChapterIndex else { return }
            // Pull progression, page number, and pageCount in one bridged call
            // so the saved location is internally consistent. If the JS
            // helpers haven't loaded (e.g., a tear-down before didFinish),
            // fall back to nil page fields and just save progression.
            let script = """
            (function () {
              if (!window.__chickenReportProgress) return null;
              const progression = window.__chickenReportProgress();
              if (typeof window.__chickenCurrentPage !== 'function') {
                return { progression: progression, page: null, pageCount: null };
              }
              const metrics = window.__chickenPageMetrics();
              const page = window.__chickenCurrentPage();
              const sections = Array.from(document.querySelectorAll('[data-chicken-spine-index]'));
              let active = 0;
              for (let i = 0; i < sections.length; i++) {
                const rect = sections[i].getBoundingClientRect();
                if (rect.left <= window.innerWidth * 0.42) {
                  active = Number(sections[i].dataset.chickenSpineIndex || 0);
                } else { break; }
              }
              const section = sections.find(s => Number(s.dataset.chickenSpineIndex || 0) === active);
              const spineFirstPage = section ? Math.round((section.offsetLeft || 0) / metrics.pageUnit) : 0;
              return {
                progression: progression,
                page: page,
                pageCount: metrics.pageCount,
                pageWithinSpine: Math.max(0, page - spineFirstPage)
              };
            })();
            """
            webView.evaluateJavaScript(script) { [weak self, publication, currentChapterIndex] value, _ in
                guard let self, !self.isTornDown else { return }
                let info = value as? [String: Any]
                let chapterProgress = (info?["progression"] as? Double) ?? 0
                let total = Double(max(publication.spine.count, 1))
                let absolute = (Double(currentChapterIndex) + chapterProgress) / total
                let zeroPage = info?["page"] as? Int
                let pageCount = info?["pageCount"] as? Int
                let pageWithinSpine = info?["pageWithinSpine"] as? Int
                let displayPage = zeroPage.map { max(1, $0 + 1) }
                _ = pageCount  // pageCount lives on bodyState, not in the saved location
                let location = EPUBLocation(
                    href: publication.spine[currentChapterIndex].relativePath,
                    spineIndex: currentChapterIndex,
                    progression: chapterProgress,
                    globalProgression: absolute,
                    pageNumber: displayPage,
                    pageWithinSpine: pageWithinSpine
                ).encoded
                self.parent.onProgress(absolute, location)
            }
        }

        private func restoreIndex(for publication: EPUBPublication?) -> Int {
            guard let publication else { return 0 }
            guard let location = EPUBLocation.decode(parent.book.lastLocation), locationIsValid(location) else {
                return min(parent.chapterIndex, max(publication.spine.count - 1, 0))
            }
            return location.spineIndex
        }

        private func locationIsValid(_ location: EPUBLocation) -> Bool {
            guard let publication, publication.spine.indices.contains(location.spineIndex) else { return false }
            return publication.spine[location.spineIndex].relativePath == location.href
        }

        private func scroll(to location: EPUBLocation) {
            guard let webView else { return }
            let progress = max(0, min(1, location.progression))
            // Prefer page-number restore when the saved location has one. The
            // JS side clamps to current pageCount, so a bigger font that
            // shrinks page count still lands somewhere reasonable. Fall back
            // to spine + progression for older saves or vertical-mode reads.
            let script: String
            if let pageNumber = location.pageNumber {
                let zeroIndexed = max(0, pageNumber - 1)
                script = """
                if (window.__chickenScrollToPage) {
                    window.__chickenScrollToPage(\(zeroIndexed), 'auto');
                } else if (window.__chickenScrollToLocation) {
                    window.__chickenScrollToLocation(\(location.spineIndex), \(progress));
                } else {
                    document.getElementById('chapter-\(location.spineIndex)')?.scrollIntoView({ block: 'start' });
                }
                """
            } else {
                script = "window.__chickenScrollToLocation ? window.__chickenScrollToLocation(\(location.spineIndex), \(progress)) : document.getElementById('chapter-\(location.spineIndex)')?.scrollIntoView({ block: 'start' });"
            }
            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        private static func javascriptString(_ value: String) -> String {
            guard
                let data = try? JSONEncoder().encode(value),
                let encoded = String(data: data, encoding: .utf8)
            else {
                return "\"\""
            }
            return encoded
        }

        deinit {
            prepareForDismantle()
        }
    }

    private func makeReaderCSS() -> String {
        let isPaged = readingMode == .paged
        let isSpread = readingMode == .spread
        let isHorizontal = isPaged || isSpread
        let bodyMaxWidth = isHorizontal ? "none" : "\(Int(columnWidth))px"
        let effectiveFontSize = isSpread ? max(fontSize + 2, fontSize * 1.12) : fontSize
        let bodyPadding = isHorizontal ? "52px 0 36px" : "64px 56px 88px"
        let pageCSSVariables: String
        let flowCSS: String
        if isPaged {
            pageCSSVariables = "--chicken-page-width: min(\(Int(columnWidth))px, calc(100vw - 112px)); --chicken-column-gap: 64px; --chicken-page-inset: clamp(40px, 5vw, 84px);"
            flowCSS = "column-width: var(--chicken-page-width) !important; column-gap: var(--chicken-column-gap) !important; column-fill: auto !important; height: calc(100vh - 88px) !important; overflow-x: hidden !important; overflow-y: hidden !important; overscroll-behavior-x: none !important; scrollbar-width: none !important;"
        } else if isSpread {
            pageCSSVariables = "--chicken-column-gap: clamp(96px, 7vw, 160px); --chicken-page-width: calc((100vw - var(--chicken-column-gap)) / 2); --chicken-page-inset: clamp(56px, 4.6vw, 104px);"
            flowCSS = "column-width: var(--chicken-page-width) !important; column-gap: var(--chicken-column-gap) !important; column-fill: auto !important; height: calc(100vh - 88px) !important; overflow-x: hidden !important; overflow-y: hidden !important; overscroll-behavior-x: none !important; scrollbar-width: none !important;"
        } else {
            pageCSSVariables = "--chicken-page-width: \(Int(columnWidth))px; --chicken-column-gap: 0px; --chicken-page-inset: 0px;"
            flowCSS = "overflow-x: hidden !important; overflow-y: auto !important;"
        }
        let spreadCSS = isSpread
            ? """
              .chicken-spine-section h1,
              .chicken-spine-section h2,
              .chicken-spine-section h3,
              .chicken-spine-section h4,
              .chicken-spine-section h5,
              .chicken-spine-section h6,
              .chicken-spine-section header,
              .chicken-spine-section figure,
              .chicken-spine-section table {
                break-inside: avoid-column;
              }
              """
            : ""
        return """
        html {
          background: \(palette.background.webHex) !important;
          color: \(palette.text.webHex) !important;
          \(pageCSSVariables)
        }
        body {
          box-sizing: border-box;
          max-width: \(bodyMaxWidth);
          margin: 0 auto !important;
          padding: \(bodyPadding) !important;
          background: \(palette.background.webHex) !important;
          color: \(palette.text.webHex) !important;
          font-family: Georgia, 'Times New Roman', serif !important;
          font-size: \(effectiveFontSize)px !important;
          line-height: \(lineHeight) !important;
          overflow-wrap: normal;
          word-break: normal;
          \(flowCSS)
        }
        body::-webkit-scrollbar {
          width: 0 !important;
          height: 0 !important;
          display: \(isHorizontal ? "none" : "initial");
        }
        \(spreadCSS)
        .chicken-spine-section {
          box-sizing: border-box;
        }
        \(isHorizontal ? """
        .chicken-spine-section {
          padding-left: var(--chicken-page-inset) !important;
          padding-right: var(--chicken-page-inset) !important;
          -webkit-box-decoration-break: clone;
          box-decoration-break: clone;
        }
        """ : "")
        .chicken-spine-section p,
        .chicken-spine-section li,
        .chicken-spine-section blockquote,
        .chicken-spine-section dd,
        .chicken-spine-section dt,
        .chicken-spine-section figcaption {
          color: \(palette.text.webHex) !important;
          font-size: \(effectiveFontSize)px !important;
          line-height: \(lineHeight) !important;
        }
        /* Justified text + auto hyphenation give horizontal modes a printed-
           book rag, and widows/orphans prevent dangling lines at column
           boundaries. Vertical scroll mode opts out of hyphenation since
           there's no column boundary to clean up. */
        .chicken-spine-section p,
        .chicken-spine-section li,
        .chicken-spine-section blockquote,
        .chicken-spine-section dd,
        .chicken-spine-section dt {
          overflow-wrap: break-word;
          word-break: normal;
          text-align: \(isHorizontal ? "justify" : "left");
          hyphens: \(isHorizontal ? "auto" : "manual");
          -webkit-hyphens: \(isHorizontal ? "auto" : "manual");
          widows: 2;
          orphans: 2;
        }
        .chicken-spine-section h1,
        .chicken-spine-section h2,
        .chicken-spine-section h3,
        .chicken-spine-section h4,
        .chicken-spine-section h5,
        .chicken-spine-section h6 {
          color: \(palette.text.webHex) !important;
          font-family: Georgia, 'Times New Roman', serif !important;
          line-height: 1.2 !important;
        }
        /* Scene breaks. Publisher EPUBs use either a bare <hr> or a centered
           paragraph of asterisks/dingbats; both render as a quiet asterism
           rule in the muted color, sitting in the column flow. break-inside
           kept default so the ornament can land on a page edge naturally. */
        .chicken-spine-section hr {
          border: 0 !important;
          height: auto !important;
          margin: 1.6em auto !important;
          text-align: center !important;
          color: \(palette.muted.webHex) !important;
          font-family: Georgia, 'Times New Roman', serif !important;
          font-size: 0.9em !important;
          letter-spacing: 0.6em !important;
          line-height: 1 !important;
          background: transparent !important;
        }
        .chicken-spine-section hr::before {
          content: "* * *";
        }
        .chicken-spine-section table {
          display: table !important;
          width: auto !important;
          max-width: 100% !important;
          border-collapse: collapse;
          table-layout: auto !important;
          font-size: max(13px, \(effectiveFontSize - 2)px) !important;
          line-height: 1.45 !important;
          overflow-wrap: normal !important;
          word-break: normal !important;
          white-space: normal !important;
        }
        .chicken-spine-section th,
        .chicken-spine-section td {
          display: table-cell !important;
          color: \(palette.text.webHex) !important;
          font-size: inherit !important;
          line-height: inherit !important;
          padding: 0.28em 0.7em 0.28em 0 !important;
          vertical-align: top !important;
          overflow-wrap: normal !important;
          word-break: normal !important;
          min-width: 4.5em;
        }
        .chicken-spine-section th {
          font-weight: 600 !important;
        }
        .chicken-spine-section a { color: \(palette.muted.webHex) !important; }
        .chicken-spine-section img,
        .chicken-spine-section svg,
        .chicken-spine-section video {
          max-width: 100% !important;
          height: auto !important;
        }
        ::selection {
          background: rgba(189, 153, 87, 0.36);
        }
        """
    }
}

private struct EPUBPublication {
    let rootURL: URL
    let combinedHTMLURL: URL
    let spine: [EPUBSpineItem]

    nonisolated var chapters: [ReaderChapter] {
        spine.enumerated().map { index, item in
            ReaderChapter(
                id: index,
                title: item.title,
                subtitle: nil,
                level: item.tocLevel
            )
        }
    }

    nonisolated static func load(from archiveURL: URL) -> EPUBPublication? {
        let fileManager = FileManager.default
        let root = epubCacheRoot(for: archiveURL)

        do {
            if !fileManager.fileExists(atPath: root.path) {
                try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
                guard unzip(archiveURL, to: root) else { return nil }
            }
        } catch {
            return nil
        }

        let containerURL = root.appendingPathComponent("META-INF/container.xml")
        guard
            let containerXML = try? String(contentsOf: containerURL, encoding: .utf8),
            let packagePath = firstXMLAttribute("full-path", in: containerXML)
        else {
            return nil
        }

        let packageURL = root.appendingPathComponent(packagePath)
        guard let packageXML = try? String(contentsOf: packageURL, encoding: .utf8) else {
            return nil
        }

        let manifest = manifestItems(from: packageXML)
        let spineIDs = spineItemRefs(from: packageXML)
        let tocEntries = tableOfContents(from: packageXML, packageURL: packageURL, manifest: manifest)
        let packageDirectory = packageURL.deletingLastPathComponent()
        let spine = spineIDs.compactMap { idref -> EPUBSpineItem? in
            guard let item = manifest[idref] else { return nil }
            guard item.isReadableDocument else { return nil }
            let relative = normalizedEPUBPath(item.href, relativeTo: packagePath)
            let fileURL = packageDirectory.appendingPathComponent(item.href.removingPercentEncoding ?? item.href)
            return EPUBSpineItem(
                id: idref,
                title: tocEntries[relative]?.title ?? item.title ?? documentTitle(from: fileURL) ?? title(from: item.href),
                relativePath: relative,
                fileURL: fileURL,
                tocLevel: tocEntries[relative]?.level ?? 0
            )
        }

        guard !spine.isEmpty else { return nil }
        let combinedHTMLURL = root.appendingPathComponent("__chicken-reader.html")
        if !fileManager.fileExists(atPath: combinedHTMLURL.path) {
            guard writeCombinedReaderHTML(spine: spine, to: combinedHTMLURL) else { return nil }
        }
        return EPUBPublication(rootURL: root, combinedHTMLURL: combinedHTMLURL, spine: spine)
    }

    nonisolated private static func epubCacheRoot(for archiveURL: URL) -> URL {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let values = try? archiveURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let signature = "\(archiveURL.path)|\(values?.fileSize ?? 0)|\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        let safeName = archiveURL.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "/", with: "-")
        return base
            .appendingPathComponent("Chicken", isDirectory: true)
            .appendingPathComponent("EPUBCache", isDirectory: true)
            .appendingPathComponent("\(safeName)-\(signature.stableReaderHash)", isDirectory: true)
    }

    nonisolated private static func unzip(_ archiveURL: URL, to destination: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", "-o", archiveURL.path, "-d", destination.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    nonisolated private static func manifestItems(from xml: String) -> [String: EPUBManifestItem] {
        let itemPattern = #"<item\b([^>]*)>"#
        guard let regex = try? NSRegularExpression(pattern: itemPattern, options: [.caseInsensitive]) else { return [:] }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        var items: [String: EPUBManifestItem] = [:]

        for match in regex.matches(in: xml, range: range) {
            guard let attrRange = Range(match.range(at: 1), in: xml) else { continue }
            let attrs = String(xml[attrRange])
            guard
                let id = firstXMLAttribute("id", in: attrs),
                let href = firstXMLAttribute("href", in: attrs)
            else {
                continue
            }
            let mediaType = firstXMLAttribute("media-type", in: attrs)
            let properties = firstXMLAttribute("properties", in: attrs)
            items[id] = EPUBManifestItem(
                id: id,
                href: href,
                mediaType: mediaType,
                properties: properties,
                title: firstXMLAttribute("title", in: attrs)
            )
        }
        return items
    }

    nonisolated private static func tableOfContents(
        from packageXML: String,
        packageURL: URL,
        manifest: [String: EPUBManifestItem]
    ) -> [String: EPUBTOCEntry] {
        if let navItem = manifest.values.first(where: { $0.properties?.contains("nav") == true }) {
            let navURL = packageURL.deletingLastPathComponent().appendingPathComponent(navItem.href.removingPercentEncoding ?? navItem.href)
            if let navHTML = try? String(contentsOf: navURL, encoding: .utf8) {
                let titles = navigationTitles(from: navHTML, navURL: navURL, packageURL: packageURL)
                if !titles.isEmpty { return titles }
            }
        }

        if let ncxItem = manifest.values.first(where: { $0.mediaType == "application/x-dtbncx+xml" || $0.href.lowercased().hasSuffix(".ncx") }) {
            let ncxURL = packageURL.deletingLastPathComponent().appendingPathComponent(ncxItem.href.removingPercentEncoding ?? ncxItem.href)
            if let ncxXML = try? String(contentsOf: ncxURL, encoding: .utf8) {
                return ncxTitles(from: ncxXML, ncxURL: ncxURL, packageURL: packageURL)
            }
        }

        return [:]
    }

    nonisolated private static func navigationTitles(from html: String, navURL: URL, packageURL: URL) -> [String: EPUBTOCEntry] {
        let navChunk = firstRegexCapture(
            pattern: #"<nav\b(?=[^>]*(?:epub:type|type)\s*=\s*["'][^"']*(?:toc|contents)[^"']*["'])[^>]*>([\s\S]*?)</nav>"#,
            in: html
        ) ?? html
        return linkTitles(from: navChunk, baseURL: navURL, packageURL: packageURL, level: 0)
    }

    nonisolated private static func linkTitles(from html: String, baseURL: URL, packageURL: URL, level: Int) -> [String: EPUBTOCEntry] {
        let itemPattern = #"<li\b[^>]*>([\s\S]*?)</li>"#
        guard let itemRegex = try? NSRegularExpression(pattern: itemPattern, options: [.caseInsensitive]) else { return directLinkTitles(from: html, baseURL: baseURL, packageURL: packageURL, level: level) }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = itemRegex.matches(in: html, range: range)
        guard !matches.isEmpty else {
            return directLinkTitles(from: html, baseURL: baseURL, packageURL: packageURL, level: level)
        }
        var titles: [String: EPUBTOCEntry] = [:]

        for match in matches {
            guard let itemRange = Range(match.range(at: 1), in: html) else { continue }
            let item = String(html[itemRange])
            titles.merge(directLinkTitles(from: item, baseURL: baseURL, packageURL: packageURL, level: level)) { current, _ in current }
            if let nested = firstRegexCapture(pattern: #"<ol\b[^>]*>([\s\S]*?)</ol>"#, in: item)
                ?? firstRegexCapture(pattern: #"<ul\b[^>]*>([\s\S]*?)</ul>"#, in: item) {
                titles.merge(linkTitles(from: nested, baseURL: baseURL, packageURL: packageURL, level: level + 1)) { current, _ in current }
            }
        }

        return titles
    }

    nonisolated private static func directLinkTitles(from html: String, baseURL: URL, packageURL: URL, level: Int) -> [String: EPUBTOCEntry] {
        let pattern = #"<a\b(?=[^>]*\bhref\s*=\s*["']([^"']+)["'])[^>]*>([\s\S]*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [:] }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var titles: [String: EPUBTOCEntry] = [:]

        for match in regex.matches(in: html, range: range) {
            guard
                let hrefRange = Range(match.range(at: 1), in: html),
                let titleRange = Range(match.range(at: 2), in: html)
            else { continue }

            let key = normalizedTOCPath(String(html[hrefRange]), baseURL: baseURL, packageURL: packageURL)
            let clean = cleanTitle(String(html[titleRange]))
            if !clean.isEmpty {
                titles[key] = EPUBTOCEntry(title: clean, level: level)
            }
        }

        return titles
    }

    nonisolated private static func ncxTitles(from xml: String, ncxURL: URL, packageURL: URL) -> [String: EPUBTOCEntry] {
        let pattern = #"<navPoint\b[^>]*>([\s\S]*?)</navPoint>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [:] }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        var titles: [String: EPUBTOCEntry] = [:]

        for match in regex.matches(in: xml, range: range) {
            guard let pointRange = Range(match.range(at: 1), in: xml) else { continue }
            let point = String(xml[pointRange])
            guard
                let src = firstXMLAttribute("src", in: point),
                let text = firstRegexCapture(pattern: #"<text\b[^>]*>([\s\S]*?)</text>"#, in: point)
            else { continue }

            let key = normalizedTOCPath(src, baseURL: ncxURL, packageURL: packageURL)
            let clean = cleanTitle(text)
            if !clean.isEmpty {
                let level = max(0, point.components(separatedBy: "<navPoint").count - 2)
                titles[key] = EPUBTOCEntry(title: clean, level: level)
            }
        }

        return titles
    }

    nonisolated private static func normalizedTOCPath(_ href: String, baseURL: URL, packageURL: URL) -> String {
        let path = String(href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
            .removingPercentEncoding ?? href
        let absolute = baseURL.deletingLastPathComponent().appendingPathComponent(path).standardizedFileURL
        let packageDir = packageURL.deletingLastPathComponent().standardizedFileURL
        let packagePath = packageDir.path
        guard absolute.path.hasPrefix(packagePath) else { return path }
        return String(absolute.path.dropFirst(packagePath.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    nonisolated private static func documentTitle(from fileURL: URL) -> String? {
        guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        let candidate = firstRegexCapture(pattern: #"<h[1-3]\b[^>]*>([\s\S]*?)</h[1-3]>"#, in: raw)
            ?? firstRegexCapture(pattern: #"<title\b[^>]*>([\s\S]*?)</title>"#, in: raw)
        let clean = cleanTitle(candidate ?? "")
        return clean.isEmpty ? nil : clean
    }

    nonisolated private static func cleanTitle(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<!\[CDATA\[(.*?)\]\]>"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: #"[\s\n\r\t]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func writeCombinedReaderHTML(spine: [EPUBSpineItem], to destination: URL) -> Bool {
        let sections = spine.enumerated().map { index, item -> String in
            let raw = (try? String(contentsOf: item.fileURL, encoding: .utf8))
                ?? (try? String(contentsOf: item.fileURL, encoding: .isoLatin1))
                ?? ""
            let headLinks = stylesheetLinks(from: raw, relativeTo: item.fileURL)
            let body = bodyHTML(from: raw)
            let rewrittenBody = rewriteResourceURLs(in: body, relativeTo: item.fileURL)

            return """
            <section class="chicken-spine-section" id="chapter-\(index)" data-chicken-spine-index="\(index)">
            \(headLinks)
            \(rewrittenBody)
            </section>
            """
        }.joined(separator: "\n")

        let html =
        """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <style>
            .chicken-spine-section {
              min-height: 60vh;
              padding-bottom: 3.2rem;
              margin-bottom: 2.6rem;
              border-bottom: 1px solid rgba(31, 27, 22, 0.10);
            }
            .chicken-spine-section:last-child {
              border-bottom: 0;
            }
          </style>
        </head>
        <body class="chicken-reader-body">
        \(sections)
        </body>
        </html>
        """

        do {
            try html.write(to: destination, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    nonisolated private static func bodyHTML(from html: String) -> String {
        let pattern = #"<body\b[^>]*>([\s\S]*?)</body>"#
        return firstRegexCapture(pattern: pattern, in: html) ?? html
    }

    nonisolated private static func stylesheetLinks(from html: String, relativeTo fileURL: URL) -> String {
        let pattern = #"<link\b[^>]*rel\s*=\s*["'][^"']*stylesheet[^"']*["'][^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return "" }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: html) else { return nil }
            return rewriteResourceURLs(in: String(html[matchRange]), relativeTo: fileURL)
        }.joined(separator: "\n")
    }

    nonisolated private static func rewriteResourceURLs(in html: String, relativeTo fileURL: URL) -> String {
        let pattern = #"\b(src|href)\s*=\s*["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return html }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).reversed()
        let result = NSMutableString(string: html)

        for match in matches {
            guard match.numberOfRanges >= 3 else { continue }
            let attribute = ns.substring(with: match.range(at: 1))
            let value = ns.substring(with: match.range(at: 2))
            guard let rewritten = rewrittenResourceURL(value, relativeTo: fileURL) else { continue }
            result.replaceCharacters(in: match.range, with: "\(attribute)=\"\(rewritten)\"")
        }

        return String(result)
    }

    nonisolated private static func rewrittenResourceURL(_ value: String, relativeTo fileURL: URL) -> String? {
        if value.hasPrefix("#")
            || value.hasPrefix("http://")
            || value.hasPrefix("https://")
            || value.hasPrefix("data:")
            || value.hasPrefix("mailto:")
            || value.hasPrefix("file://") {
            return nil
        }

        let parts = value.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let path = String(parts.first ?? "")
        let fragment = parts.count > 1 ? "#\(parts[1])" : ""
        guard !path.isEmpty else { return nil }

        let decoded = path.removingPercentEncoding ?? path
        let absolute = fileURL.deletingLastPathComponent().appendingPathComponent(decoded).standardizedFileURL
        return absolute.absoluteString + fragment
    }

    nonisolated private static func spineItemRefs(from xml: String) -> [String] {
        let pattern = #"<itemref\b(?=[^>]*\bidref\s*=\s*["']([^"']+)["'])[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        return regex.matches(in: xml, range: range).compactMap { match in
            guard let idRange = Range(match.range(at: 1), in: xml) else { return nil }
            return String(xml[idRange])
        }
    }

    nonisolated private static func firstXMLAttribute(_ name: String, in xml: String) -> String? {
        let pattern = #"\#(NSRegularExpression.escapedPattern(for: name))\s*=\s*["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        guard
            let match = regex.firstMatch(in: xml, range: range),
            let captureRange = Range(match.range(at: 1), in: xml)
        else {
            return nil
        }
        return String(xml[captureRange])
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
    }

    nonisolated private static func firstRegexCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard
            let match = regex.firstMatch(in: text, range: range),
            match.numberOfRanges > 1,
            let captureRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return String(text[captureRange])
    }

    nonisolated private static func normalizedEPUBPath(_ href: String, relativeTo packagePath: String) -> String {
        let packageDirectory = (packagePath as NSString).deletingLastPathComponent
        if packageDirectory.isEmpty { return href }
        return (packageDirectory as NSString).appendingPathComponent(href)
    }

    nonisolated private static func title(from href: String) -> String {
        let raw = (href.removingPercentEncoding ?? href)
            .split(separator: "/")
            .last
            .map(String.init) ?? href
        return raw
            .replacingOccurrences(of: ".xhtml", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: ".html", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct EPUBManifestItem {
    let id: String
    let href: String
    let mediaType: String?
    let properties: String?
    let title: String?

    nonisolated var isReadableDocument: Bool {
        let lowerHref = href.lowercased()
        return mediaType?.contains("html") == true
            || lowerHref.hasSuffix(".xhtml")
            || lowerHref.hasSuffix(".html")
            || lowerHref.hasSuffix(".htm")
    }
}

private struct EPUBTOCEntry: Hashable {
    let title: String
    let level: Int
}

private struct EPUBSpineItem {
    let id: String
    let title: String
    let relativePath: String
    let fileURL: URL
    let tocLevel: Int
}

private extension String {
    nonisolated var stableReaderHash: String {
        var hash: UInt64 = 5381
        for byte in utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }
}

private extension Color {
    var webHex: String {
        let nsColor = NSColor(self).usingColorSpace(.sRGB) ?? .textColor
        let red = max(0, min(255, Int(round(nsColor.redComponent * 255))))
        let green = max(0, min(255, Int(round(nsColor.greenComponent * 255))))
        let blue = max(0, min(255, Int(round(nsColor.blueComponent * 255))))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

// MARK: - Text body

private struct TextReaderBody: View {
    let book: Book
    let palette: ReaderPalette
    @Binding var chapterIndex: Int
    @Binding var bodyState: ReaderBodyState
    @Binding var selection: ReaderSelection?
    let highlights: [Highlight]
    let fontSize: CGFloat
    let lineHeight: CGFloat
    let columnWidth: CGFloat

    @EnvironmentObject private var library: LocalLibraryStore
    @State private var content: String = ""
    @State private var loaded = false

    var body: some View {
        ScrollView {
            ZStack(alignment: .topLeading) {
                Color.clear
                    .frame(height: 0)
                    .onAppear {
                        if !loaded {
                            loaded = true
                            Task { await load() }
                        }
                    }

                if !content.isEmpty {
                    TextRenderingView(
                        content: content,
                        palette: palette,
                        highlights: highlights,
                        fontSize: fontSize,
                        lineHeight: lineHeight,
                        columnWidth: columnWidth,
                        clearSelectionToken: bodyState.clearSelectionRequest,
                        onSelection: { sel in selection = sel }
                    )
                    .padding(.horizontal, 56)
                    .padding(.vertical, 64)
                    .frame(maxWidth: .infinity)
                } else if loaded {
                    Text("Preview unavailable for \(book.originalFileName).")
                        .font(.chickenSerif(15))
                        .foregroundStyle(palette.muted)
                        .padding(56)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .background(palette.background)
    }

    private func load() async {
        let url = library.fileURL(for: book)
        let raw = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        await MainActor.run {
            content = raw
            let chapter = ReaderChapter(
                id: 0,
                title: book.title,
                subtitle: nil
            )
            bodyState.chapters = [chapter]
            bodyState.totalPages = nil
            bodyState.currentPage = nil
        }
    }
}

// MARK: - NSTextView wrapper

private struct TextRenderingView: NSViewRepresentable {
    let content: String
    let palette: ReaderPalette
    let highlights: [Highlight]
    let fontSize: CGFloat
    let lineHeight: CGFloat
    let columnWidth: CGFloat
    let clearSelectionToken: UUID
    let onSelection: (ReaderSelection?) -> Void

    func makeNSView(context: Context) -> SelectionAwareTextView {
        let view = SelectionAwareTextView()
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.allowsUndo = false
        view.isRichText = false
        view.usesFindBar = false
        view.textContainerInset = NSSize(width: 0, height: 0)
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.delegate = context.coordinator
        view.onSelection = { [weak view] in
            guard let view else { return }
            let range = view.selectedRange()
            guard range.length > 0,
                  let storage = view.textStorage,
                  let layout = view.layoutManager,
                  let container = view.textContainer else {
                context.coordinator.lastSelection = nil
                onSelection(nil)
                return
            }
            let nsString = storage.string as NSString
            let selectedText = nsString.substring(with: range)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard selectedText.count >= 3 else {
                context.coordinator.lastSelection = nil
                onSelection(nil)
                return
            }
            let glyphRange = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = layout.boundingRect(forGlyphRange: glyphRange, in: container)
            let viewPoint = CGPoint(x: rect.midX, y: rect.minY)
            let windowPoint = view.convert(viewPoint, to: nil)
            context.coordinator.lastSelection = ReaderSelection(text: selectedText, anchor: windowPoint)
            onSelection(context.coordinator.lastSelection)
        }
        return view
    }

    func updateNSView(_ view: SelectionAwareTextView, context: Context) {
        view.textContainer?.containerSize = NSSize(width: columnWidth, height: .greatestFiniteMagnitude)
        view.textColor = NSColor(palette.text)

        if context.coordinator.lastContent != content
            || context.coordinator.lastFontSize != fontSize
            || context.coordinator.lastLineHeight != lineHeight
            || context.coordinator.lastTheme != palette
            || context.coordinator.lastHighlights != highlights {
            let attributed = Self.makeAttributedString(
                content: content,
                palette: palette,
                fontSize: fontSize,
                lineHeight: lineHeight,
                highlights: highlights
            )
            view.textStorage?.setAttributedString(attributed)
            context.coordinator.lastContent = content
            context.coordinator.lastFontSize = fontSize
            context.coordinator.lastLineHeight = lineHeight
            context.coordinator.lastTheme = palette
            context.coordinator.lastHighlights = highlights
        }

        if context.coordinator.lastClearToken != clearSelectionToken {
            context.coordinator.lastClearToken = clearSelectionToken
            view.setSelectedRange(NSRange(location: 0, length: 0))
        }

        view.invalidateIntrinsicContentSize()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onSelection: onSelection) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var lastContent: String = ""
        var lastFontSize: CGFloat = 0
        var lastLineHeight: CGFloat = 0
        var lastTheme: ReaderPalette? = nil
        var lastHighlights: [Highlight] = []
        var lastClearToken: UUID? = nil
        var lastSelection: ReaderSelection?
        let onSelection: (ReaderSelection?) -> Void

        init(onSelection: @escaping (ReaderSelection?) -> Void) {
            self.onSelection = onSelection
        }
    }

    // MARK: Attributed string assembly

    private static func makeAttributedString(
        content: String,
        palette: ReaderPalette,
        fontSize: CGFloat,
        lineHeight: CGFloat,
        highlights: [Highlight]
    ) -> NSAttributedString {
        let paragraphs = content
            .split(separator: "\n\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let result = NSMutableAttributedString()

        let bodyDescriptor = NSFont.systemFont(ofSize: fontSize).fontDescriptor
            .withDesign(.serif) ?? NSFont.systemFont(ofSize: fontSize).fontDescriptor
        let bodyFont = NSFont(descriptor: bodyDescriptor, size: fontSize)
            ?? NSFont.systemFont(ofSize: fontSize)

        let dropCapSize = round(fontSize * 3.4)
        let dropCapDescriptor = NSFont.systemFont(ofSize: dropCapSize, weight: .medium).fontDescriptor
            .withDesign(.serif) ?? NSFont.systemFont(ofSize: dropCapSize, weight: .medium).fontDescriptor
        let dropCapFont = NSFont(descriptor: dropCapDescriptor, size: dropCapSize)
            ?? NSFont.systemFont(ofSize: dropCapSize, weight: .medium)

        let bodyParagraph = NSMutableParagraphStyle()
        bodyParagraph.lineHeightMultiple = lineHeight
        bodyParagraph.paragraphSpacing = round(fontSize * 1.1)
        bodyParagraph.alignment = .natural
        bodyParagraph.hyphenationFactor = 0.6

        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: NSColor(palette.text),
            .paragraphStyle: bodyParagraph,
            .kern: 0.05
        ]

        for (paragraphIndex, paragraph) in paragraphs.enumerated() {
            if paragraphIndex == 0, let firstChar = paragraph.first {
                let dropCapParagraph = NSMutableParagraphStyle()
                dropCapParagraph.lineHeightMultiple = lineHeight
                dropCapParagraph.paragraphSpacing = round(fontSize * 1.1)
                dropCapParagraph.alignment = .natural
                dropCapParagraph.hyphenationFactor = 0.6
                dropCapParagraph.firstLineHeadIndent = 0
                dropCapParagraph.headIndent = 0

                let dropCapAttrs: [NSAttributedString.Key: Any] = [
                    .font: dropCapFont,
                    .foregroundColor: NSColor(palette.text),
                    .baselineOffset: -round(dropCapSize - fontSize * 1.1),
                    .kern: 0.0
                ]
                let dropString = NSMutableAttributedString(string: String(firstChar), attributes: dropCapAttrs)

                let rest = String(paragraph.dropFirst())
                let restString = NSMutableAttributedString(string: rest, attributes: bodyAttrs)

                let merged = NSMutableAttributedString()
                merged.append(dropString)
                merged.append(restString)
                merged.addAttribute(.paragraphStyle, value: dropCapParagraph, range: NSRange(location: 0, length: merged.length))
                result.append(merged)
            } else {
                result.append(NSAttributedString(string: paragraph, attributes: bodyAttrs))
            }

            if paragraphIndex < paragraphs.count - 1 {
                result.append(NSAttributedString(string: "\n\n", attributes: bodyAttrs))
            }
        }

        // Apply existing highlights
        let nsString = result.string as NSString
        for highlight in highlights {
            let range = nsString.range(of: highlight.text)
            if range.location != NSNotFound {
                result.addAttribute(.backgroundColor, value: NSColor(highlight.color.fill), range: range)
            }
        }

        return result
    }
}

final class SelectionAwareTextView: NSTextView {
    var onSelection: (() -> Void)?

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        DispatchQueue.main.async { [weak self] in self?.onSelection?() }
    }

    override func keyUp(with event: NSEvent) {
        super.keyUp(with: event)
        DispatchQueue.main.async { [weak self] in self?.onSelection?() }
    }
}
