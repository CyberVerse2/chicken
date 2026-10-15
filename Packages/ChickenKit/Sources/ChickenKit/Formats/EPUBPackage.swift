import Foundation

/// Parsed OPF package of an EPUB: metadata, manifest, reading order, table of
/// contents, and cover image location. All paths are archive-absolute
/// (e.g. `OEBPS/Text/ch01.xhtml`), percent-decoded, and normalised.
public struct EPUBPackage: Sendable {
    public struct ManifestItem: Sendable, Hashable {
        public let id: String
        /// The `href` exactly as written in the OPF.
        public let href: String
        public let path: String
        public let mediaType: String?
        public let properties: String?
        public let title: String?

        public var isReadableDocument: Bool {
            let lower = href.lowercased()
            return mediaType?.contains("html") == true
                || lower.hasSuffix(".xhtml")
                || lower.hasSuffix(".html")
                || lower.hasSuffix(".htm")
        }

        public var isImage: Bool {
            mediaType?.hasPrefix("image/") == true
                || href.range(of: #"\.(jpe?g|png|gif|webp)$"#, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    public struct SpineItem: Sendable, Hashable {
        public let id: String
        public let path: String
        public let title: String
        public let tocLevel: Int
        /// Identifier stored in saved reading locations. Matches what earlier
        /// versions of Chicken wrote (package directory + raw href), so
        /// positions saved before the rebuild still resolve.
        public let locationHref: String
    }

    public struct TOCEntry: Sendable, Hashable {
        public let title: String
        public let path: String
        public let fragment: String?
        public let level: Int
    }

    public enum PackageError: Error {
        case missingContainer
        case missingPackage
        case emptySpine
    }

    public let packagePath: String
    public let metadata: DocumentMetadata
    public let manifest: [String: ManifestItem]
    public let spine: [SpineItem]
    public let tableOfContents: [TOCEntry]
    public let coverImagePath: String?

    public init(archive: ZipArchive) throws {
        guard
            let containerData = try? archive.data(for: "META-INF/container.xml"),
            let container = MarkupNode.parse(containerData)
        else { throw PackageError.missingContainer }

        let rootfiles = container.descendants("rootfile")
        let opfRootfile = rootfiles.first { node in
            let mediaType = node.attribute("media-type") ?? "application/oebps-package+xml"
            return mediaType.contains("oebps")
        }
        guard
            let packagePath = (opfRootfile ?? rootfiles.first)?.attribute("full-path"),
            let packageData = try? archive.data(for: packagePath),
            let package = MarkupNode.parse(packageData)
        else { throw PackageError.missingPackage }

        self.packagePath = packagePath
        let packageDirectory = EPUBPath.directory(of: packagePath)

        // Manifest
        var manifest: [String: ManifestItem] = [:]
        for item in package.firstDescendant("manifest")?.children("item") ?? [] {
            guard let id = item.attribute("id"), let href = item.attribute("href") else { continue }
            manifest[id] = ManifestItem(
                id: id,
                href: href,
                path: EPUBPath.resolve(href, relativeTo: packageDirectory),
                mediaType: item.attribute("media-type"),
                properties: item.attribute("properties"),
                title: item.attribute("title")
            )
        }
        self.manifest = manifest

        // Metadata
        let metadataNode = package.firstDescendant("metadata")
        func value(_ name: String) -> String? {
            let text = metadataNode?.firstDescendant(name)?.textContent
            return DocumentMetadata.clean(text.map { HTMLText.decodeEntities($0) })
        }
        let description = value("description").map { HTMLText.plainText(from: $0) }
        metadata = DocumentMetadata(
            title: value("title"),
            author: value("creator"),
            pageCount: nil,
            publisher: value("publisher"),
            language: value("language"),
            summary: DocumentMetadata.clean(description)
        )

        // Table of contents
        let toc = Self.tableOfContents(archive: archive, package: package, manifest: manifest)
        tableOfContents = toc
        var tocByPath: [String: TOCEntry] = [:]
        for entry in toc where tocByPath[entry.path] == nil {
            tocByPath[entry.path] = entry
        }

        // Spine (reading order). Non-document itemrefs are skipped, matching
        // the chapter indexing used by saved locations and highlights.
        let itemRefs = package.firstDescendant("spine")?.children("itemref").compactMap { $0.attribute("idref") } ?? []
        spine = itemRefs.compactMap { idref -> SpineItem? in
            guard let item = manifest[idref], item.isReadableDocument else { return nil }
            let title = tocByPath[item.path]?.title
                ?? DocumentMetadata.clean(item.title)
                ?? Self.documentTitle(archive: archive, path: item.path)
                ?? EPUBPath.title(fromHref: item.href)
            return SpineItem(
                id: idref,
                path: item.path,
                title: title,
                tocLevel: tocByPath[item.path]?.level ?? 0,
                locationHref: packageDirectory.isEmpty ? item.href : (packageDirectory as NSString).appendingPathComponent(item.href)
            )
        }
        guard !spine.isEmpty else { throw PackageError.emptySpine }

        coverImagePath = Self.coverPath(package: package, manifest: manifest, archive: archive)
    }

    // MARK: - Table of contents

    private static func tableOfContents(
        archive: ZipArchive,
        package: MarkupNode,
        manifest: [String: ManifestItem]
    ) -> [TOCEntry] {
        if let nav = manifest.values.first(where: { $0.properties?.split(separator: " ").contains("nav") == true }),
           let navData = try? archive.data(for: nav.path),
           let navDocument = MarkupNode.parse(navData) {
            let entries = navigationEntries(in: navDocument, basePath: nav.path)
            if !entries.isEmpty { return entries }
        }

        let ncxID = package.firstDescendant("spine")?.attribute("toc")
        let ncx = ncxID.flatMap { manifest[$0] }
            ?? manifest.values.first { $0.mediaType == "application/x-dtbncx+xml" || $0.href.lowercased().hasSuffix(".ncx") }
        if let ncx, let ncxData = try? archive.data(for: ncx.path), let ncxDocument = MarkupNode.parse(ncxData) {
            var entries: [TOCEntry] = []
            for point in ncxDocument.firstDescendant("navMap")?.children("navPoint") ?? [] {
                collectNavPoints(point, basePath: ncx.path, level: 0, into: &entries)
            }
            return entries
        }
        return []
    }

    private static func navigationEntries(in document: MarkupNode, basePath: String) -> [TOCEntry] {
        let navs = document.descendants("nav")
        let tocNav = navs.first { ($0.attribute("type") ?? "").split(separator: " ").contains("toc") }
            ?? navs.first
        guard let list = tocNav?.child("ol") ?? tocNav?.firstDescendant("ol") else { return [] }
        var entries: [TOCEntry] = []
        collectListItems(list, basePath: basePath, level: 0, into: &entries)
        return entries
    }

    private static func collectListItems(_ list: MarkupNode, basePath: String, level: Int, into entries: inout [TOCEntry]) {
        for item in list.children("li") {
            if let anchor = item.child("a") ?? item.firstDescendant("a"),
               let href = anchor.attribute("href") {
                let title = cleanTitle(anchor.textContent)
                if !title.isEmpty {
                    let (path, fragment) = EPUBPath.split(href, relativeTo: EPUBPath.directory(of: basePath))
                    entries.append(TOCEntry(title: title, path: path, fragment: fragment, level: level))
                }
            }
            if let nested = item.child("ol") {
                collectListItems(nested, basePath: basePath, level: level + 1, into: &entries)
            }
        }
    }

    private static func collectNavPoints(_ point: MarkupNode, basePath: String, level: Int, into entries: inout [TOCEntry]) {
        if let src = point.child("content")?.attribute("src") {
            let title = cleanTitle(point.child("navLabel")?.child("text")?.textContent ?? "")
            if !title.isEmpty {
                let (path, fragment) = EPUBPath.split(src, relativeTo: EPUBPath.directory(of: basePath))
                entries.append(TOCEntry(title: title, path: path, fragment: fragment, level: level))
            }
        }
        for child in point.children("navPoint") {
            collectNavPoints(child, basePath: basePath, level: level + 1, into: &entries)
        }
    }

    private static func documentTitle(archive: ZipArchive, path: String) -> String? {
        guard let raw = archive.string(for: path) else { return nil }
        let pattern = #"<h[1-3]\b[^>]*>([\s\S]*?)</h[1-3]>|<title\b[^>]*>([\s\S]*?)</title>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = raw as NSString
        guard let match = regex.firstMatch(in: raw, range: NSRange(location: 0, length: ns.length)) else { return nil }
        for group in 1...2 where match.range(at: group).location != NSNotFound {
            let title = cleanTitle(ns.substring(with: match.range(at: group)))
            if !title.isEmpty { return title }
        }
        return nil
    }

    static func cleanTitle(_ raw: String) -> String {
        HTMLText.plainText(from: raw).replacingOccurrences(of: "\n", with: " ")
    }

    // MARK: - Cover

    private static func coverPath(package: MarkupNode, manifest: [String: ManifestItem], archive: ZipArchive) -> String? {
        let images = manifest.values.filter(\.isImage)

        if let item = images.first(where: { $0.properties?.split(separator: " ").contains("cover-image") == true }) {
            return item.path
        }
        if let coverID = package.descendants("meta").first(where: { $0.attribute("name") == "cover" })?.attribute("content"),
           let item = manifest[coverID], item.isImage {
            return item.path
        }
        if let item = images.first(where: { $0.id.lowercased() == "cover" || $0.id.lowercased() == "cover-image" }) {
            return item.path
        }
        let namePattern = #"(cover|front|title|ttlpg|[_-]cv[ti]?)[^/]*\.(jpe?g|png|webp)$"#
        if let item = images
            .filter({ $0.href.range(of: namePattern, options: [.regularExpression, .caseInsensitive]) != nil })
            .sorted(by: { $0.href < $1.href })
            .first {
            return item.path
        }
        return nil
    }
}

/// Path arithmetic for paths inside an EPUB archive.
enum EPUBPath {
    static func directory(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<slash])
    }

