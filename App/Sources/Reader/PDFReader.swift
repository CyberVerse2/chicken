import ChickenKit
import CoreImage
import PDFKit
import SwiftUI

struct PDFReader: View {
    let model: ReaderModel
    let fileURL: URL
    let palette: ReaderPalette
    let readingMode: ReadingMode
    let darkPages: Bool
    let onTapCenter: () -> Void

    private var shouldInvertPages: Bool { palette.isDark && darkPages }

    var body: some View {
        PDFSurface(
            model: model,
            fileURL: fileURL,
            palette: palette,
            readingMode: readingMode,
            inverted: shouldInvertPages,
            onTapCenter: onTapCenter
        )
        #if !os(macOS)
        .modifier(PDFDarkPagesModifier(active: shouldInvertPages))
        #endif
    }
}

#if !os(macOS)
private struct PDFDarkPagesModifier: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content
                .colorInvert()
                .hueRotation(.degrees(180))
                .brightness(-0.04)
        } else {
            content
        }
    }
}
#endif

private struct PDFSurface: PlatformViewRepresentable {
    let model: ReaderModel
    let fileURL: URL
    let palette: ReaderPalette
    let readingMode: ReadingMode
    let inverted: Bool
    let onTapCenter: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeView(context: Context) -> ChickenPDFView {
        let view = ChickenPDFView()
        view.autoScales = true
        view.displaysAsBook = true
        view.enableDataDetectors = false
        view.pageShadowsEnabled = false
        #if !os(macOS)
        view.isOpaque = true
        #endif
        context.coordinator.attach(view, onTapCenter: onTapCenter)
        context.coordinator.load(fileURL)
        apply(to: view, coordinator: context.coordinator)
        return view
    }

    func updateView(_ view: ChickenPDFView, context: Context) {
        context.coordinator.onTapCenter = onTapCenter
        apply(to: view, coordinator: context.coordinator)
    }

