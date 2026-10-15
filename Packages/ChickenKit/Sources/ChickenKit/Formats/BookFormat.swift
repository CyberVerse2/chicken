import Foundation
import UniformTypeIdentifiers

public enum BookFormat: String, Codable, CaseIterable, Hashable, Sendable {
    case pdf
    case epub
    case text
    case document
    case unknown

    public init(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "pdf": self = .pdf
        case "epub": self = .epub
        case "txt", "text", "md", "markdown", "rtf": self = .text
        case "doc", "docx": self = .document
        default: self = .unknown
        }
    }

    /// Extensions Chicken can actually open in a reader. Formats such as DOCX
    /// or MOBI are recognised but deliberately not imported, because the
    /// reader would show them as unreadable bytes.
    public static let importableExtensions: Set<String> = ["pdf", "epub", "txt", "text", "md", "markdown", "rtf"]

    public static var importableContentTypes: [UTType] {
        var types: [UTType] = [.pdf, .epub, .plainText, .rtf]
        if let markdown = UTType(filenameExtension: "md") { types.append(markdown) }
        return types
    }

    public var label: String {
        switch self {
        case .pdf: return "PDF"
        case .epub: return "EPUB"
        case .text: return "Text"
        case .document: return "Document"
        case .unknown: return "File"
        }
    }

    public var systemImage: String {
        switch self {
        case .pdf: return "doc.richtext"
        case .epub: return "text.book.closed"
        case .text: return "doc.plaintext"
        case .document: return "doc.text"
        case .unknown: return "doc"
        }
    }

    /// Whether the reader offers scroll / pages / spread flow controls.
    public var supportsFlowModes: Bool { self == .pdf || self == .epub }
}

public struct DocumentMetadata: Sendable, Hashable {
    public var title: String?
    public var author: String?
    public var pageCount: Int?
    public var publisher: String?
    public var language: String?
    public var summary: String?

    public init(
        title: String? = nil,
        author: String? = nil,
        pageCount: Int? = nil,
        publisher: String? = nil,
        language: String? = nil,
        summary: String? = nil
    ) {
        self.title = title
        self.author = author
        self.pageCount = pageCount
        self.publisher = publisher
        self.language = language
        self.summary = summary
    }

    public static let empty = DocumentMetadata()

    public var isEmpty: Bool {
        title == nil && author == nil && pageCount == nil && publisher == nil && language == nil && summary == nil
    }

    public func mergingFallbacks(from fallback: DocumentMetadata?) -> DocumentMetadata {
        guard let fallback else { return self }
        return DocumentMetadata(
            title: title ?? fallback.title,
            author: author ?? fallback.author,
            pageCount: pageCount ?? fallback.pageCount,
            publisher: publisher ?? fallback.publisher,
            language: language ?? fallback.language,
            summary: summary ?? fallback.summary
        )
    }

    static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

public enum DocumentMetadataReader {
    public static func metadata(for url: URL, format: BookFormat) -> DocumentMetadata {
        switch format {
        case .pdf:
            return PDFMetadataReader.metadata(for: url)
        case .epub:
            guard let archive = try? ZipArchive(url: url), let package = try? EPUBPackage(archive: archive) else {
                return .empty
            }
            return package.metadata
        case .text, .document, .unknown:
            return .empty
        }
    }

    /// Title derived from a file name, used when a document carries no metadata.
    public static func title(fromFileName url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
