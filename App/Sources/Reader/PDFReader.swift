import ChickenKit
import PDFKit
import SwiftUI

/// PDFKit reader for macOS, iPadOS, and iOS. Chapters come from the PDF
/// outline (or one entry per page when there is none). Highlights are drawn
/// as non-persistent annotations; the library is the source of truth.
struct PDFReader: PlatformViewRepresentable {
    let model: ReaderModel
    let fileURL: URL
    let palette: ReaderPalette
    let readingMode: ReadingMode
    let onTapCenter: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeView(context: Context) -> ChickenPDFView {
        let view = ChickenPDFView()
        view.autoScales = true
        view.displaysAsBook = true
        context.coordinator.attach(view, onTapCenter: onTapCenter)
        context.coordinator.load(fileURL)
        apply(to: view, coordinator: context.coordinator)
        return view
    }

    func updateView(_ view: ChickenPDFView, context: Context) {
        context.coordinator.onTapCenter = onTapCenter
        apply(to: view, coordinator: context.coordinator)
        let index = model.chapterIndex
        if !model.consumeEngineChapterChange(index) {
            context.coordinator.goToChapter(index)
        }
    }

    static func dismantleView(_ view: ChickenPDFView, coordinator: Coordinator) {
        coordinator.captureLocation()
    }

    private func apply(to view: ChickenPDFView, coordinator: Coordinator) {
        view.backgroundColor = PlatformColor.hex(palette.surfaceAltHex)
        guard coordinator.appliedMode != readingMode else { return }
        coordinator.appliedMode = readingMode
        let page = view.currentPage
        switch readingMode {
        case .scroll:
            view.displayMode = .singlePageContinuous
            view.displayDirection = .vertical
        case .paged:
            view.displayMode = .singlePage
            view.displayDirection = .horizontal
        case .spread:
            view.displayMode = .twoUp
            view.displayDirection = .horizontal
        }
        view.usesDiscreteTurns = readingMode.isHorizontal
        #if os(iOS)
        view.usePageViewController(readingMode == .paged, withViewOptions: nil)
        #endif
        view.autoScales = true
        if let page { view.go(to: page) }
    }

    @MainActor
    final class Coordinator: NSObject, ReaderEngine {
        let model: ReaderModel
        weak var view: ChickenPDFView?
        var onTapCenter: () -> Void = {}
        var appliedMode: ReadingMode?
        /// Outline entries: (first page index, title).
        private var outline: [(page: Int, title: String)] = []
        private var searchQuery = ""
        private var searchMatches: [PDFSelection] = []
        private var searchIndex = -1
        private var observers: [NSObjectProtocol] = []

        init(model: ReaderModel) {
            self.model = model
            super.init()
            model.engine = self
        }

