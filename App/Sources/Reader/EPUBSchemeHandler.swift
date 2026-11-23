import ChickenKit
import Foundation
import Synchronization
import WebKit

nonisolated final class EPUBSchemeRegistry: Sendable {
    static let shared = EPUBSchemeRegistry()
    static let scheme = "chicken-epub"

    private struct Entry: Sendable {
        let session: EPUBBookSession
        var initialToken: String?
        var initialData: Data?
        var bytesServed: Int = 0
    }

    private let entries = Mutex<[UUID: Entry]>([:])

    func register(session: EPUBBookSession) {
        entries.withLock { map in
            map[session.bookID] = Entry(session: session)
        }
    }

    func unregister(bookID: UUID) {
        entries.withLock { map in
            _ = map.removeValue(forKey: bookID)
        }
    }

    func stageInitialHTML(_ html: Data, token: String, for bookID: UUID) {
        entries.withLock { map in
            map[bookID]?.initialToken = token
            map[bookID]?.initialData = html
        }
    }

    func initialHTML(token: String, for bookID: UUID) -> Data? {
        entries.withLock { map in
            guard map[bookID]?.initialToken == token else { return nil }
            return map[bookID]?.initialData
        }
    }

    func recordBytes(_ count: Int, for bookID: UUID) {
        entries.withLock { map in
            map[bookID]?.bytesServed += count
        }
    }

    func totalBytesServed(for bookID: UUID) -> Int {
        entries.withLock { $0[bookID]?.bytesServed ?? 0 }
    }

    func session(for bookID: UUID) -> EPUBBookSession? {
        entries.withLock { $0[bookID]?.session }
    }

    func resourceData(for url: URL) -> Data? {
        guard url.scheme == Self.scheme,
              let host = url.host(),
              let bookID = UUID(uuidString: host),
              let session = session(for: bookID)
        else { return nil }
        return session.resourceData(for: url.path)?.data
    }
}

final class EPUBSchemeHandler: NSObject, WKURLSchemeHandler {
    static let shared = EPUBSchemeHandler()

    private var activeTaskIDs: Set<ObjectIdentifier> = []
    private var runningTasks: [ObjectIdentifier: Task<Void, Never>] = [:]

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let taskID = ObjectIdentifier(urlSchemeTask)
        activeTaskIDs.insert(taskID)

        guard let url = urlSchemeTask.request.url,
              let host = url.host(),
              let bookID = UUID(uuidString: host),
              let session = EPUBSchemeRegistry.shared.session(for: bookID)
        else {
            finishWithError(urlSchemeTask, taskID: taskID, code: 404)
            return
        }

        let path = url.path

        if path.hasPrefix("/__reader/") {
            let token = String(path.dropFirst("/__reader/".count))
            if let data = EPUBSchemeRegistry.shared.initialHTML(token: token, for: bookID) {
                reply(urlSchemeTask, taskID: taskID, url: url, data: data, mimeType: "text/html; charset=utf-8", cacheable: false, bookID: bookID)
            } else {
                finishWithError(urlSchemeTask, taskID: taskID, code: 404)
            }
            return
        }

        if path.hasPrefix("/__chapter/") {
            let rawIndex = String(path.dropFirst("/__chapter/".count))
            guard let index = Int(rawIndex) else {
                finishWithError(urlSchemeTask, taskID: taskID, code: 400)
                return
            }
            let task = Task { [weak self] in
                let data = await Self.loadChapterJSON(session: session, index: index)
                guard let self, self.activeTaskIDs.contains(taskID) else { return }
                if let data {
                    self.reply(urlSchemeTask, taskID: taskID, url: url, data: data, mimeType: "application/json; charset=utf-8", cacheable: true, bookID: bookID)
                } else {
                    self.finishWithError(urlSchemeTask, taskID: taskID, code: 404)
                }
            }
            runningTasks[taskID] = task
            return
        }

        if path.hasPrefix("/__footnote/") {
            let rest = path.dropFirst("/__footnote/".count)
            let parts = rest.split(separator: "/", maxSplits: 1)
            guard parts.count == 2, let chapterIndex = Int(parts[0]) else {
                finishWithError(urlSchemeTask, taskID: taskID, code: 400)
                return
            }
            let fragment = String(parts[1]).removingPercentEncoding ?? String(parts[1])
            let task = Task { [weak self] in
                let data = await Self.loadFootnoteJSON(session: session, chapterIndex: chapterIndex, fragment: fragment)
                guard let self, self.activeTaskIDs.contains(taskID) else { return }
                self.reply(urlSchemeTask, taskID: taskID, url: url, data: data, mimeType: "application/json; charset=utf-8", cacheable: true, bookID: bookID)
            }
            runningTasks[taskID] = task
            return
        }

