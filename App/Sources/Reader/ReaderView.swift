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
    @State private var zenHover = false

    init(book: Book, library: LibraryStore) {
        self.library = library
        _model = State(initialValue: ReaderModel(book: book, library: library, defaultMode: Self.defaultMode))
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
            .toolbar { toolbar }
            .toolbarVisibility(chromeVisible ? .automatic : .hidden, for: Self.toolbarPlacement)
            .navigationTitle(book.title)
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
            library.markOpened(book)
            library.readerDidAppear()
        }
        .onDisappear {
            model.engine?.captureLocation()
            model.savePreferences()
            library.readerDidDisappear()
            library.save()
        }
        .onChange(of: model.fontSize) { model.savePreferences() }
        .onChange(of: model.lineHeight) { model.savePreferences() }
        .onChange(of: model.columnWidth) { model.savePreferences() }
        .onChange(of: model.readingMode) { model.savePreferences() }
        .onChange(of: model.isZen) { _, zen in
            model.savePreferences()
            if zen {
                showAnnotations = false
                showSearch = false
                showTypography = false
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

    private var readingSurface: some View {
        engineView
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        if chromeVisible && model.error == nil {
                            ReaderProgressBar(model: model, compact: isCompact)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }
                .padding(.horizontal, isCompact ? 12 : 24)
                .padding(.bottom, isCompact ? 4 : 14)
                .animation(.smooth(duration: 0.25), value: model.selection)
            }
    }

    @ViewBuilder
    private var engineView: some View {
        if let error = model.error {
            ContentUnavailableView {
                Label(book.title, systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            }
            .foregroundStyle(palette.text)
        } else {
            let fileURL = library.fileURL(for: book)
            switch book.format {
            case .pdf:
                PDFReader(model: model, fileURL: fileURL, palette: palette, readingMode: model.readingMode, onTapCenter: toggleChrome)
            case .epub:
                EPUBReader(
                    model: model,
                    fileURL: fileURL,
                    cacheDirectory: library.paths.epubCache,
                    style: EPUBStyle(palette: palette, fontSize: model.fontSize, lineHeight: model.lineHeight, columnWidth: model.columnWidth, mode: effectiveMode),
                    onTapCenter: toggleChrome
                )
            case .text, .document, .unknown:
                TextReader(model: model, fileURL: fileURL, palette: palette, fontSize: model.fontSize, lineHeight: model.lineHeight, columnWidth: model.columnWidth, onTapCenter: toggleChrome)
            }
        }
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
                Text(book.title)
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
                Toggle(isOn: $model.isZen) {
                    Label("Zen Mode", systemImage: "rectangle.compress.vertical")
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
