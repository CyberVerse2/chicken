import Foundation

/// A candidate file found in a folder the user has shared with Chicken.
public struct DiscoveredBook: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let title: String
    public let format: BookFormat
    public let sourceFolder: String
    public let fileSize: Int64
    public let metadata: DocumentMetadata
    public let score: Int

    public var isLikelyBook: Bool { score >= 45 }

    public var classification: String {
        if score >= 70 { return "Very likely a book" }
        if score >= 45 { return "Likely a book" }
        if score >= 25 { return "Needs review" }
        return "Probably not a book"
    }

    public func enriched() -> DiscoveredBook {
        let metadata = DocumentMetadataReader.metadata(for: url, format: format)
        guard !metadata.isEmpty else { return self }
        return DiscoveredBook(
            url: url,
            title: metadata.title ?? title,
            format: format,
            sourceFolder: sourceFolder,
            fileSize: fileSize,
            metadata: metadata,
            score: BookDiscovery.score(url: url, format: format, fileSize: fileSize, metadata: metadata)
        )
    }
}

public enum BookDiscovery {
    public struct Progress: Sendable {
        public let checked: Int
        public let found: Int
        public let currentFolder: String
    }

    private static let skippedFolderNames: Set<String> = [
        "Library", "Applications", "System", "Developer", "node_modules", ".git",
        "DerivedData", "Build", "Caches", "Containers", "Group Containers", ".Trash",
    ]

    /// Walks each root (already security-scope accessed by the caller) for
    /// importable files, skipping names in `excludingFileNames`. Results are
    /// sorted likely-books first.
    public static func scan(
        roots: [URL],
        excludingFileNames: Set<String>,
        progress: @Sendable (Progress) -> Void
    ) -> [DiscoveredBook] {
        let fileManager = FileManager.default
        var checked = 0
        var found: [DiscoveredBook] = []
        var seen = Set<String>()

        for root in roots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [.skipsPackageDescendants, .skipsHiddenFiles]
            ) else { continue }

            for case let url as URL in enumerator {
                if Task.isCancelled { return sort(found) }
                checked += 1
                if checked % 200 == 0 {
                    progress(Progress(checked: checked, found: found.count, currentFolder: url.deletingLastPathComponent().lastPathComponent))
                }

                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                if values?.isDirectory == true {
                    if skippedFolderNames.contains(url.lastPathComponent) { enumerator.skipDescendants() }
                    continue
                }

                let fileExtension = url.pathExtension.lowercased()
                guard BookFormat.importableExtensions.contains(fileExtension),
                      !excludingFileNames.contains(url.lastPathComponent),
                      seen.insert(url.standardizedFileURL.path).inserted
                else { continue }

                let format = BookFormat(fileExtension: fileExtension)
                let fileSize = Int64(values?.fileSize ?? 0)
                found.append(
                    DiscoveredBook(
                        url: url,
                        title: DocumentMetadataReader.title(fromFileName: url),
                        format: format,
                        sourceFolder: url.deletingLastPathComponent().path,
                        fileSize: fileSize,
                        metadata: .empty,
                        score: score(url: url, format: format, fileSize: fileSize, metadata: .empty)
                    )
                )
            }
        }

        progress(Progress(checked: checked, found: found.count, currentFolder: ""))
        return sort(found)
    }

    public static func sort(_ books: [DiscoveredBook]) -> [DiscoveredBook] {
        books.sorted {
            if $0.isLikelyBook != $1.isLikelyBook { return $0.isLikelyBook }
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    /// Heuristic 0–100 "is this a book?" score. EPUBs are almost always books;
    /// PDFs need supporting signals (page count, metadata, size, path).
    public static func score(url: URL, format: BookFormat, fileSize: Int64, metadata: DocumentMetadata) -> Int {
        var score = 0
        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        let path = url.path.lowercased()

        switch format {
        case .epub: score += 95
        case .pdf: score += 34
        case .text: score += 20
        case .document: score += 10
        case .unknown: break
        }

        if let pageCount = metadata.pageCount {
            if pageCount >= 80 { score += 45 }
            else if pageCount >= 35 { score += 28 }
            else if pageCount >= 15 { score += 12 }
            else { score -= 35 }
        }

        if metadata.author != nil { score += 18 }
        if metadata.title != nil { score += 12 }
        if metadata.publisher != nil { score += 6 }
        if metadata.language != nil { score += 4 }
        if fileSize > 2_000_000 { score += 12 }
        else if fileSize > 800_000 { score += 8 }
        if fileSize < 120_000 { score -= 20 }

        let positiveSignals = ["book", "ebook", "library", "novel", "edition", "press", "volume"]
        if positiveSignals.contains(where: path.contains) { score += 18 }

        let negativeSignals = [
            "invoice", "receipt", "ticket", "boarding", "statement", "contract",
            "form", "slides", "deck", "pitch", "overview", "resume", "cv",
            "certificate", "assignment", "lecture", "report", "bank", "travel",
        ]
        if negativeSignals.contains(where: { name.contains($0) || path.contains("/\($0)") }) {
            score -= 45
        }

        return min(max(score, 0), 100)
    }
}
