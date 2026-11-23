import ChickenKit
import SwiftUI

struct ReaderLoader: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppRouter.self) private var router
    let bookID: UUID

    var body: some View {
        Group {
            if let book = library.book(id: bookID) {
                ReaderView(book: book, library: library, initialJump: router.consumeJumpTarget(for: bookID))
                    .id(bookID)
                    .readingActivity(for: book, library: library)
            } else {
                ContentUnavailableView(
                    "Book Unavailable",
                    systemImage: "book.closed",
                    description: Text("This book is no longer in your library.")
                )
            }
        }
        .readingTheme(library.preferences.theme)
    }
}

struct ReaderView: View {
    private enum BookFileState: Equatable {
        case downloading(attempt: Int)
        case ready(URL)
        case failed(String, attempt: Int)

        var url: URL? {
            if case .ready(let url) = self { return url }
            return nil
        }
    }

    private struct RemotePositionOffer: Equatable {
        var baseline: Date = .distantPast
        var offered: ReadingPosition?
        var dismissedAt: Date?
    }

    let library: LibraryStore
    @State private var model: ReaderModel

    @Environment(AppRouter.self) private var router
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showChapters = !ReaderView.prefersCompactLayout
    @State private var showAnnotations = false
    @State private var showTypography = false
    @State private var showSearch = false
    @State private var searchText = ""
    @State private var chromeHidden = false
    @State private var showingZenHint = false
    @State private var zenHintTask: Task<Void, Never>?
    @State private var coverTimedOut = false
    @State private var zenHover = false
    @State private var availableWidth: CGFloat = 1200
    @State private var fileState: BookFileState
    @State private var remoteOffer = RemotePositionOffer()
    @State private var engineReloadToken = UUID()
    @State private var catchUpDate: Date?
    @State private var quoteCardRequest: QuoteCardRequest?

    init(book: Book, library: LibraryStore, initialJump: JumpTarget? = nil) {
        self.library = library
        _model = State(initialValue: ReaderModel(book: book, library: library, defaultMode: Self.defaultMode, initialJump: initialJump))
        if let url = library.readableFileURL(for: book) {
            _fileState = State(initialValue: .ready(url))
        } else {
            _fileState = State(initialValue: .downloading(attempt: 0))
        }
        if let lastOpened = book.lastOpenedAt,
           book.progress > 0.03,
           !book.isFinished,
           Date().timeIntervalSince(lastOpened) >= 18 * 3600 {
            _catchUpDate = State(initialValue: lastOpened)
        }
    }

    private static var debugPanel: String? {
        #if DEBUG
        ProcessInfo.processInfo.environment["CHICKEN_DEBUG_PANEL"]
        #else
        nil
        #endif
    }

    private static var prefersCompactLayout: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    private static var defaultMode: ReadingMode { prefersCompactLayout ? .paged : .scroll }

