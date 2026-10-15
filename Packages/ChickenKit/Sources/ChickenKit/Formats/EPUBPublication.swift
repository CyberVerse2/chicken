import Foundation

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
    static let documentName = "__chicken-reader-v2.html"

    public static func prepare(bookAt archiveURL: URL, cacheDirectory: URL) throws -> EPUBPublication {
        let fileManager = FileManager.default
        pruneCache(at: cacheDirectory)

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
            // Touch so the pruner treats this book as recently used.
            try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: root.path)
        }

        return EPUBPublication(rootURL: root, documentURL: documentURL, package: package)
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

        let language = package.metadata.language.map { " lang=\"\($0)\"" } ?? ""
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
        guard let regex = try? NSRegularExpression(pattern: #"<body\b[^>]*>([\s\S]*?)</body>"#, options: [.caseInsensitive]) else {
            return html
        }
        let ns = html as NSString
        guard let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)) else { return html }
        return ns.substring(with: match.range(at: 1))
    }

    static func stylesheetLinks(in html: String) -> [String] {
        let pattern = #"<link\b[^>]*rel\s*=\s*["'][^"']*stylesheet[^"']*["'][^>]*>|<style\b[^>]*>[\s\S]*?</style>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    /// Points `src`/`href` attributes at the unpacked files. Links into other
    /// spine documents become in-page anchors so they work in the combined view.
    static func rewriteResourceURLs(
        in html: String,
        directory: String,
        root: URL,
        spineIndexByPath: [String: Int]
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\b(src|href|xlink:href)\s*=\s*["']([^"']+)["']"#, options: [.caseInsensitive]) else {
            return html
        }
        let ns = html as NSString
        let result = NSMutableString(string: html)
        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).reversed() {
            let attribute = ns.substring(with: match.range(at: 1))
            let value = HTMLText.decodeEntities(ns.substring(with: match.range(at: 2)))
            let lower = value.lowercased()
            if value.hasPrefix("#") || ["http:", "https:", "data:", "mailto:", "file:", "tel:"].contains(where: lower.hasPrefix) {
                continue
            }
            let (path, fragment) = EPUBPath.split(value, relativeTo: directory)
            guard !path.isEmpty else { continue }

            let rewritten: String
            if attribute.lowercased() != "src", let spineIndex = spineIndexByPath[path] {
                rewritten = fragment.map { "#\($0)" } ?? "#chapter-\(spineIndex)"
            } else {
                rewritten = root.appendingPathComponent(path).absoluteString + (fragment.map { "#\($0)" } ?? "")
            }
            result.replaceCharacters(in: match.range, with: "\(attribute)=\"\(rewritten)\"")
        }
        return result as String
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
