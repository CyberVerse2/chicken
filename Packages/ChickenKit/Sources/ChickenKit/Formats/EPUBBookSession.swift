import Dispatch
import Foundation
import Synchronization

public final class EPUBBookSession: Sendable {
    public struct PreparedChapter: Sendable {
        public let index: Int
        public let stylesHTML: String
        public let bodyHTML: String
        public let byteWeight: Int

        public func jsonData() -> Data {
            let payload = ChapterPayload(
                index: index,
                styles: stylesHTML,
                body: bodyHTML,
                weight: byteWeight
            )
            return (try? JSONEncoder().encode(payload)) ?? Data("{}".utf8)
        }
    }

    public struct SearchMatch: Sendable, Hashable {
        public let spineIndex: Int
        public let occurrenceInSpine: Int
        public let snippet: String
    }

    private struct ChapterPayload: Encodable {
        let index: Int
        let styles: String
        let body: String
        let weight: Int
    }

    private struct CacheState {
        var chapters: [Int: PreparedChapter] = [:]
        var chapterLRU: [Int] = []
        var smallResources: [String: (Data, String)] = [:]
        var smallResourceLRU: [String] = []
        var plainTexts: [Int: String] = [:]
    }

    private struct PackageCacheEntry: Sendable {
        let fingerprint: String
        let package: EPUBPackage
    }

    private struct PackageCacheState: Sendable {
        var entries: [String: PackageCacheEntry] = [:]
        var lru: [String] = []
    }

    private static let packageCache = Mutex(PackageCacheState())

    public let bookID: UUID
    public let archive: ZipArchive
    public let package: EPUBPackage
    public let spineWeights: [Int]
    public let cumulativeWeights: [Int]
    public let totalWeight: Int

    private let spineIndexByPath: [String: Int]
    private let mimeByPath: [String: String]
    private let cache = Mutex(CacheState())

    public init(bookAt url: URL, bookID: UUID = UUID()) throws {
        self.bookID = bookID
        let archive = try ZipArchive(url: url)
        let rv = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let cacheKey = url.path
        let fingerprint = "\(rv?.fileSize ?? 0)|\(rv?.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(archive.entries.count)"
        let package: EPUBPackage
        if let cached = Self.packageCache.withLock({ state -> EPUBPackage? in
            guard let entry = state.entries[cacheKey], entry.fingerprint == fingerprint else {
                return nil
            }
            return entry.package
        }) {
            package = cached
        } else {
            let parsed = try EPUBPackage(archive: archive)
            Self.packageCache.withLock { state in
                state.entries[cacheKey] = PackageCacheEntry(fingerprint: fingerprint, package: parsed)
                state.lru.removeAll { $0 == cacheKey }
                state.lru.append(cacheKey)
                if state.lru.count > 64 {
                    let evicted = state.lru.removeFirst()
                    state.entries.removeValue(forKey: evicted)
                }
            }
            package = parsed
        }
        self.archive = archive
        self.package = package

        var spineMap: [String: Int] = [:]
        var weights: [Int] = []
        weights.reserveCapacity(package.spine.count)
        var cumulative: [Int] = [0]
        cumulative.reserveCapacity(package.spine.count + 1)
        var running = 0

        for (index, item) in package.spine.enumerated() {
            if spineMap[item.path] == nil {
                spineMap[item.path] = index
            }
            let rawWeight = archive.entryBytesCount(for: item.path) ?? 512
            let weight = max(512, rawWeight)
            weights.append(weight)
            running += weight
            cumulative.append(running)
        }

        self.spineIndexByPath = spineMap
        self.spineWeights = weights
        self.cumulativeWeights = cumulative
        self.totalWeight = max(1, running)

        var mimes: [String: String] = [:]
        mimes.reserveCapacity(package.manifest.count)
        for item in package.manifest.values {
            if let mediaType = item.mediaType, !mediaType.isEmpty {
                mimes[item.path] = mediaType
            }
        }
        self.mimeByPath = mimes
    }

    public func globalProgress(spineIndex: Int, localProgress: Double) -> Double {
        guard !spineWeights.isEmpty else { return 0 }
        let idx = min(max(spineIndex, 0), spineWeights.count - 1)
        let clampedLocal = min(max(localProgress, 0), 1)
        let start = Double(cumulativeWeights[idx])
        let weight = Double(spineWeights[idx])
        return min(1, max(0, (start + weight * clampedLocal) / Double(totalWeight)))
    }