    static func dismantleView(_ view: ChickenPDFView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    private func apply(to view: ChickenPDFView, coordinator: Coordinator) {
        let targetHex: UInt32 = inverted ? 0xEBEBEA : palette.surfaceAltHex
        if coordinator.appliedBackgroundHex != targetHex {
            coordinator.appliedBackgroundHex = targetHex
            view.backgroundColor = PlatformColor.hex(targetHex)
        }
        #if os(macOS)
        if coordinator.appliedDarkInversion != inverted {
            coordinator.appliedDarkInversion = inverted
            view.applyDarkPageFilter(inverted)
        }
        #endif
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

    final class Coordinator: NSObject, ReaderEngine, PDFDocumentDelegate {
        private enum RestoreState {
            case idle
            case pending(Int)
            case settling(Task<Void, Never>)
            case ready
        }

        nonisolated private struct OutlineEntry: Sendable {
            let page: Int
            let title: String
            let level: Int
        }

        nonisolated private struct UncheckedPDFDocumentBox: @unchecked Sendable {
            let document: PDFDocument
        }

        nonisolated private struct PreparedPDF: Sendable {
            let box: UncheckedPDFDocumentBox
            let outline: [OutlineEntry]
            let chapters: [ReaderChapter]
            let isOutlineSorted: Bool
            let pageCount: Int
        }

        private struct PendingHighlight: Sendable {
            let text: String
            let color: HighlightColor
        }

        let model: ReaderModel
        weak var view: ChickenPDFView?
        var onTapCenter: () -> Void = {}
        var appliedMode: ReadingMode?
        var appliedBackgroundHex: UInt32?
        var appliedDarkInversion: Bool?

        private var outline: [OutlineEntry] = []
        private var isOutlineSorted = true
        private var searchQuery = ""
        private var searchMatches: [PDFSelection] = []
        private var searchIndex = -1
        private var isSearching = false
        private var searchBackwards = false
        private var observers: [NSObjectProtocol] = []
        private var restoreState: RestoreState = .idle
        private var loadTask: Task<Void, Never>?
        private var settledPageTask: Task<Void, Never>?
        private var lastPageUIUpdateAt: ContinuousClock.Instant?
        private var annotatedPages: Set<Int> = []
        private var pendingHighlightsByPage: [Int: [PendingHighlight]] = [:]
        private var appliedHighlightPages: Set<Int> = []

        init(model: ReaderModel) {
            self.model = model
            super.init()
            model.engine = self
        }

        func attach(_ view: ChickenPDFView, onTapCenter: @escaping () -> Void) {
            self.view = view
            self.onTapCenter = onTapCenter
            view.onTapCenter = { [weak self] in self?.onTapCenter() }
            view.onLayout = { [weak self] in self?.performPendingRestore() }
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.pageChanged() }
            })
            observers.append(center.addObserver(forName: .PDFViewSelectionChanged, object: view, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.selectionChanged() }
            })
        }

        func teardown() {
            captureLocation()
            loadTask?.cancel()
            loadTask = nil
            settledPageTask?.cancel()
            settledPageTask = nil
            view?.document?.cancelFindString()
            view?.document?.delegate = nil
            if case .settling(let task) = restoreState { task.cancel() }
            restoreState = .idle
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
        }

        isolated deinit {
            loadTask?.cancel()
            settledPageTask?.cancel()
            if case .settling(let task) = restoreState { task.cancel() }
            observers.forEach(NotificationCenter.default.removeObserver)
        }

        func load(_ url: URL) {
            loadTask?.cancel()
            let start = ContinuousClock.now
            loadTask = Task { [weak self] in
                let prepared = await Self.openDocumentAndOutline(url)
                guard let self, !Task.isCancelled else { return }
                guard let prepared else {
                    self.model.engineDidFail(
                        fileURL: url,
                        detail: "Chicken could not open this file as a PDF. It may be damaged, encrypted, or mislabeled."
                    )
                    return
                }
                let document = prepared.box.document
                document.delegate = self
                self.outline = prepared.outline
                self.isOutlineSorted = prepared.isOutlineSorted
                self.view?.document = document
                self.model.engineDidBecomeReady()
                self.model.chapters = prepared.chapters
                self.model.totalPages = prepared.pageCount
                self.restoreInitialLocation(document)
                self.refreshHighlights()
                let d = start.duration(to: .now)
                let ms = Double(d.components.seconds) * 1000.0 + Double(d.components.attoseconds) / 1e15
                PerfMonitor.log("pdf_open", ms: ms, detail: "pages=\(prepared.pageCount)")
            }
        }

        @concurrent
        private static func openDocumentAndOutline(_ url: URL) async -> PreparedPDF? {
            guard let document = PDFDocument(url: url) else { return nil }
            var entries: [OutlineEntry] = []
            func walk(_ node: PDFOutline, level: Int) {
                if Task.isCancelled { return }
                for index in 0..<node.numberOfChildren {
                    guard let child = node.child(at: index) else { continue }
                    if let page = child.destination?.page {
                        entries.append(OutlineEntry(
                            page: document.index(for: page),
                            title: child.label?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Untitled",
                            level: level
                        ))
                    }
                    walk(child, level: level + 1)
                }
            }
            if let root = document.outlineRoot { walk(root, level: 0) }
            let hasOutline = !entries.isEmpty
            if !hasOutline {
                entries = (0..<document.pageCount).map {
                    OutlineEntry(page: $0, title: "Page \($0 + 1)", level: 0)
                }
            }
            var sorted = true
            var prev = -1
            for entry in entries {
                if entry.page < prev { sorted = false; break }
                prev = entry.page
            }
            let chapters = entries.enumerated().map { index, entry in
                ReaderChapter(
                    id: index,
                    title: entry.title,
                    subtitle: hasOutline ? "Page \(entry.page + 1)" : nil,
                    level: entry.level
                )
            }
            return PreparedPDF(
                box: UncheckedPDFDocumentBox(document: document),
                outline: entries,
                chapters: chapters,
                isOutlineSorted: sorted,
                pageCount: document.pageCount
            )
        }

        private func restoreInitialLocation(_ document: PDFDocument) {
            let targetPage: Int
            if let location = PDFLocation.decode(model.preferredStartLocation),
               document.page(at: location.pageIndex) != nil {
                targetPage = location.pageIndex
            } else if let jump = model.initialJumpTarget, outline.indices.contains(jump.chapterIndex) {
                targetPage = outline[jump.chapterIndex].page
            } else if model.book.progress > 0, document.pageCount > 0 {
                targetPage = max(0, min(document.pageCount - 1, Int((model.book.progress * Double(document.pageCount)).rounded(.up)) - 1))
            } else {
                targetPage = 0
            }
            restoreState = .pending(targetPage)
            performPendingRestore()
        }

        private func performPendingRestore() {
            guard case .pending(let pageIndex) = restoreState,
                  let view, let document = view.document,
                  view.bounds.width > 0, view.bounds.height > 0,
                  let page = document.page(at: pageIndex) else { return }
            view.go(to: page)
            updatePageState(pageIndex: pageIndex, document: document)
            let task = Task { @MainActor [weak self] in
                await Task.yield()
                guard let self, !Task.isCancelled, let view = self.view else { return }
                if view.currentPage != page { view.go(to: page) }
                self.restoreState = .ready
                self.updatePageState(pageIndex: pageIndex, document: document)
            }
            restoreState = .settling(task)
        }

        private func chapter(forPage pageIndex: Int) -> Int {
            guard !outline.isEmpty else { return 0 }
            if !isOutlineSorted {
                return outline.lastIndex { $0.page <= pageIndex } ?? 0
            }
            var low = 0
            var high = outline.count - 1
            var best = 0
            while low <= high {
                let mid = (low + high) >> 1
                if outline[mid].page <= pageIndex {
                    best = mid
                    low = mid + 1
                } else {
                    high = mid - 1
                }
            }
            return best
        }

        private func pageRange(forChapter index: Int, document: PDFDocument) -> Range<Int> {
            let start = outline.indices.contains(index) ? outline[index].page : 0
            let end = outline.indices.contains(index + 1) ? outline[index + 1].page : document.pageCount
            return start..<max(start + 1, end)
        }

        private func pageChanged() {
            guard case .ready = restoreState,
                  let view, let document = view.document, let page = view.currentPage else { return }
            let pageIndex = document.index(for: page)
            let now = ContinuousClock.now
            if lastPageUIUpdateAt.map({ $0.duration(to: now) >= .milliseconds(100) }) ?? true {
                lastPageUIUpdateAt = now
                updatePageState(pageIndex: pageIndex, document: document)
            }
            settledPageTask?.cancel()
            settledPageTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled, let self,
                      let view = self.view, let doc = view.document,
                      let settledPage = view.currentPage else { return }
                let settledIndex = doc.index(for: settledPage)
                self.flushSettledPage(pageIndex: settledIndex, document: doc)
            }
        }

        private func flushSettledPage(pageIndex: Int, document: PDFDocument) {
            lastPageUIUpdateAt = ContinuousClock.now
            applyHighlightsNear(pageIndex: pageIndex, in: document)
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
            model.applyPosition(
                currentPage: pageIndex + 1,
                chapterProgress: Double(chapterPage) / Double(range.count),
                chapterPage: chapterPage,
                chapterPageCount: range.count
            )
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

        func readAloudPassages(after: String?) async -> [SpokenPassage] {
            guard let view, let document = view.document, document.pageCount > 0 else { return [] }
            let start: Int
            if let after, let index = Int(after) {
                start = index + 1
            } else {
                start = view.currentPage.map { document.index(for: $0) } ?? 0
            }
            var passages: [SpokenPassage] = []
            var index = start
            while index < document.pageCount && passages.count < 3 {
                if let raw = document.page(at: index)?.string {
                    let text = raw
                        .replacingOccurrences(of: "-\n", with: "")
                        .replacing(/\s+/, with: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty { passages.append(SpokenPassage(id: String(index), text: text)) }
                }
                index += 1
            }
            return passages
        }

        func revealPassage(_ id: String) {
            guard let view, let document = view.document, let index = Int(id), let page = document.page(at: index) else { return }
            if view.currentPage != page { view.go(to: page) }
        }

        func endReadingAloud() {}

        func search(_ query: String, backwards: Bool) {
            guard let view, let document = view.document else { return }
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                document.cancelFindString()
                model.searchMatchSummary = nil
                return
            }
            if trimmed != searchQuery {
                document.cancelFindString()
                searchQuery = trimmed
                searchMatches = []
                searchIndex = -1
                isSearching = true
                searchBackwards = backwards
                model.searchMatchSummary = "Searching…"
                document.beginFindString(trimmed, withOptions: [.caseInsensitive])
                return
            }
            searchBackwards = backwards
            guard !searchMatches.isEmpty else {
                if !isSearching { model.searchMatchSummary = "No matches" }
                return
            }
            stepSearchMatch(view: view, backwards: backwards)
        }

        private func stepSearchMatch(view: ChickenPDFView, backwards: Bool) {
            guard !searchMatches.isEmpty else { return }
            if backwards {
                searchIndex = searchIndex <= 0 ? searchMatches.count - 1 : searchIndex - 1
            } else {
                searchIndex = (searchIndex + 1) % searchMatches.count
            }
            let suffix = isSearching ? "+" : ""
            model.searchMatchSummary = "\(searchIndex + 1) of \(searchMatches.count)\(suffix)"
            let match = searchMatches[searchIndex]
            view.setCurrentSelection(match, animate: true)
            view.go(to: match)
        }

        nonisolated func didMatchString(_ instance: PDFSelection) {
            nonisolated(unsafe) let selection = instance
            Task { @MainActor [weak self] in
                guard let self, self.isSearching, let view = self.view else { return }
                self.searchMatches.append(selection)
                if self.searchIndex < 0 {
                    self.searchIndex = 0
                    self.model.searchMatchSummary = "1 of \(self.searchMatches.count)+"
                    view.setCurrentSelection(selection, animate: true)
                    view.go(to: selection)
                } else {
                    self.model.searchMatchSummary = "\(self.searchIndex + 1) of \(self.searchMatches.count)+"
                }
            }
        }

        nonisolated func documentDidEndDocumentFind(_ notification: Notification) {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isSearching = false
                if self.searchMatches.isEmpty {
                    self.model.searchMatchSummary = "No matches"
                } else if self.searchIndex >= 0 {
                    self.model.searchMatchSummary = "\(self.searchIndex + 1) of \(self.searchMatches.count)"
                }
            }
        }

        func clearSelection() {
            view?.clearSelection()
        }

        func refreshHighlights() {
            guard let view, let document = view.document else { return }
            for index in annotatedPages {
                guard let page = document.page(at: index) else { continue }
                for annotation in page.annotations where annotation.userName == Self.annotationTag {
                    page.removeAnnotation(annotation)
                }
            }
            annotatedPages.removeAll()
            appliedHighlightPages.removeAll()
            var grouped: [Int: [PendingHighlight]] = [:]
            for highlight in model.book.highlights ?? [] {
                guard let location = PDFLocation.decode(highlight.location) else { continue }
                grouped[location.pageIndex, default: []].append(PendingHighlight(text: highlight.text, color: highlight.color))
            }
            pendingHighlightsByPage = grouped
            let currentIndex = view.currentPage.map { document.index(for: $0) } ?? 0
            applyHighlightsNear(pageIndex: currentIndex, in: document)
        }

        private func applyHighlightsNear(pageIndex: Int, in document: PDFDocument) {
            guard !pendingHighlightsByPage.isEmpty else { return }
            let low = max(0, pageIndex - 2)
            let high = min(document.pageCount - 1, pageIndex + 2)
            guard low <= high else { return }
            for idx in low...high where !appliedHighlightPages.contains(idx) {
                appliedHighlightPages.insert(idx)
                guard let items = pendingHighlightsByPage[idx], !items.isEmpty,
                      let page = document.page(at: idx),
                      let pageText = page.string else { continue }
                let nsText = pageText as NSString
                for item in items {
                    let range = nsText.range(of: item.text, options: [.caseInsensitive])
                    guard range.location != NSNotFound, let match = page.selection(for: range) else { continue }
                    for line in match.selectionsByLine() {
                        let annotation = PDFAnnotation(bounds: line.bounds(for: page), forType: .highlight, withProperties: nil)
                        annotation.color = PlatformColor(item.color.bar).withAlphaComponent(0.45)
                        annotation.userName = Self.annotationTag
                        page.addAnnotation(annotation)
                    }
                    annotatedPages.insert(idx)
                }
            }
        }

        func captureLocation() {
            settledPageTask?.cancel()
            settledPageTask = nil
            guard case .ready = restoreState,
                  let view, let document = view.document, let page = view.currentPage else { return }
            flushSettledPage(pageIndex: document.index(for: page), document: document)
        }

        static let annotationTag = "chicken-highlight"
    }
}

