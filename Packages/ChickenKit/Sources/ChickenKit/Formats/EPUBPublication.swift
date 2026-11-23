import Foundation
import Synchronization

/// An EPUB unpacked into the caches directory and stitched into one HTML
/// document, ready for a web view. Each spine document becomes a
/// `<section id="chapter-N" data-chicken-spine-index="N">`, which the reader
/// script uses for chapter tracking, pagination, and restoring positions.
public struct EPUBPublication: Sendable {
    public let rootURL: URL
    public let documentURL: URL
    public let package: EPUBPackage

    public var spine: [EPUBPackage.SpineItem] { package.spine }

    /// Bump when the generated HTML changes shape so stale caches rebuild.
    static let documentName = "__chicken-reader-v3.html"
    private static let lastPruneAt = Mutex<Date>(.distantPast)

    public static func prepare(bookAt archiveURL: URL, cacheDirectory: URL) throws -> EPUBPublication {
        let fileManager = FileManager.default
        pruneCacheIfNeeded(at: cacheDirectory)

        let archive = try ZipArchive(url: archiveURL)
        let package = try EPUBPackage(archive: archive)
        let root = cacheRoot(for: archiveURL, in: cacheDirectory)
        let documentURL = root.appendingPathComponent(documentName)

        if !fileManager.fileExists(atPath: documentURL.path) {
            if fileManager.fileExists(atPath: root.path) {
                try? fileManager.removeItem(at: root)
            }
            try archive.extractAll(to: root)
            try combinedHTML(package: package, root: root).write(to: documentURL, atomically: true, encoding: .utf8)
        } else {
            try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: root.path)
        }

