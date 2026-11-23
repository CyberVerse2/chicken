#if DEBUG && os(macOS)
import AppKit
import ChickenKit
import PDFKit
import QuartzCore
import SwiftData
import SwiftUI
import WebKit

@MainActor
final class ScrollBenchmarkRunner: NSObject {
    static let shared = ScrollBenchmarkRunner()

    private struct ScenarioSpec {
        let id: String
        let title: String
        let format: BookFormat
        let sourcePath: String?
        let generatedKind: GeneratedKind?
        let mode: ReadingMode
        let theme: ReadingTheme
        let darkModePDF: Bool
        let pagedTurns: Bool

        enum GeneratedKind {
            case plainText
            case markdown
            case rtf
        }
    }

    private struct ScenarioMetrics: Encodable {
        let id: String
        let status: String
        let frames: Int
        let duration_s: Double
        let fps: Double
        let expected_frame_ms: Double
        let p50_ms: Double
        let p95_ms: Double
        let p99_ms: Double
        let max_ms: Double
        let hitches_20ms: Int
        let hitches_33ms: Int
        let hitches_50ms: Int
        let hitch_ms_per_s: Double
        let scroll_px: Double
        let progress_delta: Double
        let extra: [String: Double]
    }

    private var window: NSWindow?
    private var activeLink: CADisplayLink?
    private var isRunning = false