nonisolated private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

final class ChickenPDFView: PDFView {
    var usesDiscreteTurns = false
    var onTapCenter: () -> Void = {}
    var onLayout: () -> Void = {}

    private var isPaired: Bool { displayMode == .twoUp || displayMode == .twoUpContinuous }

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

    func applyDarkPageFilter(_ active: Bool) {
        wantsLayer = true
        layerUsesCoreImageFilters = active
        guard active, let filter = CIFilter(name: "CIColorMatrix") else {
            layer?.filters = nil
            return
        }
        filter.setValue(CIVector(x: 0.5748, y: -1.4304, z: -0.1444, w: 0), forKey: "inputRVector")
        filter.setValue(CIVector(x: -0.4252, y: -0.4304, z: -0.1444, w: 0), forKey: "inputGVector")
        filter.setValue(CIVector(x: -0.4252, y: -1.4304, z: 0.8556, w: 0), forKey: "inputBVector")
        filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        filter.setValue(CIVector(x: 0.96, y: 0.96, z: 0.96, w: 0), forKey: "inputBiasVector")
        layer?.filters = [filter]
    }

    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        onLayout()
    }

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
        case 123, 116: goToPreviousPage(nil)
        case 124, 121: goToNextPage(nil)
        case 126 where usesDiscreteTurns: goToPreviousPage(nil)
        case 125 where usesDiscreteTurns: goToNextPage(nil)
        case 49 where usesDiscreteTurns:
            event.modifierFlags.contains(.shift) ? goToPreviousPage(nil) : goToNextPage(nil)
        default: super.keyDown(with: event)
        }
    }
    #else
    private let tapDelegate = PDFTapDelegate()

    private lazy var tapRecognizer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = tapDelegate
        return recognizer
    }()

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, !(gestureRecognizers ?? []).contains(tapRecognizer) {
            addGestureRecognizer(tapRecognizer)
        }
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard currentSelection == nil else { return }
        let location = recognizer.location(in: self)
        if let page = page(for: location, nearest: false),
           let annotation = page.annotation(at: convert(location, to: page)),
           annotation.type == "Link" {
            return
        }
        let x = location.x / max(bounds.width, 1)
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

#if os(iOS)
private final class PDFTapDelegate: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
        if let tap = other as? UITapGestureRecognizer, tap.numberOfTapsRequired > 1 {
            return true
        }
        return false
    }
}
#endif