    private var isCompact: Bool { sizeClass == .compact }
    private var chromeVisible: Bool { !model.isZen && !chromeHidden }
    private var book: Book { model.book }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                if showChapters && !isCompact && chromeVisible {
                    ChaptersList(model: model)
                        .frame(width: 270)
                        .background(palette.surface.opacity(0.6))
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    Rectangle().fill(palette.border).frame(width: 0.5)
                }
                readingSurface
            }
            .background(palette.background.ignoresSafeArea())
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
            .toolbar { toolbar }
            .toolbarVisibility(chromeVisible ? .automatic : .hidden, for: Self.toolbarPlacement)
            .navigationTitle(book.displayTitle)
            #if os(macOS)
            .navigationSubtitle(model.chapters.isEmpty ? book.displayAuthor : model.chapterTitle)
            #else
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .inspector(isPresented: $showAnnotations) {
                AnnotationsList(model: model, onShareQuote: presentQuoteCard)
                    .inspectorColumnWidth(min: 260, ideal: 310, max: 400)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: compactChapters) {
                NavigationStack {
                    ChaptersList(model: model) { showChapters = false }
                        .navigationTitle("Contents")
                        #if !os(macOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showChapters = false }
                            }
                        }
                }
                .presentationDetents([.medium, .large])
                .readingTheme(library.preferences.theme)
            }
            .sheet(isPresented: $model.showingFinishedRitual) {
                BookFinishedSheet(
                    book: book,
                    onShareQuote: { highlight in
                        model.showingFinishedRitual = false
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(320))
                            presentQuoteCard(highlight)
                        }
                    },
                    onCloseReader: {
                        model.showingFinishedRitual = false
                        dismiss()
                    },
                    onKeepReading: {
                        model.showingFinishedRitual = false
                    },
                    onOpenNext: { nextBook in
                        model.showingFinishedRitual = false
                        dismiss()
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(250))
                            router.presentedReader = ReaderPresentation(id: nextBook.id, source: nil)
                        }
                    }
                )
                .environment(library)
                .readingTheme(library.preferences.theme)
            }
            .sheet(item: $quoteCardRequest) { request in
                QuoteCardSheet(request: request)
                    .readingTheme(library.preferences.theme)
            }
        }
        #if os(iOS)
        .statusBarHidden(!chromeVisible)
        .persistentSystemOverlays(chromeVisible ? .automatic : .hidden)
        #endif
        .animation(reduceMotion ? .easeInOut(duration: 0.12) : ChickenMotion.standard, value: chromeVisible)
        .animation(reduceMotion ? nil : ChickenMotion.micro, value: showChapters)
        .onAppear {
            remoteOffer.baseline = library.position(for: book)?.updatedAt ?? .distantPast
            library.markOpened(book)
            library.setOpen(true, book)
            if let jump = router.consumeJumpTarget(for: book.id) {
                model.applyExternalJump(jump)
            }
        }
        .onChange(of: router.pendingJumps[book.id]) { _, target in
            guard target != nil, let jump = router.consumeJumpTarget(for: book.id) else { return }
            model.applyExternalJump(jump)
        }
        #if DEBUG
        .task {
            guard let panel = Self.debugPanel else { return }
            try? await Task.sleep(for: .seconds(1.2))
            switch panel {
            case "annotations": showAnnotations = true
            case "typography": showTypography = true
            case "search": showSearch = true
            case "contents": showChapters = true
            case "readaloud": model.readAloud.start()
            case "finished": model.completeBookAndCelebrate()
            case "catchup": catchUpDate = Date().addingTimeInterval(-3 * 86_400)
            default: break
            }
        }
        #endif
        .onDisappear {
            zenHintTask?.cancel()
            model.readAloud.stop()
            model.engine?.captureLocation()
            model.flushPreferences()
            library.setOpen(false, book)
            library.save()
        }
        .onChange(of: showAnnotations) { _, shown in
            if shown && availableWidth < 1100 { showChapters = false }
        }
        .onChange(of: showChapters) { _, shown in
            if shown && !isCompact && availableWidth < 1100 { showAnnotations = false }
        }
        .onChange(of: showSearch) { _, shown in
            if !shown { model.searchMatchSummary = nil }
        }
        .onChange(of: model.fontSize) { model.savePreferences() }
        .onChange(of: model.lineHeight) { model.savePreferences() }
        .onChange(of: model.columnWidth) { model.savePreferences() }
        .onChange(of: model.typeface) { model.savePreferences() }
        .onChange(of: model.readingMode) { model.savePreferences() }
        .onChange(of: model.darkModePDF) { model.savePreferences() }
        .onChange(of: model.isZen) { _, zen in
            model.savePreferences()
            if zen {
                showAnnotations = false
                showSearch = false
                showTypography = false
            }
            guard !Platform.isMac else { return }
            zenHintTask?.cancel()
            showingZenHint = zen
            if zen {
                zenHintTask = Task {
                    try? await Task.sleep(for: .seconds(2.8))
                    guard !Task.isCancelled else { return }
                    showingZenHint = false
                }
            }
        }
        .onKeyPress(.escape) {
            if model.activeImage != nil {
                model.activeImage = nil
                return .handled
            }
            if model.activeFootnote != nil {
                model.activeFootnote = nil
                return .handled
            }
            if catchUpDate != nil {
                catchUpDate = nil
                return .handled
            }
            if model.isZen {
                model.isZen = false
                return .handled
            }
            if showSearch {
                showSearch = false
                return .handled
            }
            return .ignored
        }
    }

    private func presentQuoteCard(_ highlight: Highlight) {
        quoteCardRequest = QuoteCardRequest(
            quote: highlight.text,
            note: highlight.note,
            bookTitle: book.displayTitle,
            author: book.displayAuthor,
            highlightColor: highlight.color,
            coverTintIndex: book.coverTintIndex
        )
    }

    private func presentQuoteCard(text: String) {
        quoteCardRequest = QuoteCardRequest(
            quote: text,
            note: "",
            bookTitle: book.displayTitle,
            author: book.displayAuthor,
            highlightColor: .amber,
            coverTintIndex: book.coverTintIndex
        )
    }

    private static var toolbarPlacement: ToolbarPlacement {
        #if os(macOS)
        .windowToolbar
        #else
        .navigationBar
        #endif
    }

    private var compactChapters: Binding<Bool> {
        Binding(get: { showChapters && isCompact }, set: { showChapters = $0 })
    }

    private var readingSurface: some View {
        engineView
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                ReaderTopBannerOverlay(
                    model: model,
                    book: book,
                    remoteOffered: remoteOffer.offered,
                    catchUpDate: catchUpDate,
                    fileReady: fileState.url != nil,
                    coverTimedOut: coverTimedOut,
                    showSearch: showSearch,
                    onDismissFurther: dismissFurther,
                    onDismissCatchUp: { self.catchUpDate = nil }
                )
            }
            .animation(reduceMotion ? nil : ChickenMotion.standard, value: remoteOffer.offered?.updatedAt)
            .animation(reduceMotion ? nil : ChickenMotion.standard, value: catchUpDate)
            .task {
                try? await Task.sleep(for: .seconds(2))
                checkFurtherPosition()
            }
            .onChange(of: library.remoteChangeGeneration) { checkFurtherPosition() }
            .overlay {
                ReaderCoverWaitingOverlay(
                    model: model,
                    book: book,
                    fileReady: fileState.url != nil,
                    coverTimedOut: coverTimedOut,
                    isCompact: isCompact,
                    reduceMotion: reduceMotion
                )
            }
            .task(id: fileState.url) {
                guard fileState.url != nil else { return }
                coverTimedOut = false
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                coverTimedOut = true
            }
            .overlay(alignment: .bottom) {
                if showingZenHint {
                    Label("Tap the middle of the page to show controls", systemImage: "hand.tap")
                        .font(.chickenUI(13, weight: .medium))
                        .foregroundStyle(palette.text)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .animation(reduceMotion ? nil : ChickenMotion.standard, value: showingZenHint)
            .overlay(alignment: .topTrailing) {
                ReaderRibbonHost(model: model, fileReady: fileState.url != nil, isCompact: isCompact)
            }
            .overlay(alignment: .top) {
                if showSearch && chromeVisible {
                    ReaderSearchBar(text: $searchText, matchSummary: model.searchMatchSummary) { backwards in
                        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !query.isEmpty { model.engine?.search(query, backwards: backwards) }
                    } onClose: {
                        showSearch = false
                    }
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .overlay(alignment: .bottom) {
                ReaderFootnoteOverlay(model: model, chromeVisible: chromeVisible, reduceMotion: reduceMotion)
            }
            .overlay {
                ReaderImageOverlay(model: model, reduceMotion: reduceMotion)
            }
            #if os(macOS)
            .overlay(alignment: .topTrailing) {
                if model.isZen {
                    Color.clear
                        .frame(width: 220, height: 64)
                        .contentShape(Rectangle())
                        .onHover { zenHover = $0 }
                        .overlay {
                            if zenHover {
                                Button("Leave Zen Mode", systemImage: "arrow.down.right.and.arrow.up.left") { model.isZen = false }
                                    .buttonStyle(.glass)
                                    .transition(.opacity)
                            }
                        }
                        .animation(reduceMotion ? nil : ChickenMotion.micro, value: zenHover)
                }
            }
            #endif
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ReaderBottomOverlay(
                    model: model,
                    book: book,
                    chromeVisible: chromeVisible,
                    isCompact: isCompact,
                    reduceMotion: reduceMotion,
                    onShareSelection: { selectedText in presentQuoteCard(text: selectedText) }
                )
            }
    }

    @ViewBuilder
    private var engineView: some View {
        if let error = model.error {
            ContentUnavailableView {
                Label(book.displayTitle, systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                HStack(spacing: 12) {
                    Button("Try Again") {
                        model.loadStatus = .loading
                        engineReloadToken = UUID()
                    }
                    .buttonStyle(.glass)
                    #if os(iOS)
                    Button("Close") { dismiss() }
                        .buttonStyle(.plain)
                        .foregroundStyle(palette.muted)
                    #endif
                }
            }
            .foregroundStyle(palette.text)
        } else if let fileURL = fileState.url {
            Group {
                switch book.format {
                case .pdf:
                    PDFReader(
                        model: model,
                        fileURL: fileURL,
                        palette: palette,
                        readingMode: effectiveMode,
                        darkPages: model.darkModePDF,
                        onTapCenter: toggleChrome
                    )
                case .epub:
                    EPUBReader(
                        model: model,
                        fileURL: fileURL,
                        cacheDirectory: library.paths.epubCache,
                        style: EPUBStyle(
                            palette: palette,
                            fontSize: model.fontSize,
                            lineHeight: model.lineHeight,
                            columnWidth: model.columnWidth,
                            mode: effectiveMode,
                            typeface: model.typeface
                        ),
                        onTapCenter: toggleChrome
                    )
                case .text, .document, .unknown:
                    TextReader(
                        model: model,
                        fileURL: fileURL,
                        palette: palette,
                        fontSize: model.fontSize,
                        lineHeight: model.lineHeight,
                        columnWidth: model.columnWidth,
                        typeface: model.typeface,
                        onTapCenter: toggleChrome
                    )
                }
            }
            .id(engineReloadToken)
        } else {
            downloadingView
                .task(id: downloadAttemptID) {
                    guard case .downloading(let attempt) = fileState else { return }
                    do {
                        let url = try await library.downloadFile(for: book)
                        fileState = .ready(url)
                    } catch is CancellationError {
                    } catch {
                        fileState = .failed(error.localizedDescription, attempt: attempt)
                    }
                }
        }
    }

    private var downloadAttemptID: Int {
        switch fileState {
        case .downloading(let attempt), .failed(_, let attempt): attempt
        case .ready: -1
        }
    }

    private func checkFurtherPosition() {
        guard remoteOffer.offered == nil else { return }
        let current = model.reportedProgress ?? book.progress
        guard let candidate = library.furtherPosition(for: book, than: current, since: remoteOffer.baseline) else { return }
        if let dismissed = remoteOffer.dismissedAt, candidate.updatedAt <= dismissed { return }
        remoteOffer.offered = candidate
    }

    private func dismissFurther() {
        remoteOffer.dismissedAt = remoteOffer.offered?.updatedAt
        remoteOffer.offered = nil
    }

    private var downloadingView: some View {
        let errorMessage: String? = if case .failed(let msg, _) = fileState { msg } else { nil }
        return VStack(spacing: 22) {
            BookCover(book: book, style: .hero)
                .frame(width: isCompact ? 160 : 200, height: isCompact ? 240 : 300)
                .shadow(color: palette.shadow, radius: 22, x: 0, y: 14)
                .opacity(errorMessage == nil ? 1 : 0.6)
            if let errorMessage {
                VStack(spacing: 12) {
                    Text(errorMessage)
                        .font(.chickenUI(14))
                        .foregroundStyle(palette.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                    Button("Try Again") {
                        fileState = .downloading(attempt: downloadAttemptID + 1)
                    }
                    .font(.chickenUI(13, weight: .medium))
                    .foregroundStyle(palette.text)
                    .buttonStyle(.glass)
                }
            } else {
                Label {
                    Text(library.download(for: book)?.progress.map { "Downloading from iCloud… \(Int(($0 * 100).rounded()))%" } ?? "Downloading from iCloud…")
                } icon: {
                    ProgressView().controlSize(.small)
                }
                .font(.chickenUI(13, weight: .medium))
                .foregroundStyle(palette.muted)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
    }

    private var effectiveMode: ReadingMode {
        model.readingMode == .spread && isCompact ? .paged : model.readingMode
    }

    private func toggleChrome() {
        if model.activeFootnote != nil {
            model.activeFootnote = nil
            return
        }
        if catchUpDate != nil {
            catchUpDate = nil
            return
        }
        guard !Platform.isMac else { return }
        if model.isZen {
            model.isZen = false
            chromeHidden = false
        } else {
            chromeHidden.toggle()
        }
        if chromeHidden { showSearch = false }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        #if os(iOS)
        ToolbarItem(placement: .topBarLeading) {
            Button("Close", systemImage: "xmark") { dismiss() }
        }
        #endif

        ToolbarItem(placement: .navigation) {
            Button("Contents", systemImage: isCompact ? "list.bullet" : "sidebar.left") { showChapters.toggle() }
                .keyboardShortcut("s", modifiers: [.command, .control])
                .help("Show contents")
        }

        #if os(iOS)
        ToolbarItem(placement: .principal) {
            VStack(spacing: 1) {
                Text(book.displayTitle)
                    .font(.chickenUI(isCompact ? 14 : 15, weight: .semibold))
                    .lineLimit(1)
                if !model.chapters.isEmpty && model.chapterTitle != book.displayTitle {
                    Text(model.chapterTitle)
                        .font(.chickenUI(11))
                        .foregroundStyle(palette.muted)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: isCompact ? 180 : 360)
        }
        #endif

        ToolbarItemGroup(placement: .primaryAction) {
            if !isCompact {
                Button("Search", systemImage: "magnifyingglass") { showSearch.toggle() }
                    .keyboardShortcut("f")
                    .help("Search in book")
            }

            Button("Text & Layout", systemImage: "textformat.size") { showTypography.toggle() }
                .keyboardShortcut("t", modifiers: [.command, .option])
                .help("Typography and layout")
                .popover(isPresented: $showTypography, arrowEdge: .bottom) {
                    TypographyPanel(model: model, isCompact: isCompact)
                        .presentationCompactAdaptation(.sheet)
                        .presentationDetents([.medium])
                        .readingTheme(library.preferences.theme)
                }

            if !isCompact {
                Button(model.isBookmarked ? "Remove Bookmark" : "Bookmark", systemImage: model.isBookmarked ? "bookmark.fill" : "bookmark") {
                    model.toggleBookmark()
                }
                .keyboardShortcut("d")
                .symbolEffect(.bounce, value: model.isBookmarked)
                .help(model.isBookmarked ? "Remove bookmark" : "Bookmark this place")

                Button("Highlights & Bookmarks", systemImage: "highlighter") { showAnnotations.toggle() }
                    .keyboardShortcut("h", modifiers: [.command, .option])
                    .help("Highlights and bookmarks")
            }

            Menu {
                if isCompact {
                    Button("Highlights & Bookmarks", systemImage: "highlighter") { showAnnotations = true }
                    Button("Search", systemImage: "magnifyingglass") { showSearch = true }
                    Button(model.isBookmarked ? "Remove Bookmark" : "Bookmark", systemImage: model.isBookmarked ? "bookmark.fill" : "bookmark") {
                        model.toggleBookmark()
                    }
                    Divider()
                }
                Picker("Theme", selection: themeBinding) {
                    ForEach(ReadingTheme.allCases) { Label($0.label, systemImage: $0.systemImage).tag($0) }
                }
                if book.format.supportsFlowModes {
                    Picker("Layout", selection: $model.readingMode) {
                        ForEach(isCompact ? [ReadingMode.scroll, .paged] : ReadingMode.allCases) { mode in
                            Label(mode.label, systemImage: mode.systemImage).tag(mode)
                        }
                    }
                }
                if book.format == .pdf && palette.isDark {
                    Toggle(isOn: $model.darkModePDF) {
                        Label("Dark Pages", systemImage: "moon.stars")
                    }
                }
                Toggle(isOn: $model.isZen) {
                    Label("Zen Mode", systemImage: "rectangle.compress.vertical")
                }
                Divider()
                if book.progress > 0 {
                    Button("Catch Up", systemImage: "clock.arrow.circlepath") {
                        catchUpDate = book.lastOpenedAt ?? Date()
                    }
                }
                if !book.isFinished {
                    Button("Mark as Finished", systemImage: "checkmark.circle") {
                        model.completeBookAndCelebrate()
                    }
                }
                if model.readAloud.state == .idle {
                    Button("Read Aloud", systemImage: "speaker.wave.2") { model.readAloud.start() }
                        .keyboardShortcut("r", modifiers: [.command, .option])
                        .disabled(model.error != nil)
                } else {
                    Button("Stop Reading Aloud", systemImage: "speaker.slash") { model.readAloud.stop() }
                        .keyboardShortcut("r", modifiers: [.command, .option])
                }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
        }
    }

    private var themeBinding: Binding<ReadingTheme> {
        Binding(get: { library.preferences.theme }, set: { library.preferences.theme = $0 })
    }
}

private struct ReaderCoverWaitingOverlay: View {
    @Environment(\.palette) private var palette
    let model: ReaderModel
    let book: Book
    let fileReady: Bool
    let coverTimedOut: Bool
    let isCompact: Bool
    let reduceMotion: Bool

    private var waiting: Bool {
        guard book.format == .epub || book.format == .pdf else { return false }
        return fileReady
            && model.error == nil
            && model.currentPage == nil
            && model.chapterProgress == nil
            && !coverTimedOut
    }

    var body: some View {
        Group {
            if waiting {
                ZStack {
                    palette.background
                    BookCover(book: book, style: .hero)
                        .frame(width: isCompact ? 200 : 260, height: isCompact ? 300 : 390)
                        .shadow(color: palette.shadow, radius: 22, x: 0, y: 14)
                }
                .ignoresSafeArea()
                .transition(.opacity)
                .allowsHitTesting(false)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.28), value: waiting)
    }
}

private struct ReaderTopBannerOverlay: View {
    @Environment(\.palette) private var palette
    let model: ReaderModel
    let book: Book
    let remoteOffered: ReadingPosition?
    let catchUpDate: Date?
    let fileReady: Bool
    let coverTimedOut: Bool
    let showSearch: Bool
    let onDismissFurther: () -> Void
    let onDismissCatchUp: () -> Void

    private var waitingForFirstPage: Bool {
        guard book.format == .epub || book.format == .pdf else { return false }
        return fileReady
            && model.error == nil
            && model.currentPage == nil
            && model.chapterProgress == nil
            && !coverTimedOut
    }

    var body: some View {
        VStack(spacing: 10) {
            if let offered = remoteOffered {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(Int((offered.progress * 100).rounded()))% on your \(offered.deviceKind.isEmpty ? "other device" : offered.deviceKind)")
                            .font(.chickenUI(13.5, weight: .semibold))
                            .foregroundStyle(palette.text)
                        Text(offered.updatedAt, format: .relative(presentation: .named))
                            .font(.chickenUI(12))
                            .foregroundStyle(palette.muted)
                    }
                    Button("Go") {
                        model.jump(to: offered)
                        onDismissFurther()
                    }
                    .font(.chickenUI(13, weight: .medium))
                    .inkProminentButton()
                    Button(action: onDismissFurther) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.muted)
                            .frame(width: 32, height: 32)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stay here")
                }
                .padding(.leading, 18)
                .padding(.trailing, 10)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
                .transition(.move(edge: .top).combined(with: .opacity))
            } else if let catchUpDate, !waitingForFirstPage, !showSearch {
                PreviouslyCatchUpCard(
                    book: book,
                    lastOpened: catchUpDate,
                    recentHighlight: book.sortedHighlights.first,
                    onJumpToHighlight: { model.jump(toHighlight: $0) },
                    onDismiss: onDismissCatchUp
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.top, 12)
        .padding(.horizontal, 16)
    }
}

private struct ReaderRibbonHost: View {
    let model: ReaderModel
    let fileReady: Bool
    let isCompact: Bool

    var body: some View {
        if model.error == nil && fileReady {
            PullRibbonOverlay(
                isBookmarked: model.isBookmarked,
                isCompact: isCompact,
                onToggle: { model.toggleBookmark() }
            )
        }
    }
}

private struct ReaderFootnoteOverlay: View {
    let model: ReaderModel
    let chromeVisible: Bool
    let reduceMotion: Bool

    var body: some View {
        Group {
            if let footnote = model.activeFootnote {
                FootnotePopoverCard(
                    footnote: footnote,
                    onJump: { model.jumpToFootnote(footnote) },
                    onDismiss: { model.activeFootnote = nil }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, chromeVisible ? 88 : 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : ChickenMotion.standard, value: model.activeFootnote)
    }
}

private struct ReaderImageOverlay: View {
    let model: ReaderModel
    let reduceMotion: Bool

    var body: some View {
        Group {
            if let imagePreview = model.activeImage {
                ImageLightboxOverlay(preview: imagePreview) {
                    model.activeImage = nil
                }
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : ChickenMotion.micro, value: model.activeImage)
    }
}

private struct ReaderBottomOverlay: View {
    let model: ReaderModel
    let book: Book
    let chromeVisible: Bool
    let isCompact: Bool
    let reduceMotion: Bool
    let onShareSelection: (String) -> Void

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 10) {
                if model.selection != nil {
                    HighlightPicker(model: model) { selectedText in
                        onShareSelection(selectedText)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if model.readAloud.state != .idle {
                    ReadAloudBar(
                        controller: model.readAloud,
                        chapter: model.chapters.isEmpty ? book.displayTitle : model.chapterTitle,
                        compact: isCompact
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if chromeVisible && model.error == nil {
                    HStack(spacing: 8) {
                        ReaderProgressBar(model: model, compact: isCompact)
                        if model.isOnLastPage && !book.isFinished {
                            Button {
                                model.completeBookAndCelebrate()
                            } label: {
                                Label("Finish", systemImage: "checkmark")
                                    .font(.chickenUI(12.5, weight: .semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                            }
                            .inkProminentButton()
                            .transition(.scale(scale: 0.92).combined(with: .opacity))
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .padding(.horizontal, isCompact ? 12 : 24)
        .padding(.bottom, isCompact ? 6 : 14)
        .animation(reduceMotion ? nil : ChickenMotion.standard, value: model.selection)
        .animation(reduceMotion ? nil : ChickenMotion.standard, value: model.readAloud.state)
        .animation(reduceMotion ? nil : ChickenMotion.standard, value: model.isOnLastPage)
    }
}
