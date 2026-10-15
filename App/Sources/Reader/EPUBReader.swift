import ChickenKit
import SwiftUI
import WebKit

/// EPUB reader: the book is unpacked into the caches directory, stitched
/// into one document, and shown in a web view driven by `ChickenReader.js`.
struct EPUBReader: PlatformViewRepresentable {
    let model: ReaderModel
    let fileURL: URL
    let cacheDirectory: URL
    let style: EPUBStyle
    let onTapCenter: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let controller = configuration.userContentController
        controller.add(WeakMessageHandler(context.coordinator), name: "chicken")
        if let script = Self.runtimeScript {
            controller.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        #if os(iOS)
        configuration.dataDetectorTypes = []
        #endif

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isInspectable = true
        #if os(macOS)
        webView.setValue(false, forKey: "drawsBackground")
        #else
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        #endif

        context.coordinator.webView = webView
        context.coordinator.onTapCenter = onTapCenter
        context.coordinator.style = style
        context.coordinator.load(fileURL, cacheDirectory: cacheDirectory)
        return webView
    }

    func updateView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onTapCenter = onTapCenter
        if coordinator.style != style {
            coordinator.style = style
            coordinator.applyStyle(preservePosition: true)
        }
        let index = model.chapterIndex
        if !model.consumeEngineChapterChange(index) {
            coordinator.goToChapter(index)
        }
    }

    static func dismantleView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.captureLocation()
        coordinator.tearDown()
    }

    private static let runtimeScript: String? = {
        guard let url = Bundle.main.url(forResource: "ChickenReader", withExtension: "js") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }()

    @MainActor
    final class Coordinator: NSObject, ReaderEngine, WKNavigationDelegate, WKScriptMessageHandler {
        let model: ReaderModel
        weak var webView: WKWebView?
        var style: EPUBStyle?
        var onTapCenter: () -> Void = {}
        private var publication: EPUBPublication?
        private var isReady = false
        private var displayedChapter: Int?
        private var loadTask: Task<Void, Never>?
        private var tornDown = false

        init(model: ReaderModel) {
            self.model = model
            super.init()
            model.engine = self
        }

        func load(_ url: URL, cacheDirectory: URL) {
            loadTask = Task { [weak self] in
                let result = await Task.detached(priority: .userInitiated) {
                    Result { try EPUBPublication.prepare(bookAt: url, cacheDirectory: cacheDirectory) }
                }.value
                guard let self, !self.tornDown else { return }
                switch result {
                case .success(let publication):
                    self.publication = publication
                    self.model.error = nil
                    self.model.chapters = publication.spine.enumerated().map { index, item in
                        ReaderChapter(id: index, title: item.title, level: item.tocLevel)
                    }
                    self.webView?.loadFileURL(publication.documentURL, allowingReadAccessTo: publication.rootURL)
                case .failure:
                    self.model.chapters = []
                    self.model.resetPosition()
                    self.model.error = FileManager.default.fileExists(atPath: url.path)
                        ? "Chicken could not open this file as an EPUB. It may be damaged, incomplete, DRM-protected, or not actually an EPUB."
                        : "This book's file is missing from Chicken's library folder."
                }
            }
        }

        func tearDown() {
            tornDown = true
            loadTask?.cancel()
            webView?.stopLoading()
            webView?.navigationDelegate = nil
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: "chicken")
        }

        // MARK: Script bridge

        func applyStyle(preservePosition: Bool) {
            guard isReady, let style else { return }
            let config: [String: Any] = [
                "horizontal": style.mode.isHorizontal,
                "spread": style.mode == .spread,
                "background": ReaderPalette.css(style.palette.backgroundHex),
                "css": style.css,
                "preservePosition": preservePosition,
            ]
            call("chicken.configure", config)
            #if os(iOS)
            webView?.scrollView.isScrollEnabled = !style.mode.isHorizontal
            webView?.scrollView.bounces = !style.mode.isHorizontal
            #endif
        }

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
                isReady = true
                applyStyle(preservePosition: false)
                refreshHighlights()
                restoreInitialLocation()
                focusWebView()
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
            default:
                break
            }
        }

        private func handleProgress(_ message: MessagePayload) {
            guard let publication, let index = message.index, publication.spine.indices.contains(index) else { return }
            displayedChapter = index
            model.engineDidChangeChapter(index)

            let displayPage = message.page.map { $0 + 1 }
            if model.totalPages != message.pageCount { model.totalPages = message.pageCount }
            if model.currentPage != displayPage { model.currentPage = displayPage }
            model.chapterProgress = message.sectionProgression
            model.chapterPage = message.pageWithinSpine.map { $0 + 1 }
            model.chapterPageCount = message.chapterPageCount

            let location = EPUBLocation(
                href: publication.spine[index].locationHref,
                spineIndex: index,
                progression: message.sectionProgression ?? 0,
                globalProgression: message.progression ?? 0,
                pageNumber: displayPage,
                pageWithinSpine: message.pageWithinSpine
            )
            model.reportProgress(message.progression ?? 0, location: location.encoded)
        }

        private func restoreInitialLocation() {
            guard let publication else { return }
            if let location = EPUBLocation.decode(model.book.lastLocation),
               publication.spine.indices.contains(location.spineIndex),
               publication.spine[location.spineIndex].locationHref == location.href {
                restore(location)
            } else {
                let start = EPUBLocation(href: "", spineIndex: model.chapterIndex, progression: 0, globalProgression: 0)
                restore(start, attempts: 1)
            }
        }

        /// Fonts and images can still be settling right after load, which
        /// shifts pagination; repeat the restore a few times as layout firms up.
        private func restore(_ location: EPUBLocation, attempts: Int = 4) {
            let payload: [String: Any] = [
                "spineIndex": location.spineIndex,
                "progression": location.progression,
                "pageNumber": location.pageNumber as Any? ?? NSNull(),
            ]
            call("chicken.restore", payload)
            guard attempts > 1 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.restore(location, attempts: attempts - 1)
            }
        }

        private func focusWebView() {
            #if os(macOS)
            DispatchQueue.main.async { [weak self] in
                guard let webView = self?.webView, let window = webView.window, window.firstResponder !== webView else { return }
                window.makeFirstResponder(webView)
            }
            #endif
        }

        // MARK: ReaderEngine

        func goToChapter(_ index: Int) {
            guard isReady, displayedChapter != index else { return }
            displayedChapter = index
            call("chicken.scrollToSection", index, 0)
        }

        func seek(to progress: Double) {
            call("chicken.scrollToProgress", progress)
        }

        func jump(to location: String?, chapterIndex: Int) {
            if let location = EPUBLocation.decode(location) {
                restore(location, attempts: 1)
            } else {
                displayedChapter = nil
                goToChapter(chapterIndex)
            }
        }

        func turnPage(_ direction: Int) {
            call("chicken.turnPage", direction)
        }

        func search(_ query: String, backwards: Bool) {
            call("chicken.search", query, backwards)
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

        // MARK: Reading aloud

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

        // MARK: Navigation

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .cancel }
            if url.isFileURL { return .allow }
            // External links open in the browser, never inside the reader.
            if navigationAction.navigationType == .linkActivated {
                #if os(macOS)
                NSWorkspace.shared.open(url)
                #else
                await UIApplication.shared.open(url)
                #endif
            }
            return .cancel
        }
    }
}

/// Values from a script message, parsed once so they can cross to the main actor.
nonisolated private struct MessagePayload: Sendable {
    let type: String
    let index: Int?
    let text: String?
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
        progression = double("progression")
        sectionProgression = double("sectionProgression")
        page = int("page")
        pageCount = int("pageCount")
        pageWithinSpine = int("pageWithinSpine")
        chapterPageCount = int("chapterPageCount")
    }
}

/// WKUserContentController retains its handlers; this breaks the cycle
/// between the web view and the coordinator.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: (any WKScriptMessageHandler)?

    init(_ target: any WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