    public func location(forGlobalProgress progress: Double) -> (spineIndex: Int, localProgress: Double) {
        guard !spineWeights.isEmpty else { return (0, 0) }
        let clamped = min(max(progress, 0), 1)
        let targetByte = clamped * Double(totalWeight)
        var low = 0
        var high = spineWeights.count - 1
        var best = 0
        while low <= high {
            let mid = (low + high) >> 1
            if Double(cumulativeWeights[mid]) <= targetByte {
                best = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        let start = Double(cumulativeWeights[best])
        let weight = Double(spineWeights[best])
        let local = weight > 0 ? min(1, max(0, (targetByte - start) / weight)) : 0
        return (best, local)
    }

    public func chapter(at index: Int) -> PreparedChapter? {
        guard package.spine.indices.contains(index) else { return nil }
        if let cached = cache.withLock({ state -> PreparedChapter? in
            guard let found = state.chapters[index] else { return nil }
            state.chapterLRU.removeAll { $0 == index }
            state.chapterLRU.append(index)
            return found
        }) {
            return cached
        }

        let item = package.spine[index]
        guard let raw = archive.string(for: item.path) else { return nil }
        let directory = EPUBPath.directory(of: item.path)
        let styles = EPUBPublication.stylesheetLinks(in: raw)
            .map {
                EPUBPublication.rewriteResourceURLs(
                    in: $0,
                    directory: directory,
                    spineIndexByPath: spineIndexByPath,
                    injectLazyImages: false
                )
            }
            .joined(separator: "\n")
        let body = EPUBPublication.rewriteResourceURLs(
            in: EPUBPublication.bodyHTML(from: raw),
            directory: directory,
            spineIndexByPath: spineIndexByPath,
            injectLazyImages: true
        )
        let prepared = PreparedChapter(
            index: index,
            stylesHTML: styles,
            bodyHTML: body,
            byteWeight: spineWeights[index]
        )

        cache.withLock { state in
            state.chapters[index] = prepared
            state.chapterLRU.removeAll { $0 == index }
            state.chapterLRU.append(index)
            if state.chapterLRU.count > 8 {
                let evicted = state.chapterLRU.removeFirst()
                state.chapters.removeValue(forKey: evicted)
            }
        }
        return prepared
    }

    public func resourceData(for rawPath: String) -> (data: Data, mimeType: String)? {
        let trimmed = rawPath.hasPrefix("/") ? String(rawPath.dropFirst()) : rawPath
        let decoded = trimmed.removingPercentEncoding ?? trimmed
        let candidates = decoded == trimmed ? [trimmed] : [decoded, trimmed]

        for candidate in candidates {
            if let cached = cache.withLock({ $0.smallResources[candidate] }) {
                return cached
            }
            guard let entry = archive.entry(candidate),
                  let data = try? archive.data(for: entry)
            else { continue }
            let mime = mimeByPath[entry.path] ?? Self.mimeType(forPath: entry.path)
            if data.count <= 256 * 1024 {
                cache.withLock { state in
                    state.smallResources[candidate] = (data, mime)
                    state.smallResourceLRU.removeAll { $0 == candidate }
                    state.smallResourceLRU.append(candidate)
                    if state.smallResourceLRU.count > 64 {
                        let evicted = state.smallResourceLRU.removeFirst()
                        state.smallResources.removeValue(forKey: evicted)
                    }
                }
            }
            return (data, mime)
        }
        return nil
    }

    public func footnoteText(chapterIndex: Int, fragment: String) -> String? {
        guard package.spine.indices.contains(chapterIndex), !fragment.isEmpty else { return nil }
        guard let raw = archive.string(for: package.spine[chapterIndex].path) else { return nil }
        guard let idMatch = findElementRange(withID: fragment, in: raw) else { return nil }
        let text = HTMLText.plainText(from: String(raw[idMatch]))
        guard !text.isEmpty, text.count <= 2400 else { return nil }
        return text
    }

    public func search(_ query: String) -> [SearchMatch] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        let lowerNeedle = needle.lowercased()
        let spineCount = package.spine.count
        guard spineCount > 0 else { return [] }

        let cachedPlainTexts = cache.withLock { $0.plainTexts }
        let collector = Mutex<([SearchMatch], [(Int, String)])>(([], []))

        DispatchQueue.concurrentPerform(iterations: spineCount) { index in
            if Task.isCancelled { return }
            let lowerPlain: String
            var newlyBuilt: (Int, String)?
            if let cached = cachedPlainTexts[index] {
                lowerPlain = cached
            } else if package.spine.indices.contains(index),
                      let raw = archive.string(for: package.spine[index].path) {
                let body = EPUBPublication.bodyHTML(from: raw)
                let built = HTMLText.plainText(from: body).lowercased()
                lowerPlain = built
                newlyBuilt = (index, built)
            } else {
                lowerPlain = ""
            }

            var localMatches: [SearchMatch] = []
            if !lowerPlain.isEmpty {
                var searchStart = lowerPlain.startIndex
                var occurrence = 0
                while let range = lowerPlain.range(of: lowerNeedle, options: .literal, range: searchStart..<lowerPlain.endIndex) {
                    localMatches.append(SearchMatch(spineIndex: index, occurrenceInSpine: occurrence, snippet: ""))
                    occurrence += 1
                    searchStart = range.upperBound
                }
            }

            if !localMatches.isEmpty || newlyBuilt != nil {
                collector.withLock { state in
                    state.0.append(contentsOf: localMatches)
                    if let pair = newlyBuilt {
                        state.1.append(pair)
                    }
                }
            }
        }

        let (unsortedMatches, builtPairs) = collector.withLock { $0 }
        if !builtPairs.isEmpty {
            cache.withLock { state in
                for (idx, text) in builtPairs {
                    state.plainTexts[idx] = text
                }
            }
        }

        return unsortedMatches.sorted {
            if $0.spineIndex != $1.spineIndex { return $0.spineIndex < $1.spineIndex }
            return $0.occurrenceInSpine < $1.occurrenceInSpine
        }
    }

    public func initialDocumentHTML(
        chapterIndex: Int,
        styleCSS: String,
        bootJSON: String
    ) -> String {
        let clampedIndex = package.spine.indices.contains(chapterIndex) ? chapterIndex : 0
        let prepared = chapter(at: clampedIndex) ?? PreparedChapter(index: clampedIndex, stylesHTML: "", bodyHTML: "", byteWeight: 512)
        let language = package.metadata.language.map { value in
            let escaped = value
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            return " lang=\"\(escaped)\""
        } ?? ""
        let safeBoot = bootJSON.replacingOccurrences(of: "</", with: "<\\/")

        return """
        <!doctype html>
        <html\(language)>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
          <base href="chicken-epub://\(bookID.uuidString)/">
          <style>
            .chicken-spine-section { min-height: 60vh; padding-bottom: 3.2rem; margin-bottom: 2.6rem; }
          </style>
          <style id="chicken-reader-style">\(styleCSS)</style>
        </head>
        <body class="chicken-reader-body">
          <main id="chicken-stage">
            <section class="chicken-spine-section" id="chapter-\(clampedIndex)" data-chicken-spine-index="\(clampedIndex)">
              \(prepared.stylesHTML)
              \(prepared.bodyHTML)
            </section>
          </main>
          <script id="chicken-boot" type="application/json">\(safeBoot)</script>
        </body>
        </html>
        """
    }

    private func plainText(forSpine index: Int) -> String {
        if let cached = cache.withLock({ $0.plainTexts[index] }) { return cached }
        guard package.spine.indices.contains(index),
              let raw = archive.string(for: package.spine[index].path)
        else { return "" }
        let body = EPUBPublication.bodyHTML(from: raw)
        let plain = HTMLText.plainText(from: body).lowercased()
        cache.withLock { $0.plainTexts[index] = plain }
        return plain
    }

    private func findElementRange(withID id: String, in html: String) -> Range<String.Index>? {
        for needle in ["id=\"\(id)\"", "id='\(id)'"] {
            if let attrRange = html.range(of: needle) {
                guard let tagStart = html[..<attrRange.lowerBound].lastIndex(of: "<") else { continue }
                let nameStart = html.index(after: tagStart)
                var nameEnd = nameStart
                while nameEnd < html.endIndex && !html[nameEnd].isWhitespace && html[nameEnd] != ">" && html[nameEnd] != "/" {
                    nameEnd = html.index(after: nameEnd)
                }
                let tagName = String(html[nameStart..<nameEnd]).lowercased()
                guard !tagName.isEmpty else { continue }
                let closeTag = "</\(tagName)>"
                if let tagGT = html[attrRange.upperBound...].firstIndex(of: ">") {
                    let afterOpen = html.index(after: tagGT)
                    if let closeRange = html.range(of: closeTag, options: .caseInsensitive, range: afterOpen..<html.endIndex) {
                        return tagStart..<closeRange.upperBound
                    }
                    let fallbackEnd = html.index(afterOpen, offsetBy: min(1600, html.distance(from: afterOpen, to: html.endIndex)))
                    return afterOpen..<fallbackEnd
                }
            }
        }
        return nil
    }

    private static func mimeType(forPath path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "css": return "text/css; charset=utf-8"
        case "js": return "application/javascript; charset=utf-8"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "svg": return "image/svg+xml"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        case "otf": return "font/otf"
        case "xhtml": return "application/xhtml+xml; charset=utf-8"
        case "html", "htm": return "text/html; charset=utf-8"
        case "xml", "ncx", "opf": return "application/xml; charset=utf-8"
        default: return "application/octet-stream"
        }
    }
}
