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
    static let documentName = "__chicken-reader-v3.html"

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
        guard let match = html.firstMatch(of: /(?i)<body\b[^>]*>([\s\S]*?)<\/body>/) else { return html }
        return String(match.output.1)
    }

    static func stylesheetLinks(in html: String) -> [String] {
        html.matches(of: /(?i)<link\b[^>]*rel\s*=\s*["'][^"']*stylesheet[^"']*["'][^>]*>|<style\b[^>]*>[\s\S]*?<\/style>/).map { String($0.output) }
    }

    /// Points `src`/`href` attributes at the unpacked files. Links into other
    /// spine documents become in-page anchors so they work in the combined view.
    static func rewriteResourceURLs(
        in html: String,
        directory: String,
        root: URL,
        spineIndexByPath: [String: Int]
    ) -> String {
        html.replacing(/(?i)\b(src|href|xlink:href)\s*=\s*["']([^"']+)["']/) { match in
            let attribute = String(match.output.1)
            let value = HTMLText.decodeEntities(String(match.output.2))
            let lower = value.lowercased()
            if value.hasPrefix("#") || ["http:", "https:", "data:", "mailto:", "file:", "tel:"].contains(where: lower.hasPrefix) {
                return String(match.output.0)
            }
            let (path, fragment) = EPUBPath.split(value, relativeTo: directory)
            guard !path.isEmpty else { return String(match.output.0) }

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
}

extension String {
    /// djb2 hash that stays stable across launches (unlike `hashValue`).
    public var stableChickenHash: UInt64 {
        var hash: UInt64 = 5381
        for byte in utf8 { hash = hash &* 33 &+ UInt64(byte) }
        return hash
    }
}