        func attach(_ view: ChickenPDFView, onTapCenter: @escaping () -> Void) {
            self.view = view
            self.onTapCenter = onTapCenter
            view.onTapCenter = { [weak self] in self?.onTapCenter() }
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.pageChanged() }
            })
            observers.append(center.addObserver(forName: .PDFViewSelectionChanged, object: view, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.selectionChanged() }
            })
        }

        isolated deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }

        func load(_ url: URL) {
            guard let document = PDFDocument(url: url) else {
                model.chapters = []
                model.resetPosition()
                model.error = FileManager.default.fileExists(atPath: url.path)
                    ? "Chicken could not open this file as a PDF. It may be damaged, encrypted, or mislabeled."
                    : "This book's file is missing from Chicken's library folder."
                return
            }
            view?.document = document
            model.error = nil
            buildOutline(document)
            model.totalPages = document.pageCount
            refreshHighlights()
            restoreInitialLocation(document)
        }

        private func buildOutline(_ document: PDFDocument) {
            var entries: [(Int, String)] = []
            func walk(_ node: PDFOutline, level: Int) {
                for index in 0..<node.numberOfChildren {
                    guard let child = node.child(at: index) else { continue }
                    if let page = child.destination?.page {
                        entries.append((document.index(for: page), child.label ?? "Untitled"))
                    }
                    walk(child, level: level + 1)
                }
            }
            if let root = document.outlineRoot { walk(root, level: 0) }
            if entries.isEmpty {
                entries = (0..<min(document.pageCount, 500)).map { ($0, "Page \($0 + 1)") }
            }
            outline = entries.map { (page: $0.0, title: $0.1) }
            model.chapters = outline.enumerated().map { index, entry in
                ReaderChapter(id: index, title: entry.title, subtitle: "Page \(entry.page + 1)")
            }
        }

        private func restoreInitialLocation(_ document: PDFDocument) {
            let pageIndex: Int
            if let location = PDFLocation.decode(model.book.lastLocation), document.page(at: location.pageIndex) != nil {
                pageIndex = location.pageIndex
            } else if model.book.progress > 0 {
                pageIndex = max(0, min(document.pageCount - 1, Int((model.book.progress * Double(document.pageCount)).rounded(.up)) - 1))
            } else {
                updatePageState(pageIndex: 0, document: document)
                return
            }
            if let page = document.page(at: pageIndex) {
                // Defer until the view has laid out, or PDFKit ignores the jump.
                DispatchQueue.main.async { [weak self] in
                    self?.view?.go(to: page)
                    self?.updatePageState(pageIndex: pageIndex, document: document)
                }
            }
        }

        private func chapter(forPage pageIndex: Int) -> Int {
            outline.lastIndex { $0.page <= pageIndex } ?? 0
        }

        private func pageRange(forChapter index: Int, document: PDFDocument) -> Range<Int> {
            let start = outline.indices.contains(index) ? outline[index].page : 0
            let end = outline.indices.contains(index + 1) ? outline[index + 1].page : document.pageCount
            return start..<max(start + 1, end)
        }

        private func pageChanged() {
            guard let view, let document = view.document, let page = view.currentPage else { return }
            let pageIndex = document.index(for: page)
            updatePageState(pageIndex: pageIndex, document: document)
            let chapter = chapter(forPage: pageIndex)
            model.reportProgress(
                Double(pageIndex + 1) / Double(max(document.pageCount, 1)),
                location: PDFLocation(pageIndex: pageIndex, chapterIndex: chapter).encoded
            )
        }

        private func updatePageState(pageIndex: Int, document: PDFDocument) {
            let chapter = chapter(forPage: pageIndex)
            let range = pageRange(forChapter: chapter, document: document)
            let chapterPage = max(1, min(range.count, pageIndex - range.lowerBound + 1))
            model.engineDidChangeChapter(chapter)
            model.currentPage = pageIndex + 1
            model.chapterPage = chapterPage
            model.chapterPageCount = range.count
            model.chapterProgress = Double(chapterPage) / Double(range.count)
        }

        private func selectionChanged() {
            guard let view, let document = view.document,
                  let selection = view.currentSelection,
                  let text = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  text.count >= 3,
                  let page = selection.pages.first
            else {
                if model.selection != nil { model.selection = nil }
                return
            }
            let pageIndex = document.index(for: page)
            let chapter = chapter(forPage: pageIndex)
            model.selection = ReaderSelection(
                text: text,
                chapterIndex: chapter,
                location: PDFLocation(pageIndex: pageIndex, chapterIndex: chapter).encoded
            )
        }

        // MARK: ReaderEngine

        func goToChapter(_ index: Int) {
            guard let view, let document = view.document, outline.indices.contains(index) else { return }
            if let current = view.currentPage, pageRange(forChapter: index, document: document).contains(document.index(for: current)) {
                return
            }
            if let page = document.page(at: outline[index].page) { view.go(to: page) }
        }

        func seek(to progress: Double) {
            guard let view, let document = view.document, document.pageCount > 0 else { return }
            let index = Int((progress * Double(document.pageCount - 1)).rounded())
            if let page = document.page(at: index) { view.go(to: page) }
        }

        func jump(to location: String?, chapterIndex: Int) {
            guard let view, let document = view.document else { return }
            if let location = PDFLocation.decode(location), let page = document.page(at: location.pageIndex) {
                view.go(to: page)
            } else {
                goToChapter(chapterIndex)
            }
        }

        func turnPage(_ direction: Int) {
            direction > 0 ? view?.goToNextPage(nil) : view?.goToPreviousPage(nil)
        }

        func search(_ query: String, backwards: Bool) {
            guard let view, let document = view.document else { return }
            if query != searchQuery {
                searchQuery = query
                searchMatches = document.findString(query, withOptions: [.caseInsensitive])
                searchIndex = backwards ? searchMatches.count : -1
            }
            guard !searchMatches.isEmpty else { return }
            searchIndex = backwards ? max(0, searchIndex - 1) : min(searchMatches.count - 1, searchIndex + 1)
            let match = searchMatches[searchIndex]
            view.setCurrentSelection(match, animate: true)
            view.go(to: match)
        }

        func clearSelection() {
            view?.clearSelection()
        }

        func refreshHighlights() {
            guard let document = view?.document else { return }
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { continue }
                for annotation in page.annotations where annotation.userName == Self.annotationTag {
                    page.removeAnnotation(annotation)
                }
            }
            for highlight in model.book.highlights ?? [] {
                guard let location = PDFLocation.decode(highlight.location),
                      let page = document.page(at: location.pageIndex) else { continue }
                guard let pageText = page.string else { continue }
                let range = (pageText as NSString).range(of: highlight.text, options: [.caseInsensitive])
                guard range.location != NSNotFound, let match = page.selection(for: range) else { continue }
                for line in match.selectionsByLine() {
                    let annotation = PDFAnnotation(bounds: line.bounds(for: page), forType: .highlight, withProperties: nil)
                    annotation.color = PlatformColor(highlight.color.bar).withAlphaComponent(0.45)
                    annotation.userName = Self.annotationTag
                    page.addAnnotation(annotation)
                }
            }
        }

        func captureLocation() {
            pageChanged()
        }

        static let annotationTag = "chicken-highlight"
    }
}