    func startIfRequested() {
        guard let raw = ProcessInfo.processInfo.environment["CHICKEN_SCROLL_BENCH"], !raw.isEmpty else { return }
        guard !isRunning else { return }
        isRunning = true

        let requested = Set(
            raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        )
        let runAll = requested.contains("all") || requested.contains("1")

        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(250))
            await self.runAll(filter: runAll ? nil : requested)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(120))
            print("SCROLL_BENCH_TIMEOUT")
            fflush(stdout)
            exit(2)
        }
    }

    private func allScenarios() -> [ScenarioSpec] {
        let booksDir = NSHomeDirectory() + "/Library/Application Support/Chicken Development/Books/"
        return [
            ScenarioSpec(
                id: "epub_chapters",
                title: "EPUB 101 Chapters Scroll",
                format: .epub,
                sourcePath: booksDir + "2D997789-738A-4237-9380-A8FDF6353599.epub",
                generatedKind: nil,
                mode: .scroll,
                theme: .paper,
                darkModePDF: false,
                pagedTurns: false
            ),
            ScenarioSpec(
                id: "epub_images",
                title: "EPUB 781 Images Scroll",
                format: .epub,
                sourcePath: booksDir + "F47A669F-5157-4C9F-ADDB-D381EAFDF497.epub",
                generatedKind: nil,
                mode: .scroll,
                theme: .paper,
                darkModePDF: false,
                pagedTurns: false
            ),
            ScenarioSpec(
                id: "epub_paged",
                title: "EPUB Paged Turns",
                format: .epub,
                sourcePath: booksDir + "2D997789-738A-4237-9380-A8FDF6353599.epub",
                generatedKind: nil,
                mode: .paged,
                theme: .paper,
                darkModePDF: false,
                pagedTurns: true
            ),
            ScenarioSpec(
                id: "pdf_heavy_light",
                title: "PDF 132MB Light Scroll",
                format: .pdf,
                sourcePath: booksDir + "214DAEB6-7A0E-4AB5-AD8A-A61DF58252EE.pdf",
                generatedKind: nil,
                mode: .scroll,
                theme: .paper,
                darkModePDF: false,
                pagedTurns: false
            ),
            ScenarioSpec(
                id: "pdf_heavy_dark",
                title: "PDF 132MB Ink Dark Scroll",
                format: .pdf,
                sourcePath: booksDir + "214DAEB6-7A0E-4AB5-AD8A-A61DF58252EE.pdf",
                generatedKind: nil,
                mode: .scroll,
                theme: .ink,
                darkModePDF: true,
                pagedTurns: false
            ),
            ScenarioSpec(
                id: "pdf_standard",
                title: "PDF 2.9MB Light Scroll",
                format: .pdf,
                sourcePath: booksDir + "190A17FD-5724-492E-89CF-984503642DF2.pdf",
                generatedKind: nil,
                mode: .scroll,
                theme: .paper,
                darkModePDF: false,
                pagedTurns: false
            ),
            ScenarioSpec(
                id: "text_plain",
                title: "Plain Text 600KB Scroll",
                format: .text,
                sourcePath: nil,
                generatedKind: .plainText,
                mode: .scroll,
                theme: .paper,
                darkModePDF: false,
                pagedTurns: false
            ),
            ScenarioSpec(
                id: "text_markdown",
                title: "Markdown 300KB Scroll",
                format: .text,
                sourcePath: nil,
                generatedKind: .markdown,
                mode: .scroll,
                theme: .paper,
                darkModePDF: false,
                pagedTurns: false
            ),
            ScenarioSpec(
                id: "text_rtf",
                title: "RTF 300KB Scroll",
                format: .text,
                sourcePath: nil,
                generatedKind: .rtf,
                mode: .scroll,
                theme: .paper,
                darkModePDF: false,
                pagedTurns: false
            ),
        ]
    }

    private func runAll(filter: Set<String>?) async {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        for existing in NSApp.windows {
            existing.orderOut(nil)
        }

        let window = NSWindow(
            contentRect: NSRect(x: 80, y: 80, width: 1240, height: 860),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Chicken Scroll Benchmark"
        window.makeKeyAndOrderFront(nil)
        self.window = window

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("chicken-scroll-bench-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        var results: [ScenarioMetrics] = []
        let specs = allScenarios().filter { filter == nil || filter!.contains($0.id) }

        for spec in specs {
            let result = await runScenario(spec, tempRoot: tempRoot, window: window)
            results.append(result)
            try? await Task.sleep(for: .milliseconds(250))
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let jsonData = try? encoder.encode(results), let json = String(data: jsonData, encoding: .utf8) {
            print("SCROLL_BENCH_JSON_START")
            print(json)
            print("SCROLL_BENCH_JSON_END")
            if let outPath = ProcessInfo.processInfo.environment["CHICKEN_SCROLL_BENCH_OUT"], !outPath.isEmpty {
                let outURL = URL(fileURLWithPath: outPath)
                try? FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? jsonData.write(to: outURL, options: .atomic)
            }
        }

        window.close()
        self.window = nil
        fflush(stdout)
        exit(0)
    }

    private func runScenario(_ spec: ScenarioSpec, tempRoot: URL, window: NSWindow) async -> ScenarioMetrics {
        let scenarioDir = tempRoot.appendingPathComponent(spec.id, isDirectory: true)
        let paths = LibraryPaths(root: scenarioDir, syncsWithICloud: false)
        try? paths.createDirectories()

        let suiteName = "cyberverse.Chicken.ScrollBench.\(spec.id).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let prefs = AppPreferences(defaults: defaults)
        prefs.theme = spec.theme
        let store = LibraryStore(paths: paths, preferences: prefs, inMemory: true)

        let ext: String
        switch spec.format {
        case .epub: ext = "epub"
        case .pdf: ext = "pdf"
        default:
            switch spec.generatedKind {
            case .markdown: ext = "md"
            case .rtf: ext = "rtf"
            case .plainText, nil: ext = "txt"
            }
        }
        let storedName = "\(UUID().uuidString).\(ext)"
        let destURL = paths.bookFile(named: storedName)

        if let sourcePath = spec.sourcePath {
            let srcURL = URL(fileURLWithPath: sourcePath)
            guard FileManager.default.fileExists(atPath: srcURL.path) else {
                return skippedMetric(id: spec.id, reason: "missing_source")
            }
            do {
                try FileManager.default.copyItem(at: srcURL, to: destURL)
            } catch {
                return skippedMetric(id: spec.id, reason: "copy_failed")
            }
        } else if let kind = spec.generatedKind {
            do {
                try writeGeneratedBook(kind: kind, to: destURL)
            } catch {
                return skippedMetric(id: spec.id, reason: "generate_failed")
            }
        }

        var extra: [String: Double] = [:]
        if spec.format == .text, let doc = await loadTextDoc(url: destURL) {
            let t0 = ContinuousClock.now
            _ = TextDocumentLoader.attributedString(
                doc,
                palette: spec.theme.palette,
                fontSize: ReaderPreferences.default.fontSize,
                lineHeight: ReaderPreferences.default.lineHeight,
                typeface: .default,
                highlights: []
            )
            let d = t0.duration(to: .now)
            extra["render_ms"] = Double(d.components.seconds) * 1000.0 + Double(d.components.attoseconds) / 1e15
        }

        let book = Book(
            title: spec.title,
            format: spec.format,
            originalFileName: "\(spec.title).\(ext)",
            storedFileName: storedName
        )
        book.preferences = ReaderPreferences(
            theme: spec.theme.rawValue,
            fontSize: ReaderPreferences.default.fontSize,
            lineHeight: ReaderPreferences.default.lineHeight,
            columnWidth: ReaderPreferences.default.columnWidth,
            readingMode: spec.mode.rawValue,
            zenMode: false,
            darkModePDF: spec.darkModePDF
        )
        store.context.insert(book)
        store.save()

        let rootView = ReaderView(book: book, library: store)
            .environment(store)
            .environment(AppRouter.shared)
            .modelContainer(store.container)
            .readingTheme(spec.theme)
            .frame(width: 1240, height: 860)

        let hosting = NSHostingController(rootView: rootView)
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 1240, height: 860))
        window.layoutIfNeeded()
        window.displayIfNeeded()

        let ready = await waitUntilReady(spec: spec, in: window, timeoutSeconds: 20.0)
        guard ready else {
            await logWaitFailure(spec: spec, in: window)
            window.contentViewController = nil
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
            return skippedMetric(id: spec.id, reason: "timeout_waiting_ready")
        }

        try? await Task.sleep(for: .milliseconds(500))

        let startOffset = await measureScrollOffset(spec: spec, in: window)
        let startProgress = book.progress

        if spec.format == .epub, let webView = findView(ofType: WKWebView.self, in: window.contentView) {
            _ = try? await webView.evaluateJavaScript("""
            (() => {
              window.__benchRAF = { times: [], running: true, last: 0 };
              const tick = (ts) => {
                if (!window.__benchRAF || !window.__benchRAF.running) return;
                if (window.__benchRAF.last > 0) window.__benchRAF.times.push(ts - window.__benchRAF.last);
                window.__benchRAF.last = ts;
                requestAnimationFrame(tick);
              };
              requestAnimationFrame(tick);
              return true;
            })()
            """)
        }

        let scrollStats = await runDisplayLinkScroll(
            spec: spec,
            window: window,
            durationSeconds: 4.0
        )

        let endOffset = await measureScrollOffset(spec: spec, in: window)
        let endProgress = book.progress

        if spec.format == .epub, let webView = findView(ofType: WKWebView.self, in: window.contentView) {
            if let jsRaw = try? await webView.evaluateJavaScript("""
            (() => {
              if (!window.__benchRAF) return null;
              window.__benchRAF.running = false;
              const times = window.__benchRAF.times.slice().sort((a, b) => a - b);
              const count = times.length;
              const pct = (p) => count ? times[Math.min(count - 1, Math.floor((count - 1) * p))] : 0;
              const hitches20 = times.filter(t => t > 20).length;
              const hitches33 = times.filter(t => t > 33.3).length;
              const mounted = document.querySelectorAll('[data-chicken-spine-index]').length;
              const snap = window.chicken ? window.chicken.snapshot() : null;
              return {
                js_raf_frames: count,
                js_raf_p50_ms: pct(0.5),
                js_raf_p95_ms: pct(0.95),
                js_raf_max_ms: count ? times[count - 1] : 0,
                js_raf_hitches_20ms: hitches20,
                js_raf_hitches_33ms: hitches33,
                mounted_chapters: mounted,
                js_progress: snap ? snap.progression : 0,
                js_page: snap ? snap.page : 0
              };
            })()
            """) as? [String: Any] {
                for (k, v) in jsRaw {
                    if let num = v as? NSNumber { extra[k] = num.doubleValue }
                }
            }
        }

        if spec.format == .pdf, let pdfView = findView(ofType: ChickenPDFView.self, in: window.contentView),
           let doc = pdfView.document, let page = pdfView.currentPage {
            extra["pdf_end_page"] = Double(doc.index(for: page))
            extra["pdf_visible_page"] = Double(pdfView.visiblePages.map { doc.index(for: $0) }.max() ?? 0)
            extra["pdf_total_pages"] = Double(doc.pageCount)
        }

        extra["paged_turns"] = Double(scrollStats.pagedTurns)

        window.contentViewController = nil
        UserDefaults.standard.removePersistentDomain(forName: suiteName)

        let sorted = scrollStats.frameDeltasMs.sorted()
        let count = sorted.count
        let pct = { (p: Double) -> Double in
            guard count > 0 else { return 0 }
            return sorted[min(count - 1, Int((Double(count - 1) * p).rounded(.down)))]
        }
        let expectedMs = scrollStats.expectedFrameMs > 0 ? scrollStats.expectedFrameMs : 16.67
        let threshold = expectedMs * 1.15
        let hitchTotal = sorted.reduce(0.0) { $0 + max(0.0, $1 - threshold) }
        let elapsed = max(0.001, scrollStats.elapsedSeconds)

        return ScenarioMetrics(
            id: spec.id,
            status: "ok",
            frames: count,
            duration_s: (elapsed * 100).rounded() / 100,
            fps: ((Double(count) / elapsed) * 10).rounded() / 10,
            expected_frame_ms: (expectedMs * 100).rounded() / 100,
            p50_ms: (pct(0.50) * 100).rounded() / 100,
            p95_ms: (pct(0.95) * 100).rounded() / 100,
            p99_ms: (pct(0.99) * 100).rounded() / 100,
            max_ms: ((sorted.last ?? 0) * 100).rounded() / 100,
            hitches_20ms: sorted.filter { $0 > 20.0 }.count,
            hitches_33ms: sorted.filter { $0 > 33.3 }.count,
            hitches_50ms: sorted.filter { $0 > 50.0 }.count,
            hitch_ms_per_s: ((hitchTotal / elapsed) * 100).rounded() / 100,
            scroll_px: ((endOffset - startOffset) * 10).rounded() / 10,
            progress_delta: ((endProgress - startProgress) * 10000).rounded() / 10000,
            extra: extra
        )
    }

    private func loadTextDoc(url: URL) async -> TextDocument? {
        if case .success(let doc) = await TextDocumentLoader.load(url) { return doc }
        return nil
    }

    private func logWaitFailure(spec: ScenarioSpec, in window: NSWindow) async {
        guard let root = window.contentView else {
            print("WAIT_FAIL \(spec.id): no window.contentView")
            return
        }
        if spec.format == .epub {
            if let webView = findView(ofType: WKWebView.self, in: root) {
                let info = try? await webView.evaluateJavaScript("[Boolean(window.chicken), document.querySelectorAll('[data-chicken-spine-index]').length, document.documentElement.scrollHeight, window.innerHeight]")
                print("WAIT_FAIL \(spec.id): webView found, info=\(String(describing: info))")
            } else {
                print("WAIT_FAIL \(spec.id): no WKWebView in hierarchy")
            }
        } else if spec.format == .pdf {
            if let pdfView = findView(ofType: ChickenPDFView.self, in: root) {
                print("WAIT_FAIL \(spec.id): pdfView found, doc=\(pdfView.document != nil), pages=\(pdfView.document?.pageCount ?? -1), currentPage=\(pdfView.currentPage != nil), bounds=\(pdfView.bounds)")
            } else {
                print("WAIT_FAIL \(spec.id): no ChickenPDFView in hierarchy")
            }
        }
    }

    private func waitUntilReady(spec: ScenarioSpec, in window: NSWindow, timeoutSeconds: Double) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(timeoutSeconds)
        while ContinuousClock.now < deadline {
            if let root = window.contentView {
                switch spec.format {
                case .epub:
                    if let webView = findView(ofType: WKWebView.self, in: root) {
                        let ready = (try? await webView.evaluateJavaScript("Boolean(window.chicken && document.querySelector('[data-chicken-spine-index]'))")) as? Bool ?? false
                        if ready {
                            if spec.pagedTurns { return true }
                            let scrollH = (try? await webView.evaluateJavaScript("document.documentElement.scrollHeight")) as? Double ?? 0
                            if scrollH > 600 { return true }
                        }
                    }
                case .pdf:
                    if let pdfView = findView(ofType: ChickenPDFView.self, in: root),
                       pdfView.document != nil, pdfView.currentPage != nil, pdfView.bounds.height > 100 {
                        return true
                    }
                default:
                    if let textScroll = findView(ofType: ColumnTextScrollView.self, in: root),
                       textScroll.textView.string.count > 100, textScroll.textView.frame.height > 800 {
                        return true
                    }
                }
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    private func measureScrollOffset(spec: ScenarioSpec, in window: NSWindow) async -> Double {
        guard let root = window.contentView else { return 0 }
        switch spec.format {
        case .epub:
            guard let webView = findView(ofType: WKWebView.self, in: root) else { return 0 }
            if spec.pagedTurns {
                return (try? await webView.evaluateJavaScript("window.chicken ? window.chicken.snapshot().page : 0")) as? Double ?? 0
            }
            return (try? await webView.evaluateJavaScript("window.scrollY || document.documentElement.scrollTop || 0")) as? Double ?? 0
        case .pdf:
            guard let pdfView = findView(ofType: ChickenPDFView.self, in: root) else { return 0 }
            if let scrollView = findView(ofType: NSScrollView.self, in: pdfView) {
                return Double(scrollView.contentView.bounds.minY)
            }
            if let doc = pdfView.document, let page = pdfView.currentPage {
                return Double(doc.index(for: page)) * 900.0
            }
            return 0
        default:
            guard let textScroll = findView(ofType: ColumnTextScrollView.self, in: root) else { return 0 }
            return Double(textScroll.contentView.bounds.minY)
        }
    }

    private struct ScrollRunOutput {
        let frameDeltasMs: [Double]
        let expectedFrameMs: Double
        let elapsedSeconds: Double
        let pagedTurns: Int
    }

    private func runDisplayLinkScroll(spec: ScenarioSpec, window: NSWindow, durationSeconds: Double) async -> ScrollRunOutput {
        guard let hostView = window.contentView else {
            return ScrollRunOutput(frameDeltasMs: [], expectedFrameMs: 16.67, elapsedSeconds: 0, pagedTurns: 0)
        }
        return await withCheckedContinuation { continuation in
            let driver = DisplayLinkDriver(
                spec: spec,
                window: window,
                durationSeconds: durationSeconds
            ) { output in
                self.activeLink?.invalidate()
                self.activeLink = nil
                continuation.resume(returning: output)
            }
            let link = hostView.displayLink(target: driver, selector: #selector(DisplayLinkDriver.step(_:)))
            driver.link = link
            self.activeLink = link
            link.add(to: .main, forMode: .common)
        }
    }

    @MainActor
    private final class DisplayLinkDriver: NSObject {
        let spec: ScenarioSpec
        weak var window: NSWindow?
        weak var link: CADisplayLink?
        let durationSeconds: Double
        let onFinish: (ScrollRunOutput) -> Void

        private var startTimestamp: CFTimeInterval = 0
        private var prevTimestamp: CFTimeInterval = 0
        private var lastPageTurnTime: CFTimeInterval = 0
        private var expectedSamples: [Double] = []
        private var frameDeltasMs: [Double] = []
        private var pagedTurns = 0
        private var finished = false
        private weak var cachedTargetView: NSView?

        init(spec: ScenarioSpec, window: NSWindow, durationSeconds: Double, onFinish: @escaping (ScrollRunOutput) -> Void) {
            self.spec = spec
            self.window = window
            self.durationSeconds = durationSeconds
            self.onFinish = onFinish
            super.init()
        }

        @objc func step(_ displayLink: CADisplayLink) {
            guard !finished else { return }
            let now = displayLink.timestamp
            if startTimestamp == 0 {
                startTimestamp = now
                prevTimestamp = now
                lastPageTurnTime = now
                return
            }

            let dtMs = (now - prevTimestamp) * 1000.0
            let expMs = (displayLink.targetTimestamp - now) * 1000.0
            if dtMs > 0 { frameDeltasMs.append(dtMs) }
            if expMs > 1.0 && expMs < 40.0 { expectedSamples.append(expMs) }
            prevTimestamp = now

            if let window {
                driveTick(window: window, now: now)
            }

            let elapsed = now - startTimestamp
            if elapsed >= durationSeconds {
                finished = true
                displayLink.invalidate()
                let medianExpected = expectedSamples.isEmpty ? 16.67 : expectedSamples.sorted()[expectedSamples.count / 2]
                onFinish(ScrollRunOutput(
                    frameDeltasMs: frameDeltasMs,
                    expectedFrameMs: medianExpected,
                    elapsedSeconds: elapsed,
                    pagedTurns: pagedTurns
                ))
            }
        }

        private func resolveTargetView(in window: NSWindow) -> NSView? {
            if let cachedTargetView, cachedTargetView.window === window {
                return cachedTargetView
            }
            guard let root = window.contentView else { return nil }
            let found: NSView?
            switch spec.format {
            case .epub:
                found = ScrollBenchmarkRunner.findView(ofType: WKWebView.self, in: root)
            case .pdf:
                if let pdf = ScrollBenchmarkRunner.findView(ofType: ChickenPDFView.self, in: root) {
                    found = pdf.documentView ?? ScrollBenchmarkRunner.findView(ofType: NSScrollView.self, in: pdf) ?? pdf
                } else {
                    found = nil
                }
            default:
                found = ScrollBenchmarkRunner.findView(ofType: ColumnTextScrollView.self, in: root)
            }
            cachedTargetView = found
            return found
        }

        private func driveTick(window: NSWindow, now: CFTimeInterval) {
            if spec.pagedTurns {
                if now - lastPageTurnTime >= 0.12 {
                    lastPageTurnTime = now
                    pagedTurns += 1
                    if let webView = resolveTargetView(in: window) as? WKWebView {
                        webView.evaluateJavaScript("window.chicken && window.chicken.turnPage(1, false)", completionHandler: nil)
                    }
                }
                return
            }

            guard let target = resolveTargetView(in: window) else { return }
            if let cgEvent = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 1,
                wheel1: -44,
                wheel2: 0,
                wheel3: 0
            ) {
                cgEvent.location = CGPoint(
                    x: window.frame.midX + 135,
                    y: window.frame.midY
                )
                if let nsEvent = NSEvent(cgEvent: cgEvent) {
                    target.scrollWheel(with: nsEvent)
                }
            }
            if spec.format == .pdf,
               let pdf = ScrollBenchmarkRunner.findView(ofType: ChickenPDFView.self, in: window.contentView),
               let sv = ScrollBenchmarkRunner.findView(ofType: NSScrollView.self, in: pdf) {
                sv.reflectScrolledClipView(sv.contentView)
            }
        }
    }

    private func skippedMetric(id: String, reason: String) -> ScenarioMetrics {
        ScenarioMetrics(
            id: id,
            status: reason,
            frames: 0,
            duration_s: 0,
            fps: 0,
            expected_frame_ms: 0,
            p50_ms: 0,
            p95_ms: 0,
            p99_ms: 0,
            max_ms: 0,
            hitches_20ms: 0,
            hitches_33ms: 0,
            hitches_50ms: 0,
            hitch_ms_per_s: 0,
            scroll_px: 0,
            progress_delta: 0,
            extra: [:]
        )
    }

    private static func findView<T: NSView>(ofType type: T.Type, in root: NSView?) -> T? {
        guard let root else { return nil }
        if let match = root as? T { return match }
        for sub in root.subviews {
            if let match = findView(ofType: type, in: sub) { return match }
        }
        return nil
    }

    private func findView<T: NSView>(ofType type: T.Type, in root: NSView?) -> T? {
        Self.findView(ofType: type, in: root)
    }

    private func writeGeneratedBook(kind: ScenarioSpec.GeneratedKind, to url: URL) throws {
        switch kind {
        case .plainText:
            var chunks: [String] = []
            chunks.reserveCapacity(6000)
            let p1 = "The wind moved across the harbor while the lanterns flickered along the stone pier, casting long reflections across the dark tide as the night watch walked slowly past the warehouses."
            let p2 = "Inside the archive room, tall oak shelves held ledgers bound in faded linen, their margins crowded with careful notes about shipping routes, barometer readings, and winter provisions."
            for i in 0..<3000 {
                chunks.append("Section \(i + 1). \(p1)")
                chunks.append(p2)
            }
            try chunks.joined(separator: "\n\n").write(to: url, atomically: true, encoding: .utf8)

        case .markdown:
            var lines: [String] = []
            lines.reserveCapacity(3000)
            for i in 0..<250 {
                lines.append("# Chapter \(i + 1): Notes on Long-Form Reading")
                lines.append("")
                lines.append("Typography exists to **honor content** and keep *prose crisp* with `inlineCode(\(i))` and [reference links](https://example.com/\(i)). Careful line measures make dense pages effortless to scan across long sessions.")
                lines.append("")
                lines.append("> Letters are things, not pictures of things. Measure and rhythm govern how the eye moves across the page.")
                lines.append("")
                lines.append("- Maintain generous margins and **consistent** rhythm")
                lines.append("- Preserve *quiet chrome* while scrolling fast")
                lines.append("- Render `attributed` runs without layout hitches")
                lines.append("")
                lines.append("```swift")
                lines.append("let measure = 620.0 + Double(\(i % 40))")
                lines.append("let leading = 1.78")
                lines.append("```")
                lines.append("")
            }
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)

        case .rtf:
            let attributed = NSMutableAttributedString()
            let titleFont = NSFont.boldSystemFont(ofSize: 22)
            let bodyFont = NSFont.systemFont(ofSize: 16)
            let italicFont = NSFontManager.shared.convert(bodyFont, toHaveTrait: .italicFontMask)
            let para = "Across the reading room the tall windows admitted pale northern light, illuminating stacks of manuscripts and annotated folios gathered from three centuries of correspondence.\n\n"
            for i in 0..<1200 {
                if i % 15 == 0 {
                    attributed.append(NSAttributedString(string: "Part \(i / 15 + 1)\n\n", attributes: [.font: titleFont]))
                }
                attributed.append(NSAttributedString(string: "Paragraph \(i + 1): ", attributes: [.font: italicFont]))
                attributed.append(NSAttributedString(string: para, attributes: [.font: bodyFont]))
            }
            let data = try attributed.data(
                from: NSRange(location: 0, length: attributed.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
            try data.write(to: url, options: .atomic)
        }
    }
}
#endif