    /// Resolves an href against a directory, percent-decoding and collapsing
    /// `.` and `..` segments. Fragments and queries are dropped.
    static func resolve(_ href: String, relativeTo directory: String) -> String {
        split(href, relativeTo: directory).path
    }

    static func split(_ href: String, relativeTo directory: String) -> (path: String, fragment: String?) {
        let parts = href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let rawPath = String(parts.first ?? "").split(separator: "?", maxSplits: 1).first.map(String.init) ?? ""
        let fragment = parts.count > 1 ? String(parts[1]) : nil
        let decoded = rawPath.removingPercentEncoding ?? rawPath
        let combined: String
        if decoded.isEmpty {
            combined = directory
        } else if decoded.hasPrefix("/") {
            combined = String(decoded.dropFirst())
        } else {
            combined = directory.isEmpty ? decoded : directory + "/" + decoded
        }
        var stack: [Substring] = []
        for segment in combined.split(separator: "/") {
            switch segment {
            case ".": continue
            case "..": _ = stack.popLast()
            default: stack.append(segment)
            }
        }
        return (stack.joined(separator: "/"), fragment)
    }

    static func title(fromHref href: String) -> String {
        let raw = (href.removingPercentEncoding ?? href).split(separator: "/").last.map(String.init) ?? href
        return raw
            .replacingOccurrences(of: #"\.x?html?$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
