import ChickenKit
import SwiftUI

/// Resolves a book by id and shows the reader, or an explanation if the
/// book has been removed (e.g. a stale restored window on the Mac).
struct ReaderLoader: View {
    @Environment(LibraryStore.self) private var library
    let bookID: UUID

    var body: some View {
        Group {
            if let book = library.book(id: bookID) {
                ReaderView(book: book, library: library)
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
    let library: LibraryStore
    @State private var model: ReaderModel

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
    /// Briefly shown on entering zen mode on iPhone and iPad, where there's
    /// no hover to reveal a way out.
    @State private var showingZenHint = false
    /// Gives up waiting for the first page after a moment, so a slow or
    /// odd file never leaves the cover stuck on screen.
    @State private var coverTimedOut = false
    @State private var zenHover = false
    @State private var availableWidth: CGFloat = 1200
    /// The book's file once it's on this device; nil while it downloads
    /// from iCloud.
    @State private var bookFile: URL?
    @State private var downloadError: String?
    @State private var downloadAttempt = 0
    /// When this device last had the book open, taken before this session
    /// writes anything; another device's position counts if it's newer.
    @State private var positionBaseline: Date?
    /// Another device that read further since, offered once per position.
    @State private var furtherPosition: ReadingPosition?
    @State private var dismissedPosition: Date?

    init(book: Book, library: LibraryStore) {
        self.library = library
        _model = State(initialValue: ReaderModel(book: book, library: library, defaultMode: Self.defaultMode))
        _bookFile = State(initialValue: library.readableFileURL(for: book))
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

    /// Phones default to page turning; larger screens to scrolling.
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
                        .background(palette.surface.opacity(0.55))
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
                AnnotationsList(model: model)
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
        }
        #if os(iOS)
        .statusBarHidden(!chromeVisible)
        .persistentSystemOverlays(chromeVisible ? .automatic : .hidden)
        #endif
        .animation(reduceMotion ? .easeInOut(duration: 0.12) : .smooth(duration: 0.25), value: chromeVisible)
        .animation(.easeInOut(duration: 0.18), value: showChapters)
        .animation(.easeInOut(duration: 0.4), value: library.preferences.theme)
        .onAppear {
            positionBaseline = library.position(for: book)?.updatedAt ?? .distantPast
            library.markOpened(book)
            library.setOpen(true, book)
            library.readerDidAppear()
        }
        #if DEBUG
        .task {
            guard let panel = Self.debugPanel else { return }
            try? await Task.sleep(for: .seconds(1.5))
            switch panel {
            case "annotations": showAnnotations = true
            case "typography": showTypography = true
            case "search": showSearch = true
            case "contents": showChapters = true
            case "readaloud": model.readAloud.start()
            default: break
            }
        }
        #endif
        .onDisappear {
            model.readAloud.stop()
            model.engine?.captureLocation()
            model.savePreferences()
            library.setOpen(false, book)
            library.readerDidDisappear()
            library.save()
        }
        // Contents and the highlights inspector both take a column; when the
        // window can't fit both beside a comfortable page, show one at a time.
        .onChange(of: showAnnotations) { _, shown in
            if shown && availableWidth < 1100 { showChapters = false }
        }
        .onChange(of: showChapters) { _, shown in
            if shown && !isCompact && availableWidth < 1100 { showAnnotations = false }
        }
        .onChange(of: model.fontSize) { model.savePreferences() }
        .onChange(of: model.lineHeight) { model.savePreferences() }
        .onChange(of: model.columnWidth) { model.savePreferences() }
        .onChange(of: model.typeface) { model.savePreferences() }
        .onChange(of: model.readingMode) { model.savePreferences() }
        .onChange(of: model.isZen) { _, zen in
            model.savePreferences()
            if zen {
                showAnnotations = false
                showSearch = false
                showTypography = false
            }
            guard !Platform.isMac else { return }
            showingZenHint = zen
            if zen {
                Task {
                    try? await Task.sleep(for: .seconds(2.8))
                    showingZenHint = false
                }
            }
        }
        #if os(macOS)
        .onExitCommand {
            if model.isZen { model.isZen = false } else if showSearch { showSearch = false }
        }
        #endif
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

    // MARK: Reading surface

    /// True until the engine reports where it is: the book's cover holds
    /// the page meanwhile, so opening a book reads as its cover opening.
    private var isWaitingForFirstPage: Bool {
        guard book.format == .epub || book.format == .pdf else { return false }
        return bookFile != nil && model.error == nil && model.currentPage == nil && model.chapterProgress == nil && !coverTimedOut
    }

    private var readingSurface: some View {
        engineView
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                if let furtherPosition {
                    furtherBanner(furtherPosition)
                        .padding(.top, 12)
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.smooth(duration: 0.3), value: furtherPosition?.updatedAt)
            .task {
                // Give a position from another device a moment to arrive.
                try? await Task.sleep(for: .seconds(2))
                checkFurtherPosition()
            }
            .onChange(of: library.remoteChangeGeneration) { checkFurtherPosition() }
            .overlay {
                if isWaitingForFirstPage {
                    ZStack {
                        palette.background
                        BookCover(book: book, style: .hero)
                            .frame(width: isCompact ? 220 : 280, height: isCompact ? 330 : 420)
                            .shadow(color: palette.shadow, radius: 24, x: 4, y: 16)
                    }
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: 0.35), value: isWaitingForFirstPage)
            .task {
                try? await Task.sleep(for: .seconds(3))
                coverTimedOut = true
            }
            .overlay(alignment: .bottom) {
                if showingZenHint {
                    Label("Tap the middle of the page to bring back the controls", systemImage: "hand.tap")
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
            .animation(.smooth(duration: 0.3), value: showingZenHint)
            .overlay(alignment: .topTrailing) {
                // A bookmarked place gets a silk ribbon over the top edge
                // of the page, as a real bookmark would.
                if model.isBookmarked && model.error == nil {
                    Ribbon()
                        .frame(width: isCompact ? 14 : 18, height: isCompact ? 88 : 64)
                        .shadow(color: .black.opacity(0.18), radius: 1.5, x: 0, y: 1)
                        .padding(.trailing, isCompact ? 22 : 40)
                        .ignoresSafeArea(edges: .top)
                        .allowsHitTesting(false)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .accessibilityLabel("Bookmarked")
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.7), value: model.isBookmarked)
            .overlay(alignment: .top) {
                if showSearch && chromeVisible {
                    ReaderSearchBar(text: $searchText) { backwards in
                        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !query.isEmpty { model.engine?.search(query, backwards: backwards) }
                    } onClose: {
                        showSearch = false
                    }
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
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
                        .animation(.easeInOut(duration: 0.15), value: zenHover)
                }
            }
            #endif
            .safeAreaInset(edge: .bottom, spacing: 0) {
                GlassEffectContainer(spacing: 10) {
                    VStack(spacing: 10) {
                        if model.selection != nil {
                            HighlightPicker(model: model)
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
                            ReaderProgressBar(model: model, compact: isCompact)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }
                .padding(.horizontal, isCompact ? 12 : 24)
                .padding(.bottom, isCompact ? 4 : 14)
                .animation(.smooth(duration: 0.25), value: model.selection)
                .animation(.smooth(duration: 0.25), value: model.readAloud.state)
            }
    }

    @ViewBuilder
    private var engineView: some View {
        if let error = model.error {
            ContentUnavailableView {
                Label(book.displayTitle, systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            }
            .foregroundStyle(palette.text)
        } else if let fileURL = bookFile {
            switch book.format {
            case .pdf:
                PDFReader(model: model, fileURL: fileURL, palette: palette, readingMode: model.readingMode, onTapCenter: toggleChrome)
            case .epub:
                EPUBReader(
                    model: model,
                    fileURL: fileURL,
                    cacheDirectory: library.paths.epubCache,
                    style: EPUBStyle(palette: palette, fontSize: model.fontSize, lineHeight: model.lineHeight, columnWidth: model.columnWidth, mode: effectiveMode, typeface: model.typeface),
                    onTapCenter: toggleChrome
                )
            case .text, .document, .unknown:
                TextReader(model: model, fileURL: fileURL, palette: palette, fontSize: model.fontSize, lineHeight: model.lineHeight, columnWidth: model.columnWidth, typeface: model.typeface, onTapCenter: toggleChrome)
            }
        } else {
            downloadingView
                .task(id: downloadAttempt) {
                    downloadError = nil
                    do {
                        bookFile = try await library.downloadFile(for: book)
                    } catch is CancellationError {
                    } catch {
                        downloadError = error.localizedDescription
                    }
                }
        }
    }

    // MARK: Another device read further

    private func checkFurtherPosition() {
        guard let baseline = positionBaseline, furtherPosition == nil else { return }
        let current = model.reportedProgress ?? book.progress
        guard let candidate = library.furtherPosition(for: book, than: current, since: baseline) else { return }
        if let dismissed = dismissedPosition, candidate.updatedAt <= dismissed { return }
        furtherPosition = candidate
    }

    private func dismissFurther() {
        dismissedPosition = furtherPosition?.updatedAt
        furtherPosition = nil
    }

    /// "62% on your iPad, 2 hours ago", with a way there.
    private func furtherBanner(_ position: ReadingPosition) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(Int((position.progress * 100).rounded()))% on your \(position.deviceKind.isEmpty ? "other device" : position.deviceKind)")
                    .font(.chickenUI(13.5, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text(position.updatedAt, format: .relative(presentation: .named))
                    .font(.chickenSerif(12.5, italic: true))
                    .foregroundStyle(palette.muted)
            }
            Button("Go") {
                model.jump(to: position)
                dismissFurther()
            }
            .font(.chickenUI(13, weight: .medium))
            .inkProminentButton()
            Button(action: dismissFurther) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.muted)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stay here")
        }
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .padding(.vertical, 9)
        .glassEffect(.regular, in: .capsule)
    }

    /// The book's cover while its file comes down from iCloud.
    private var downloadingView: some View {
        VStack(spacing: 22) {
            BookCover(book: book, style: .hero)
                .frame(width: isCompact ? 160 : 200, height: isCompact ? 240 : 300)
                .shadow(color: palette.shadow, radius: 24, x: 4, y: 16)
                .opacity(downloadError == nil ? 1 : 0.6)
            if let downloadError {
                VStack(spacing: 12) {
                    Text(downloadError)
                        .font(.chickenUI(14))
                        .foregroundStyle(palette.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                    Button("Try Again") { downloadAttempt += 1 }
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

    /// Two-page spreads need room; narrow layouts fall back to single pages.
    private var effectiveMode: ReadingMode {
        model.readingMode == .spread && isCompact ? .paged : model.readingMode
    }

    private func toggleChrome() {
        guard !Platform.isMac else { return }
        if model.isZen {
            model.isZen = false
            chromeHidden = false
        } else {
            chromeHidden.toggle()
        }
        if chromeHidden { showSearch = false }
    }

    // MARK: Toolbar

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
                    .font(.chickenSerif(15, weight: .medium))
                    .lineLimit(1)
                if !model.chapters.isEmpty {
                    Text(model.chapterTitle)
                        .font(.chickenUI(11))
                        .foregroundStyle(palette.muted)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: 360)
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
            }

            Button("Highlights & Bookmarks", systemImage: "highlighter") { showAnnotations.toggle() }
                .keyboardShortcut("h", modifiers: [.command, .option])
                .help("Highlights and bookmarks")

            Menu {
                if isCompact {
                    Button("Search", systemImage: "magnifyingglass") { showSearch = true }
                    Button(model.isBookmarked ? "Remove Bookmark" : "Bookmark", systemImage: model.isBookmarked ? "bookmark.fill" : "bookmark") {
                        model.toggleBookmark()
                    }
                }
                Picker("Theme", selection: themeBinding) {
                    ForEach(ReadingTheme.allCases) { Label($0.label, systemImage: $0.systemImage).tag($0) }
                }
                if book.format.supportsFlowModes {
                    // Scroll reads straight down through every chapter;
                    // Pages turns like a book.
                    Picker("Layout", selection: $model.readingMode) {
                        ForEach(isCompact ? [ReadingMode.scroll, .paged] : ReadingMode.allCases) { mode in
                            Label(mode.label, systemImage: mode.systemImage).tag(mode)
                        }
                    }
                }
                Toggle(isOn: $model.isZen) {
                    Label("Zen Mode", systemImage: "rectangle.compress.vertical")
                }
                Divider()
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