/// PDFView with book-like page turning: spreads advance two pages at a
/// time, and on the Mac arrow keys and trackpad swipes turn whole pages.
final class ChickenPDFView: PDFView {
    var usesDiscreteTurns = false
    var onTapCenter: () -> Void = {}

    private var isPaired: Bool { displayMode == .twoUp || displayMode == .twoUpContinuous }

    /// Spread "groups": the first page sits alone (like a book's recto), then
    /// pairs [1,2], [3,4], and so on.
    private func currentGroup() -> Int {
        guard let document, let page = currentPage else { return 0 }
        let index = document.index(for: page)
        guard isPaired else { return index }
        return displaysAsBook ? (index == 0 ? 0 : (index + 1) / 2) : index / 2
    }

    private func firstPage(ofGroup group: Int) -> Int {
        guard isPaired else { return group }
        return displaysAsBook ? (group == 0 ? 0 : 2 * group - 1) : 2 * group
    }

    override func goToNextPage(_ sender: Any?) {
        guard isPaired, let document, document.pageCount > 0 else { return super.goToNextPage(sender) }
        let target = min(document.pageCount - 1, firstPage(ofGroup: currentGroup() + 1))
        if let page = document.page(at: target), page != currentPage { go(to: page) }
    }

    override func goToPreviousPage(_ sender: Any?) {
        guard isPaired, let document, document.pageCount > 0 else { return super.goToPreviousPage(sender) }
        let target = max(0, firstPage(ofGroup: max(0, currentGroup() - 1)))
        if let page = document.page(at: target), page != currentPage { go(to: page) }
    }

    #if os(macOS)
    private var lastTurn = Date.distantPast

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, window.firstResponder !== self else { return }
            window.makeFirstResponder(self)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard usesDiscreteTurns else { return super.scrollWheel(with: event) }
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : -event.scrollingDeltaY
        guard abs(delta) > 6, Date().timeIntervalSince(lastTurn) > 0.28 else { return }
        lastTurn = Date()
        delta > 0 ? goToNextPage(nil) : goToPreviousPage(nil)
    }

    override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return super.keyDown(with: event) }
        switch event.keyCode {
        case 123, 116: goToPreviousPage(nil)                   // ←, page up
        case 124, 121: goToNextPage(nil)                       // →, page down
        case 126 where usesDiscreteTurns: goToPreviousPage(nil) // ↑
        case 125 where usesDiscreteTurns: goToNextPage(nil)     // ↓
        case 49 where usesDiscreteTurns:                       // space
            event.modifierFlags.contains(.shift) ? goToPreviousPage(nil) : goToNextPage(nil)
        default: super.keyDown(with: event)
        }
    }
    #else
    private lazy var tapRecognizer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        recognizer.cancelsTouchesInView = false
        return recognizer
    }()

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, !(gestureRecognizers ?? []).contains(tapRecognizer) {
            addGestureRecognizer(tapRecognizer)
        }
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard currentSelection == nil else { return }
        let x = recognizer.location(in: self).x / max(bounds.width, 1)
        if usesDiscreteTurns && x < 0.25 {
            goToPreviousPage(nil)
        } else if usesDiscreteTurns && x > 0.75 {
            goToNextPage(nil)
        } else {
            onTapCenter()
        }
    }
    #endif
}
