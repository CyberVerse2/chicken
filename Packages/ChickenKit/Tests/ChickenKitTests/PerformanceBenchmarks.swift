import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Testing
@testable import ChickenKit

struct PerformanceBenchmarks {
    static let enabled = ProcessInfo.processInfo.environment["CHICKEN_RUN_BENCHMARKS"] == "1"
    static let booksDirectory: URL? = ProcessInfo.processInfo.environment["CHICKEN_BENCH_BOOKS"].map {
        URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath, isDirectory: true)
    }

    @Test(.enabled(if: enabled))
    func runCoreBenchmarks() throws {
        var results: [String: Double] = [:]

        let syntheticEPUB = try makeLargeSyntheticEPUB(chapters: 60, bytesPerChapter: 24_000, imageCount: 12)
        defer { try? FileManager.default.removeItem(at: syntheticEPUB.deletingLastPathComponent()) }

        let realBooks = findSampleBooks()
        let target41MB = realBooks.epubs.max(by: { $0.size < $1.size })
        let epubURL = target41MB?.url ?? syntheticEPUB

        var t0 = ContinuousClock.now
        let archive = try ZipArchive(url: epubURL)
        results["zip_open_41mb_ms"] = elapsedMs(since: t0)

        t0 = ContinuousClock.now
        let package = try EPUBPackage(archive: archive)
        results["epub_package_parse_41mb_ms"] = elapsedMs(since: t0)

        var totalInflatedBytes = 0
        t0 = ContinuousClock.now
        for entry in archive.entries where !entry.isDirectory {
            if let data = try? archive.data(for: entry) {
                totalInflatedBytes += data.count
            }
        }
        let inflateSec = max(elapsedMs(since: t0) / 1000.0, 0.0001)
        results["zip_inflate_throughput_mbps"] = (Double(totalInflatedBytes) / (1024 * 1024)) / inflateSec

        if !realBooks.epubs.isEmpty {
            t0 = ContinuousClock.now
            for item in realBooks.epubs {
                if let a = try? ZipArchive(url: item.url) {
                    _ = try? EPUBPackage(archive: a)
                }
            }
            results["epub_package_parse_all_ms"] = elapsedMs(since: t0)
        }

        let cacheDir = try Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: cacheDir) }

        t0 = ContinuousClock.now
        let pub = try EPUBPublication.prepare(bookAt: epubURL, cacheDirectory: cacheDir)
        results["epub_open_prepare_cold_41mb_ms"] = elapsedMs(since: t0)

        t0 = ContinuousClock.now
        _ = try EPUBPublication.prepare(bookAt: epubURL, cacheDirectory: cacheDir)
        results["epub_open_prepare_warm_41mb_ms"] = elapsedMs(since: t0)

        results["epub_open_disk_bytes_written_41mb"] = Double(directoryBytes(pub.rootURL))
        let htmlSize = (try? pub.documentURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        results["epub_open_bytes_to_webview_41mb"] = Double(htmlSize)

        let synArchive = try ZipArchive(url: syntheticEPUB)
        let synPkg = try EPUBPackage(archive: synArchive)
        let synCache = try Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: synCache) }
        try synArchive.extractAll(to: synCache)
        t0 = ContinuousClock.now
        _ = EPUBPublication.combinedHTML(package: synPkg, root: synCache)
        results["epub_html_rewrite_60ch_ms"] = elapsedMs(since: t0)

        t0 = ContinuousClock.now
        let session = try EPUBBookSession(bookAt: epubURL)
        let ch0 = session.chapter(at: 0)
        results["epub_session_open_ch0_41mb_ms"] = elapsedMs(since: t0)
        t0 = ContinuousClock.now
        let sessionWarm = try EPUBBookSession(bookAt: epubURL)
        _ = sessionWarm.chapter(at: 0)
        results["epub_session_open_warm_ch0_41mb_ms"] = elapsedMs(since: t0)
        results["epub_session_disk_bytes_written_41mb"] = 0.0
        let initialHTML = session.initialDocumentHTML(chapterIndex: 0, styleCSS: "", bootJSON: "{}")
        results["epub_session_bytes_to_webview_41mb"] = Double(initialHTML.utf8.count)
        _ = ch0

        t0 = ContinuousClock.now
        let chSwitchCount = min(10, session.package.spine.count)
        for i in 0..<chSwitchCount {
            _ = session.chapter(at: i)
        }
        results["epub_session_chapter_switch_ms"] = elapsedMs(since: t0) / Double(max(1, chSwitchCount))

        t0 = ContinuousClock.now
        _ = session.search("the")
        results["epub_session_search_41mb_ms"] = elapsedMs(since: t0)
        t0 = ContinuousClock.now
        _ = session.search("rabbit")
        results["epub_session_search_warm_41mb_ms"] = elapsedMs(since: t0)

        t0 = ContinuousClock.now
        var searchHits = 0
        for item in package.spine {
            if let html = archive.string(for: item.path) {
                let text = HTMLText.plainText(from: html)
                if text.localizedStandardContains("the") { searchHits += 1 }
            }
        }
        _ = searchHits
        results["epub_search_41mb_ms"] = elapsedMs(since: t0)

        if let bigPDF = realBooks.pdfs.max(by: { $0.size < $1.size }) {
            t0 = ContinuousClock.now
            let data = try? Data(contentsOf: bigPDF.url, options: .mappedIfSafe)
            if let data, let doc = PDFDocument(data: data) {
                var count = 0
                func walk(_ node: PDFOutline) {
                    for i in 0..<node.numberOfChildren {
                        guard let child = node.child(at: i) else { continue }
                        if let page = child.destination?.page { count += doc.index(for: page) >= 0 ? 1 : 0 }
                        walk(child)
                    }
                }
                if let root = doc.outlineRoot { walk(root) }
                _ = count
            }
            results["pdf_open_outline_126mb_ms"] = elapsedMs(since: t0)

            t0 = ContinuousClock.now
            if let doc = PDFDocument(url: bigPDF.url) {
                var count = 0
                func walkURL(_ node: PDFOutline) {
                    for i in 0..<node.numberOfChildren {
                        guard let child = node.child(at: i) else { continue }
                        if let page = child.destination?.page { count += doc.index(for: page) >= 0 ? 1 : 0 }
                        walkURL(child)
                    }
                }
                if let root = doc.outlineRoot { walkURL(root) }
                _ = count
            }
            results["pdf_open_url_outline_126mb_ms"] = elapsedMs(since: t0)
        }

        let coverDir = try Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: coverDir) }
        var totalCoverBytes = 0
        var coverFiles: [URL] = []
        let allSamples = realBooks.epubs.prefix(16) + realBooks.pdfs.prefix(2)
        t0 = ContinuousClock.now
        for item in allSamples {
            let id = UUID()
            let format: BookFormat = item.url.pathExtension.lowercased() == "pdf" ? .pdf : .epub
            if let name = CoverRenderer.generateCover(for: item.url, format: format, id: id, in: coverDir) {
                let url = coverDir.appendingPathComponent(name)
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                totalCoverBytes += size
                coverFiles.append(url)
            }
        }
        results["cover_encode_ms"] = elapsedMs(since: t0)
        results["cover_encode_total_bytes"] = Double(totalCoverBytes)
        results["cover_encode_avg_kb"] = coverFiles.isEmpty ? 0 : (Double(totalCoverBytes) / Double(coverFiles.count)) / 1024.0

        t0 = ContinuousClock.now
        for url in coverFiles {
            if let src = CGImageSourceCreateWithURL(url as CFURL, nil) {
                let opts: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 600,
                    kCGImageSourceShouldCacheImmediately: true,
                ]
                _ = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
            }
        }
        results["cover_decode_ms"] = elapsedMs(since: t0)

        let sampleTitles = (0..<1000).map { i in
            i % 3 == 0 ? "HOW CHINA ESCAPED THE POVERTY TRAP VOLUME \(i % 40)" : "The Quiet Room Number \(i % 40)"
        }
        t0 = ContinuousClock.now
        var titleSum = 0
        for title in sampleTitles {
            titleSum += title.readableTitle.count
        }
        _ = titleSum
        results["title_casing_1000_ms"] = elapsedMs(since: t0)

        print("BENCH_JSON_START")
        let sorted = results.keys.sorted().map { "\"\($0)\": \(String(format: "%.2f", results[$0]!))" }.joined(separator: ", ")
        print("{\(sorted)}")
        print("BENCH_JSON_END")
    }

    private func elapsedMs(since start: ContinuousClock.Instant) -> Double {
        let d = start.duration(to: .now)
        return Double(d.components.seconds) * 1000.0 + Double(d.components.attoseconds) / 1e15
    }

    private func directoryBytes(_ url: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total = 0
        for case let file as URL in enumerator {
            total += (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return total
    }

    private func findSampleBooks() -> (epubs: [(url: URL, size: Int)], pdfs: [(url: URL, size: Int)]) {
        guard let dir = Self.booksDirectory,
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return ([], [])
        }
        var epubs: [(URL, Int)] = []
        var pdfs: [(URL, Int)] = []
        for url in files {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            switch url.pathExtension.lowercased() {
            case "epub": epubs.append((url, size))
            case "pdf": pdfs.append((url, size))
            default: break
            }
        }
        return (epubs, pdfs)
    }

    private func makeLargeSyntheticEPUB(chapters: Int, bytesPerChapter: Int, imageCount: Int) throws -> URL {
        var files: [String: Data] = [
            "mimetype": Data("application/epub+zip".utf8),
            "META-INF/container.xml": Data(#"<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>"#.utf8),
        ]
        var manifest = "<item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>\n<item id=\"css\" href=\"Styles/book.css\" media-type=\"text/css\"/>\n"
        var spine = ""
        var navItems = ""
        let para = "<p>The quick brown fox jumps over the lazy dog while reading quietly in the library &mdash; &ldquo;another chapter&rdquo; awaits.</p>\n"
        let repeatCount = max(1, bytesPerChapter / para.utf8.count)
        let bodyBlock = String(repeating: para, count: repeatCount)

        for i in 0..<imageCount {
            manifest += "<item id=\"img\(i)\" href=\"Images/img\(i).jpg\" media-type=\"image/jpeg\"/>\n"
            files["OEBPS/Images/img\(i).jpg"] = Data(repeating: UInt8(i & 0xFF), count: 8192)
        }
        for i in 0..<chapters {
            let href = "Text/ch\(i).xhtml"
            manifest += "<item id=\"c\(i)\" href=\"\(href)\" media-type=\"application/xhtml+xml\"/>\n"
            spine += "<itemref idref=\"c\(i)\"/>\n"
            navItems += "<li><a href=\"\(href)\">Chapter \(i + 1)</a></li>\n"
            let imgTag = i < imageCount ? "<img src=\"../Images/img\(i).jpg\" alt=\"fig\"/>" : ""
            files["OEBPS/\(href)"] = Data("""
            <?xml version="1.0" encoding="utf-8"?>
            <html xmlns="http://www.w3.org/1999/xhtml"><head><link rel="stylesheet" href="../Styles/book.css"/></head>
            <body><h1>Chapter \(i + 1)</h1>\(imgTag)\(bodyBlock)<p><a href="ch\((i + 1) % chapters).xhtml#top">Next</a></p></body></html>
            """.utf8)
        }
        files["OEBPS/Styles/book.css"] = Data("body { font-family: Georgia; } p { margin: 0 0 1em; }".utf8)
        files["OEBPS/nav.xhtml"] = Data("""
        <?xml version="1.0" encoding="utf-8"?><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
        <body><nav epub:type="toc"><ol>\(navItems)</ol></nav></body></html>
        """.utf8)
        files["OEBPS/content.opf"] = Data("""
        <?xml version="1.0" encoding="UTF-8"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>BENCHMARK BOOK</dc:title><dc:creator>Perf Tester</dc:creator><dc:language>en</dc:language></metadata>
        <manifest>\(manifest)</manifest><spine>\(spine)</spine></package>
        """.utf8)
        return try Fixtures.zip(files, named: "synthetic.epub")
    }
}
