import ChickenKit
import os
import SwiftUI
import WebKit

struct EPUBReader: PlatformViewRepresentable {
    let model: ReaderModel
    let fileURL: URL
    let cacheDirectory: URL
    let style: EPUBStyle
    let onTapCenter: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeView(context: Context) -> WKWebView {
        let webView = EPUBWebViewPool.shared.acquire(messageHandler: context.coordinator)
        webView.navigationDelegate = context.coordinator
        context.coordinator.attach(webView: webView, style: style, onTapCenter: onTapCenter)
        context.coordinator.load(fileURL)
        return webView
    }

    func updateView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onTapCenter = onTapCenter
        if let previous = coordinator.style, previous != style {
            let themeOnly = previous.hasSameLayout(as: style)
            coordinator.style = style
            coordinator.applyStyle(preservePosition: !themeOnly, themeOnly: themeOnly)
        } else if coordinator.style == nil {
            coordinator.style = style
        }
    }

    static func dismantleView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.captureLocation()
        coordinator.tearDown()
        EPUBWebViewPool.shared.release(webView)
    }

    final class Coordinator: NSObject, ReaderEngine, WKNavigationDelegate, WKScriptMessageHandler {
        private enum Lifecycle {
            case idle
            case loading(Task<Void, Never>)
            case loaded(EPUBBookSession, isReady: Bool)
            case tornDown
        }

        let model: ReaderModel
        weak var webView: WKWebView?
        var style: EPUBStyle?
        var loadedStyle: EPUBStyle?
        var onTapCenter: () -> Void = {}
        private var lifecycle: Lifecycle = .idle
        private var searchTask: Task<Void, Never>?
        private var searchQuery = ""
        private var searchMatches: [EPUBBookSession.SearchMatch] = []
        private var searchIndex = -1
        private var registeredBookID: UUID?
        private var loadStartedAt: ContinuousClock.Instant?
        #if os(iOS)
        private var swipeObserver: EPUBBoundarySwipeObserver?
        #endif

        private var session: EPUBBookSession? {
            if case .loaded(let session, _) = lifecycle { return session }
            return nil
        }

        private var isReady: Bool {
            if case .loaded(_, let ready) = lifecycle { return ready }
            return false
        }

        init(model: ReaderModel) {
            self.model = model
            super.init()
            model.engine = self
        }

        func attach(webView: WKWebView, style: EPUBStyle, onTapCenter: @escaping () -> Void) {
            self.webView = webView
            self.style = style
            self.onTapCenter = onTapCenter
            applyWebViewBackground(hex: style.palette.backgroundHex)
            #if os(iOS)
            let observer = EPUBBoundarySwipeObserver(scrollView: webView.scrollView) { [weak self] delta in
                self?.call("chicken.turnChapter", delta)
            }
            swipeObserver = observer
            updateScrollViewPaging(for: style.mode)
            #endif
        }

        private func applyWebViewBackground(hex: UInt32) {
            guard let webView else { return }
            let color = PlatformColor.hex(hex)
            webView.underPageBackgroundColor = color
            #if !os(macOS)
            webView.isOpaque = true
            webView.backgroundColor = color
            webView.scrollView.backgroundColor = color
            #endif
        }

        func load(_ url: URL) {
            let start = ContinuousClock.now
            loadStartedAt = start
            let initialStyle = style ?? EPUBStyle(
                palette: ReadingTheme.paper.palette,
                fontSize: model.fontSize,
                lineHeight: model.lineHeight,
                columnWidth: model.columnWidth,
                mode: model.readingMode,
                typeface: model.typeface
            )
            loadedStyle = initialStyle
            let preferredLocation = model.preferredStartLocation
            let fallbackChapter = model.chapterIndex
            let highlights = (model.book.highlights ?? []).map {
                HighlightPayload(id: $0.id.uuidString, text: $0.text, spineIndex: $0.chapterIndex, color: $0.color.cssFill)
            }
            let sessionBookID = UUID()
            let nativeSwipe = Platform.isMac ? false : initialStyle.mode.isHorizontal
            let styleCSS = initialStyle.css
            let modeRaw = initialStyle.mode.rawValue
            let backgroundCSS = ReaderPalette.css(initialStyle.palette.backgroundHex)
            let textColorCSS = ReaderPalette.css(initialStyle.palette.textHex)
            let mutedColorCSS = ReaderPalette.css(initialStyle.palette.mutedHex)
            let layoutKey = "\(Int(initialStyle.fontSize))|\(initialStyle.lineHeight)|\(Int(initialStyle.columnWidth))|\(initialStyle.mode.rawValue)|\(initialStyle.typeface.rawValue)"

            let task = Task { [weak self] in
                let result = await Self.prepareInitialLoad(
                    url: url,
                    bookID: sessionBookID,
                    modeRaw: modeRaw,
                    styleCSS: styleCSS,
                    backgroundCSS: backgroundCSS,
                    textColorCSS: textColorCSS,
                    mutedColorCSS: mutedColorCSS,
                    layoutKey: layoutKey,
                    nativeSwipe: nativeSwipe,
                    preferredLocation: preferredLocation,
                    fallbackChapter: fallbackChapter,
                    highlights: highlights
                )
                guard let self, !Task.isCancelled else { return }
                if case .tornDown = self.lifecycle { return }
                switch result {
                case .success(let prepared):
                    self.registeredBookID = prepared.session.bookID
                    EPUBSchemeRegistry.shared.register(session: prepared.session)
                    EPUBSchemeRegistry.shared.stageInitialHTML(prepared.htmlData, token: prepared.token, for: prepared.session.bookID)
                    self.lifecycle = .loaded(prepared.session, isReady: false)
                    self.model.chapters = prepared.session.package.spine.enumerated().map { index, item in
                        ReaderChapter(id: index, title: item.title, level: item.tocLevel)
                    }
                    let loadURL = URL(string: "\(EPUBSchemeRegistry.scheme)://\(prepared.session.bookID.uuidString)/__reader/\(prepared.token)")!
                    self.webView?.load(URLRequest(url: loadURL))
                    if let t0 = self.loadStartedAt {
                        let d = t0.duration(to: .now)
                        let ms = Double(d.components.seconds) * 1000.0 + Double(d.components.attoseconds) / 1e15
                        PerfMonitor.log("epub_session_prepared", ms: ms, bytes: prepared.htmlData.count)
                    }
                case .failure(let error):
                    ChickenLog.epub.error("Failed to open EPUB: \(error.localizedDescription, privacy: .public)")
                    self.model.engineDidFail(
                        fileURL: url,
                        detail: "Chicken could not open this file as an EPUB. It may be damaged, incomplete, DRM-protected, or not actually an EPUB."
                    )
                }
            }
            lifecycle = .loading(task)
        }

        nonisolated private struct HighlightPayload: Encodable, Sendable {
            let id: String
            let text: String
            let spineIndex: Int
            let color: String
        }

        private struct PreparedLoad: @unchecked Sendable {
            let session: EPUBBookSession
            let htmlData: Data
            let token: String
        }

        @concurrent
        private static func prepareInitialLoad(
            url: URL,
            bookID: UUID,
            modeRaw: String,
            styleCSS: String,
            backgroundCSS: String,
            textColorCSS: String,
            mutedColorCSS: String,
            layoutKey: String,
            nativeSwipe: Bool,
            preferredLocation: String?,
            fallbackChapter: Int,
            highlights: [HighlightPayload]
        ) async -> Result<PreparedLoad, any Error> {
            Result {
                let session = try EPUBBookSession(bookAt: url, bookID: bookID)
                let decoded = EPUBLocation.decode(preferredLocation)
                let resolvedIndex: Int
                let progression: Double
                let pageWithinSpine: Int?
                if let decoded,
                   session.package.spine.indices.contains(decoded.spineIndex),
                   session.package.spine[decoded.spineIndex].locationHref == decoded.href {
                    resolvedIndex = decoded.spineIndex
                    progression = decoded.progression
                    pageWithinSpine = decoded.pageWithinSpine
                } else if session.package.spine.indices.contains(fallbackChapter) {
                    resolvedIndex = fallbackChapter
                    progression = 0
                    pageWithinSpine = nil
                } else {
                    resolvedIndex = 0
                    progression = 0
                    pageWithinSpine = nil
                }

                var groupedHighlights: [String: [HighlightPayload]] = [:]
                for item in highlights {
                    groupedHighlights[String(item.spineIndex), default: []].append(item)
                }

                let boot = BootPayload(
                    mode: modeRaw,
                    nativeSwipe: nativeSwipe,
                    background: backgroundCSS,
                    textColor: textColorCSS,
                    mutedColor: mutedColorCSS,
                    layoutKey: layoutKey,
                    spineCount: session.package.spine.count,
                    spineWeights: session.spineWeights,
                    cumulativeWeights: session.cumulativeWeights,
                    totalWeight: session.totalWeight,
                    initialChapter: resolvedIndex,
                    restore: RestoreBoot(spineIndex: resolvedIndex, progression: progression, pageWithinSpine: pageWithinSpine),
                    highlightsByChapter: groupedHighlights
                )
                let bootJSONData = try JSONEncoder().encode(boot)
                let bootJSON = String(data: bootJSONData, encoding: .utf8) ?? "{}"
                let html = session.initialDocumentHTML(chapterIndex: resolvedIndex, styleCSS: styleCSS, bootJSON: bootJSON)
                return PreparedLoad(session: session, htmlData: Data(html.utf8), token: UUID().uuidString)
            }
        }

        nonisolated private struct RestoreBoot: Encodable {
            let spineIndex: Int
            let progression: Double
            let pageWithinSpine: Int?
        }

        nonisolated private struct BootPayload: Encodable {
            let mode: String
            let nativeSwipe: Bool
            let background: String
            let textColor: String
            let mutedColor: String
            let layoutKey: String
            let spineCount: Int
            let spineWeights: [Int]
            let cumulativeWeights: [Int]
            let totalWeight: Int
            let initialChapter: Int
            let restore: RestoreBoot
            let highlightsByChapter: [String: [HighlightPayload]]
        }

        func tearDown() {
            if case .loading(let task) = lifecycle { task.cancel() }
            lifecycle = .tornDown
            searchTask?.cancel()
            searchTask = nil
            #if os(iOS)
            swipeObserver?.detach()
            swipeObserver = nil
            #endif
            if let registeredBookID {
                let bytes = EPUBSchemeRegistry.shared.totalBytesServed(for: registeredBookID)
                PerfMonitor.log("epub_session_closed", bytes: bytes)
                EPUBSchemeRegistry.shared.unregister(bookID: registeredBookID)
                self.registeredBookID = nil
            }
        }

        func applyStyle(preservePosition: Bool, themeOnly: Bool = false) {
            guard isReady, let style else { return }
            loadedStyle = style
            applyWebViewBackground(hex: style.palette.backgroundHex)
            var config: [String: Any] = [
                "background": ReaderPalette.css(style.palette.backgroundHex),
                "textColor": ReaderPalette.css(style.palette.textHex),
                "mutedColor": ReaderPalette.css(style.palette.mutedHex),
                "themeOnly": themeOnly,
            ]
            if !themeOnly {
                config["mode"] = style.mode.rawValue
                config["horizontal"] = style.mode.isHorizontal
                config["spread"] = style.mode == .spread
                config["css"] = style.css
                config["preservePosition"] = preservePosition
                config["nativeSwipe"] = Platform.isMac ? false : style.mode.isHorizontal
                config["layoutKey"] = "\(Int(style.fontSize))|\(style.lineHeight)|\(Int(style.columnWidth))|\(style.mode.rawValue)|\(style.typeface.rawValue)"
            }
            call("chicken.configure", config)
            #if os(iOS)
            if !themeOnly {
                updateScrollViewPaging(for: style.mode)
            }
            #endif
        }

        #if os(iOS)
        private func updateScrollViewPaging(for mode: ReadingMode) {
            guard let scrollView = webView?.scrollView else { return }
            scrollView.isScrollEnabled = true
            scrollView.isPagingEnabled = mode.isHorizontal
            scrollView.bounces = true
            scrollView.alwaysBounceHorizontal = mode.isHorizontal
            scrollView.showsHorizontalScrollIndicator = false
        }
        #endif

        private func call(_ function: String, _ arguments: Any...) {
            let encoded = arguments.map(Self.javascriptLiteral).joined(separator: ", ")
            webView?.evaluateJavaScript("window.chicken && \(function)(\(encoded))", completionHandler: nil)
        }

        private static func javascriptLiteral(_ value: Any) -> String {
            if let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
               let string = String(data: data, encoding: .utf8) {
                return string
            }
            return "null"
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            handle(MessagePayload(message.body as? [String: Any] ?? [:]))
        }

        private func handle(_ message: MessagePayload) {
            switch message.type {
            case "ready":
                if case .loaded(let session, _) = lifecycle {
                    lifecycle = .loaded(session, isReady: true)
                }
                if let t0 = loadStartedAt {
                    let d = t0.duration(to: .now)
                    let ms = Double(d.components.seconds) * 1000.0 + Double(d.components.attoseconds) / 1e15
                    PerfMonitor.log("epub_ready", ms: ms)
                    loadStartedAt = nil
                }
                model.engineDidBecomeReady()
                handleProgress(message)
                focusWebView()
                if let style, let loadedStyle, style != loadedStyle {
                    self.loadedStyle = style
                    let themeOnly = loadedStyle.hasSameLayout(as: style)
                    applyStyle(preservePosition: !themeOnly, themeOnly: themeOnly)
                }
            case "progress":
                handleProgress(message)
            case "selection":
                if let text = message.text, let index = message.index {
                    model.selection = ReaderSelection(text: text, chapterIndex: index, location: model.currentLocation)
                } else if model.selection != nil {
                    model.selection = nil
                }
            case "tap":
                onTapCenter()
            case "footnote":
                if let text = message.text, !text.isEmpty {
                    model.activeFootnote = ReaderFootnote(
                        label: message.label ?? "Note",
                        text: text,
                        chapterIndex: message.chapter,
                        fragment: message.fragment
                    )
                    Haptics.impact(.light)
                }
            case "image":
                if let src = message.src, let url = URL(string: src) {
                    model.activeImage = ReaderImagePreview(url: url, alt: message.alt ?? "")
                }
            default:
                break
            }
        }

        private func handleProgress(_ message: MessagePayload) {
            guard let session, let index = message.index, session.package.spine.indices.contains(index) else { return }
            model.engineDidChangeChapter(index)

            let displayPage = message.page.map { $0 + 1 }
            model.applyPosition(
                totalPages: message.pageCount,
                updateTotalPages: message.pageCount != nil,
                currentPage: displayPage,
                chapterProgress: message.sectionProgression,
                chapterPage: message.pageWithinSpine.map { $0 + 1 },
                chapterPageCount: message.chapterPageCount
            )

            let location = EPUBLocation(
                href: session.package.spine[index].locationHref,
                spineIndex: index,
                progression: message.sectionProgression ?? 0,
                globalProgression: message.progression ?? 0,
                pageNumber: displayPage,
                pageWithinSpine: message.pageWithinSpine
            )
            model.reportProgress(message.progression ?? 0, location: location.encoded)
        }

        private func focusWebView() {
            #if os(macOS)
            Task { @MainActor [weak self] in
                guard let webView = self?.webView, let window = webView.window, window.firstResponder !== webView else { return }
                window.makeFirstResponder(webView)
            }
            #endif
        }

        func goToChapter(_ index: Int) {
            guard isReady else { return }
            call("chicken.scrollToSection", index, 0)
        }

        func seek(to progress: Double) {
            guard isReady else { return }
            call("chicken.scrollToProgress", progress)
        }

        func jump(to location: String?, chapterIndex: Int) {
            guard isReady else { return }
            if let location = EPUBLocation.decode(location) {
                let payload: [String: Any] = [
                    "spineIndex": location.spineIndex,
                    "progression": location.progression,
                    "pageWithinSpine": location.pageWithinSpine as Any? ?? NSNull(),
                ]
                call("chicken.restore", payload, true)
            } else {
                goToChapter(chapterIndex)
            }
        }

        func search(_ query: String, backwards: Bool) {
            guard isReady, let session else { return }
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                model.searchMatchSummary = nil
                return
            }
            if trimmed == searchQuery && !searchMatches.isEmpty {
                advanceSearch(query: trimmed, backwards: backwards)
                return
            }
            searchTask?.cancel()
            searchQuery = trimmed
            searchMatches = []
            searchIndex = -1
            searchTask = Task { [weak self] in
                let matches = await Self.runSearch(session: session, query: trimmed)
                guard let self, !Task.isCancelled, self.searchQuery == trimmed else { return }
                self.searchMatches = matches
                self.searchIndex = backwards ? matches.count : -1
                self.advanceSearch(query: trimmed, backwards: backwards)
            }
        }

        @concurrent
        private static func runSearch(session: EPUBBookSession, query: String) async -> [EPUBBookSession.SearchMatch] {
            session.search(query)
        }

        private func advanceSearch(query: String, backwards: Bool) {
            guard !searchMatches.isEmpty else {
                model.searchMatchSummary = "No matches"
                return
            }
            if backwards {
                searchIndex = searchIndex <= 0 ? searchMatches.count - 1 : searchIndex - 1
            } else {
                searchIndex = (searchIndex + 1) % searchMatches.count
            }
            let match = searchMatches[searchIndex]
            model.searchMatchSummary = "\(searchIndex + 1) of \(searchMatches.count)"
            call("chicken.highlightSearchMatch", query, match.spineIndex, match.occurrenceInSpine)
        }

        func clearSelection() {
            call("chicken.clearSelection")
        }

        func refreshHighlights() {
            guard isReady else { return }
            let items: [[String: Any]] = (model.book.highlights ?? []).map {
                ["id": $0.id.uuidString, "text": $0.text, "spineIndex": $0.chapterIndex, "color": $0.color.cssFill]
            }
            call("chicken.applyHighlights", items)
        }

        func captureLocation() {
            guard isReady, let webView else { return }
            webView.evaluateJavaScript("window.chicken && window.chicken.snapshot()") { [weak self] value, _ in
                guard let body = value as? [String: Any] else { return }
                MainActor.assumeIsolated { self?.handleProgress(MessagePayload(body)) }
            }
        }

        func readAloudPassages(after: String?) async -> [SpokenPassage] {
            guard isReady, let webView else { return [] }
            let value = try? await webView.callAsyncJavaScript(
                "return window.chicken ? window.chicken.readAloud(after, 30) : []",
                arguments: ["after": after ?? NSNull()],
                contentWorld: .page
            )
            return (value as? [[String: Any]] ?? []).compactMap { item in
                guard let id = item["id"] as? String, let text = item["text"] as? String, !text.isEmpty else { return nil }
                return SpokenPassage(id: id, text: text)
            }
        }

        func revealPassage(_ id: String) {
            call("chicken.revealPassage", id)
        }

        func endReadingAloud() {
            call("chicken.endReadingAloud")
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .cancel }
            if url.scheme == EPUBSchemeRegistry.scheme || url.isFileURL || url.absoluteString == "about:blank" {
                return .allow
            }
            if navigationAction.navigationType == .linkActivated {
                #if os(macOS)
                NSWorkspace.shared.open(url)
                #else
                await UIApplication.shared.open(url)
                #endif
            }
            return .cancel
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            logNavigationFailure(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            logNavigationFailure(error)
        }

        private func logNavigationFailure(_ error: any Error) {
            let nsError = error as NSError
            guard !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) else { return }
            ChickenLog.epub.error("EPUB WebView navigation failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

#if os(iOS)
private final class EPUBBoundarySwipeObserver: NSObject {
    private weak var scrollView: UIScrollView?
    private let onTurnChapter: (Int) -> Void

    init(scrollView: UIScrollView, onTurnChapter: @escaping (Int) -> Void) {
        self.scrollView = scrollView
        self.onTurnChapter = onTurnChapter
        super.init()
        scrollView.panGestureRecognizer.addTarget(self, action: #selector(handlePan(_:)))
    }

    func detach() {
        scrollView?.panGestureRecognizer.removeTarget(self, action: #selector(handlePan(_:)))
        scrollView = nil
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard recognizer.state == .ended,
              let scrollView,
              scrollView.isPagingEnabled
        else { return }
        let x = scrollView.contentOffset.x
        let maxX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
        let translation = recognizer.translation(in: scrollView)
        let tx = translation.x
        let ty = translation.y
        if x < -36 || (x <= 1 && tx > 55 && abs(tx) > abs(ty) * 1.4) {
            onTurnChapter(-1)
        } else if x > maxX + 36 || (x >= maxX - 1 && tx < -55 && abs(tx) > abs(ty) * 1.4) {
            onTurnChapter(1)
        }
    }
}
#endif

nonisolated private struct MessagePayload: Sendable {
    let type: String
    let index: Int?
    let text: String?
    let label: String?
    let fragment: String?
    let chapter: Int?
    let src: String?
    let alt: String?
    let progression: Double?
    let sectionProgression: Double?
    let page: Int?
    let pageCount: Int?
    let pageWithinSpine: Int?
    let chapterPageCount: Int?

    init(_ body: [String: Any]) {
        func int(_ key: String) -> Int? { (body[key] as? NSNumber)?.intValue }
        func double(_ key: String) -> Double? { (body[key] as? NSNumber)?.doubleValue }
        type = body["type"] as? String ?? ""
        index = int("index")
        text = body["text"] as? String
        label = body["label"] as? String
        fragment = body["fragment"] as? String
        chapter = int("chapter")
        src = body["src"] as? String
        alt = body["alt"] as? String
        progression = double("progression")
        sectionProgression = double("sectionProgression")
        page = int("page")
        pageCount = int("pageCount")
        pageWithinSpine = int("pageWithinSpine")
        chapterPageCount = int("chapterPageCount")
    }
}