        let task = Task { [weak self] in
            let result = await Self.loadResource(session: session, path: path)
            guard let self, self.activeTaskIDs.contains(taskID) else { return }
            if let result {
                self.reply(urlSchemeTask, taskID: taskID, url: url, data: result.data, mimeType: result.mimeType, cacheable: true, bookID: bookID)
            } else {
                self.finishWithError(urlSchemeTask, taskID: taskID, code: 404)
            }
        }
        runningTasks[taskID] = task
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        let taskID = ObjectIdentifier(urlSchemeTask)
        activeTaskIDs.remove(taskID)
        runningTasks.removeValue(forKey: taskID)?.cancel()
    }

    @concurrent
    private static func loadChapterJSON(session: EPUBBookSession, index: Int) async -> Data? {
        session.chapter(at: index)?.jsonData()
    }

    @concurrent
    private static func loadFootnoteJSON(session: EPUBBookSession, chapterIndex: Int, fragment: String) async -> Data {
        let text = session.footnoteText(chapterIndex: chapterIndex, fragment: fragment)
        let payload: [String: String?] = ["text": text]
        return (try? JSONEncoder().encode(payload)) ?? Data("{\"text\":null}".utf8)
    }

    @concurrent
    private static func loadResource(session: EPUBBookSession, path: String) async -> (data: Data, mimeType: String)? {
        session.resourceData(for: path)
    }

    private func reply(
        _ task: any WKURLSchemeTask,
        taskID: ObjectIdentifier,
        url: URL,
        data: Data,
        mimeType: String,
        cacheable: Bool,
        bookID: UUID
    ) {
        guard activeTaskIDs.remove(taskID) != nil else { return }
        runningTasks.removeValue(forKey: taskID)
        EPUBSchemeRegistry.shared.recordBytes(data.count, for: bookID)
        var headers: [String: String] = [
            "Content-Type": mimeType,
            "Content-Length": "\(data.count)",
            "Access-Control-Allow-Origin": "*",
            "Cache-Control": cacheable ? "max-age=31536000, immutable" : "no-store",
        ]
        if mimeType.hasPrefix("text/html") {
            headers["X-Content-Type-Options"] = "nosniff"
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        PerfMonitor.log("epub_scheme_reply", bytes: data.count, detail: url.path)
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    private func finishWithError(_ task: any WKURLSchemeTask, taskID: ObjectIdentifier, code: Int) {
        guard activeTaskIDs.remove(taskID) != nil else { return }
        runningTasks.removeValue(forKey: taskID)
        task.didFailWithError(NSError(domain: NSURLErrorDomain, code: code))
    }
}

final class EPUBWebViewPool {
    static let shared = EPUBWebViewPool()

    private var warmWebView: WKWebView?
    private var warmed = false

    private static let runtimeScriptSource: String? = {
        guard let url = Bundle.main.url(forResource: "ChickenReader", withExtension: "js") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }()

    private init() {}

    func warmUpIfNeeded() {
        guard !warmed, warmWebView == nil else { return }
        warmed = true
        let webView = makeWebView()
        webView.loadHTMLString("<!doctype html><html><body></body></html>", baseURL: nil)
        warmWebView = webView
    }

    func acquire(messageHandler: any WKScriptMessageHandler) -> WKWebView {
        let webView: WKWebView
        if let pooled = warmWebView {
            warmWebView = nil
            webView = pooled
        } else {
            webView = makeWebView()
        }
        let controller = webView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: "chicken")
        controller.add(EPUBWeakMessageHandler(messageHandler), name: "chicken")
        return webView
    }

    func release(_ webView: WKWebView) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "chicken")
        if warmWebView == nil {
            webView.loadHTMLString("<!doctype html><html><body></body></html>", baseURL: nil)
            warmWebView = webView
        }
    }

    private func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(EPUBSchemeHandler.shared, forURLScheme: EPUBSchemeRegistry.scheme)
        let controller = configuration.userContentController
        if let script = Self.runtimeScriptSource {
            controller.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        #if os(iOS)
        configuration.dataDetectorTypes = []
        #endif

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isInspectable = true
        #if os(macOS)
        webView.setValue(false, forKey: "drawsBackground")
        #else
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        #endif
        return webView
    }
}

private final class EPUBWeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: (any WKScriptMessageHandler)?

    init(_ target: any WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