        return EPUBPublication(rootURL: root, documentURL: documentURL, package: package)
    }

    public static func pruneCacheIfNeeded(at cacheDirectory: URL, maxBytes: Int = 1_500_000_000, minInterval: TimeInterval = 3600) {
        let now = Date()
        let shouldPrune = lastPruneAt.withLock { last -> Bool in
            guard now.timeIntervalSince(last) >= minInterval else { return false }
            last = now
            return true
        }
        guard shouldPrune else { return }
        pruneCache(at: cacheDirectory, maxBytes: maxBytes)
    }

    // MARK: Cache management

    static func cacheRoot(for archiveURL: URL, in cacheDirectory: URL) -> URL {
        let values = try? archiveURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let signature = "\(archiveURL.lastPathComponent)|\(values?.fileSize ?? 0)|\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        let name = archiveURL.deletingPathExtension().lastPathComponent
        return cacheDirectory.appendingPathComponent("\(name)-\(String(signature.stableChickenHash, radix: 16))", isDirectory: true)
    }

    /// Drops unpacked books not opened for two weeks and keeps the cache under
    /// roughly 1.5 GB, evicting the least recently used first.
    static func pruneCache(at cacheDirectory: URL, maxBytes: Int = 1_500_000_000) {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .totalFileAllocatedSizeKey]
        guard let entries = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
            return
        }
        let cutoff = Date().addingTimeInterval(-14 * 24 * 60 * 60)
        var kept: [(url: URL, modified: Date, size: Int)] = []
        for entry in entries {
            let values = try? entry.resourceValues(forKeys: Set(keys))
            let modified = values?.contentModificationDate ?? .distantPast
            if modified < cutoff {
                try? fileManager.removeItem(at: entry)
            } else {
                kept.append((entry, modified, directorySize(entry)))
            }
        }
        var total = kept.reduce(0) { $0 + $1.size }
        for entry in kept.sorted(by: { $0.modified < $1.modified }) where total > maxBytes {
            try? fileManager.removeItem(at: entry.url)
            total -= entry.size
        }
    }

    private static func directorySize(_ url: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else {
            return 0
        }
        var total = 0
        for case let file as URL in enumerator {
            total += (try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0
        }
        return total
    }

    // MARK: Combined document

    static func combinedHTML(package: EPUBPackage, root: URL) -> String {
        var spineIndexByPath: [String: Int] = [:]
        for (index, item) in package.spine.enumerated() where spineIndexByPath[item.path] == nil {
            spineIndexByPath[item.path] = index
        }

        let sections = package.spine.enumerated().map { index, item -> String in
            let fileURL = root.appendingPathComponent(item.path)
            let raw = (try? String(contentsOf: fileURL, encoding: .utf8))
                ?? (try? String(contentsOf: fileURL, encoding: .isoLatin1))
                ?? ""
            let directory = EPUBPath.directory(of: item.path)
            let rewrite = { (html: String) in
                rewriteResourceURLs(in: html, directory: directory, root: root, spineIndexByPath: spineIndexByPath)
            }
            let styles = stylesheetLinks(in: raw).map(rewrite).joined(separator: "\n")
            let body = rewrite(bodyHTML(from: raw))
            return """
            <section class="chicken-spine-section" id="chapter-\(index)" data-chicken-spine-index="\(index)">
            \(styles)
            \(body)
            </section>
            """
        }.joined(separator: "\n")

        let language = package.metadata.language.map { value in
            let escaped = value
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            return " lang=\"\(escaped)\""
        } ?? ""
        return """
        <!doctype html>
        <html\(language)>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
          <style>
            .chicken-spine-section { min-height: 60vh; padding-bottom: 3.2rem; margin-bottom: 2.6rem; }
          </style>
        </head>
        <body class="chicken-reader-body">
        \(sections)
        </body>
        </html>
        """
    }

    static func bodyHTML(from html: String) -> String {
        guard let bodyOpen = html.range(of: "<body", options: .caseInsensitive) else { return html }
        guard let openEnd = html[bodyOpen.upperBound...].firstIndex(of: ">") else { return html }
        let contentStart = html.index(after: openEnd)
        if let bodyClose = html.range(of: "</body>", options: [.caseInsensitive, .backwards], range: contentStart..<html.endIndex) {
            return String(html[contentStart..<bodyClose.lowerBound])
        }
        return String(html[contentStart...])
    }

    static func stylesheetLinks(in html: String) -> [String] {
        var results: [String] = []
        var cursor = html.startIndex
        while let lt = html[cursor...].firstIndex(of: "<") {
            let afterLT = html.index(after: lt)
            guard afterLT < html.endIndex else { break }
            if html[afterLT...].range(of: "link", options: [.caseInsensitive, .anchored]) != nil,
               afterLT < html.index(after: afterLT) || true {
                let afterTag = html.index(afterLT, offsetBy: min(4, html.distance(from: afterLT, to: html.endIndex)))
                if afterTag < html.endIndex && html[afterTag].isWhitespace,
                   let gt = html[afterTag...].firstIndex(of: ">") {
                    let tag = html[lt...gt]
                    if tag.range(of: "stylesheet", options: .caseInsensitive) != nil {
                        results.append(String(tag))
                    }
                    cursor = html.index(after: gt)
                    continue
                }
            }
            if html[afterLT...].range(of: "style", options: [.caseInsensitive, .anchored]) != nil {
                let afterTag = html.index(afterLT, offsetBy: min(5, html.distance(from: afterLT, to: html.endIndex)))
                if afterTag < html.endIndex && (html[afterTag] == ">" || html[afterTag].isWhitespace),
                   let close = html.range(of: "</style>", options: .caseInsensitive, range: afterTag..<html.endIndex) {
                    results.append(String(html[lt..<close.upperBound]))
                    cursor = close.upperBound
                    continue
                }
            }
            cursor = afterLT
        }
        return results
    }

    /// Points `src`/`href` attributes at the unpacked files. Links into other
    /// spine documents become in-page anchors so they work in the combined view.
    static func rewriteResourceURLs(
        in html: String,
        directory: String,
        root: URL,
        spineIndexByPath: [String: Int]
    ) -> String {
        rewriteResourceURLs(in: html, directory: directory, spineIndexByPath: spineIndexByPath, injectLazyImages: false)
    }

    static func rewriteResourceURLs(
        in html: String,
        directory: String,
        spineIndexByPath: [String: Int],
        injectLazyImages: Bool
    ) -> String {
        let utf8 = Array(html.utf8)
        let count = utf8.count
        var output = Data()
        output.reserveCapacity(count + 128)
        var lastCopied = 0
        var i = 0

        @inline(__always)
        func asciiLower(_ b: UInt8) -> UInt8 {
            (b >= 65 && b <= 90) ? (b &+ 32) : b
        }
        @inline(__always)
        func isIdentChar(_ b: UInt8) -> Bool {
            (b >= 97 && b <= 122) || (b >= 65 && b <= 90) || (b >= 48 && b <= 57) || b == 95 || b == 45 || b == 58
        }
        @inline(__always)
        func isSpace(_ b: UInt8) -> Bool {
            b == 32 || b == 9 || b == 10 || b == 13
        }
        @inline(__always)
        func matchesLower(_ at: Int, _ pattern: [UInt8]) -> Bool {
            guard at + pattern.count <= count else { return false }
            for k in 0..<pattern.count {
                if asciiLower(utf8[at + k]) != pattern[k] { return false }
            }
            return true
        }

        let patImg: [UInt8] = [60, 105, 109, 103]
        let patSrc: [UInt8] = [115, 114, 99]
        let patHref: [UInt8] = [104, 114, 101, 102]
        let patXlink: [UInt8] = [120, 108, 105, 110, 107, 58, 104, 114, 101, 102]

        while i < count {
            let byte = asciiLower(utf8[i])
            if injectLazyImages && byte == 60 && matchesLower(i, patImg) {
                let after = i + 4
                if after < count && isSpace(utf8[after]) {
                    if let gt = utf8[after...].firstIndex(of: 62) {
                        let tagSlice = String(decoding: utf8[i...gt], as: UTF8.self)
                        if tagSlice.range(of: "loading=", options: .caseInsensitive) == nil {
                            output.append(contentsOf: utf8[lastCopied..<after])
                            output.append(contentsOf: " loading=\"lazy\" decoding=\"async\"".utf8)
                            lastCopied = after
                        }
                    }
                    i = after
                    continue
                }
            }

            if (byte == 115 || byte == 104 || byte == 120) && (i == 0 || !isIdentChar(utf8[i - 1])) {
                let attrLen: Int
                if matchesLower(i, patSrc) {
                    attrLen = 3
                } else if matchesLower(i, patHref) {
                    attrLen = 4
                } else if matchesLower(i, patXlink) {
                    attrLen = 10
                } else {
                    i += 1
                    continue
                }
                var cursor = i + attrLen
                while cursor < count && isSpace(utf8[cursor]) { cursor += 1 }
                guard cursor < count, utf8[cursor] == 61 else { i += attrLen; continue }
                cursor += 1
                while cursor < count && isSpace(utf8[cursor]) { cursor += 1 }
                guard cursor < count else { break }
                let quote = utf8[cursor]
                guard quote == 34 || quote == 39 else { i = cursor; continue }
                let valueStart = cursor + 1
                guard let valueEnd = utf8[valueStart...].firstIndex(of: quote) else { i = valueStart; continue }

                if valueEnd > valueStart {
                    let rawValue = String(decoding: utf8[valueStart..<valueEnd], as: UTF8.self)
                    let attrName = String(decoding: utf8[i..<(i + attrLen)], as: UTF8.self)
                    if let replacement = rewriteAttribute(attribute: attrName, rawValue: rawValue, directory: directory, spineIndexByPath: spineIndexByPath) {
                        output.append(contentsOf: utf8[lastCopied..<i])
                        output.append(contentsOf: replacement.utf8)
                        lastCopied = valueEnd + 1
                    }
                }
                i = valueEnd + 1
                continue
            }
            i += 1
        }
        if lastCopied == 0 { return html }
        output.append(contentsOf: utf8[lastCopied..<count])
        return String(decoding: output, as: UTF8.self)
    }

    private static func rewriteAttribute(
        attribute: String,
        rawValue: String,
        directory: String,
        spineIndexByPath: [String: Int]
    ) -> String? {
        let value = HTMLText.decodeEntities(rawValue)
        let lower = value.lowercased()
        if value.hasPrefix("#") || ["http:", "https:", "data:", "mailto:", "file:", "tel:"].contains(where: lower.hasPrefix) {
            return nil
        }
        let (path, fragment) = EPUBPath.split(value, relativeTo: directory)
        guard !path.isEmpty else { return nil }

        if attribute.lowercased() != "src", let spineIndex = spineIndexByPath[path] {
            if let fragment {
                return "\(attribute)=\"#\(fragment)\" data-chicken-target-chapter=\"\(spineIndex)\""
            }
            return "\(attribute)=\"#chapter-\(spineIndex)\""
        }
        let encodedPath = path
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { segment in
                String(segment).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(segment)
            }
            .joined(separator: "/")
        let rewritten = encodedPath + (fragment.map { "#\($0)" } ?? "")
        return "\(attribute)=\"\(rewritten)\""
    }
}

extension String {
    /// djb2 hash that stays stable across launches (unlike `hashValue`).
    public var stableChickenHash: UInt64 {
        var hash: UInt64 = 5381
        for byte in utf8 { hash = hash &* 33 &+ UInt64(byte) }
        return hash
    }
}
