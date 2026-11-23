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
    public var isbn: String?

    public init(
        title: String? = nil,
        author: String? = nil,
        pageCount: Int? = nil,
        publisher: String? = nil,
        language: String? = nil,
        summary: String? = nil,
        isbn: String? = nil
    ) {
        self.title = title
        self.author = author
        self.pageCount = pageCount
        self.publisher = publisher
        self.language = language
        self.summary = summary
        self.isbn = isbn
    }

    public static let empty = DocumentMetadata()

    public var isEmpty: Bool {
        title == nil && author == nil && pageCount == nil && publisher == nil && language == nil && summary == nil && isbn == nil
    }

    public func mergingFallbacks(from fallback: DocumentMetadata?) -> DocumentMetadata {
        guard let fallback else { return self }
        return DocumentMetadata(
            title: title ?? fallback.title,
            author: author ?? fallback.author,
            pageCount: pageCount ?? fallback.pageCount,
            publisher: publisher ?? fallback.publisher,
            language: language ?? fallback.language,
            summary: summary ?? fallback.summary,
            isbn: isbn ?? fallback.isbn
        )
    }

    static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

public enum ISBNExtractor {
    public static func normalize(_ raw: String) -> String? {
        var working = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = working.lowercased()
        if lower.hasPrefix("urn:isbn:") {
            working = String(working.dropFirst(9))
        } else if lower.hasPrefix("isbn:") {
            working = String(working.dropFirst(5))
        }
        working = working.trimmingCharacters(in: .whitespacesAndNewlines)
        var cleaned = ""
        cleaned.reserveCapacity(13)
        for ch in working {
            if ch == "-" || ch == " " || ch == "\u{00A0}" || ch == "\u{2013}" || ch == "\u{2014}" {
                continue
            }
            if ch.isASCII && ch.isNumber {
                cleaned.append(ch)
            } else if ch == "x" || ch == "X" {
                cleaned.append("X")
            } else {
                return nil
            }
        }
        if cleaned.count == 13 && isValidISBN13(cleaned) {
            return cleaned
        }
        if cleaned.count == 10 && isValidISBN10(cleaned) {
            return cleaned
        }
        return nil
    }

    public static func extract(from text: String) -> String? {
        guard !text.isEmpty else { return nil }
        var firstISBN10: String?
        let bytes = Array(text.utf8)
        let count = bytes.count
        var i = 0
        while i < count {
            let b = bytes[i]
            if b >= 0x30 && b <= 0x39 {
                let prevIsAlnum: Bool
                if i > 0 {
                    let p = bytes[i - 1]
                    prevIsAlnum = (p >= 0x30 && p <= 0x39) || (p >= 0x41 && p <= 0x5A) || (p >= 0x61 && p <= 0x7A)
                } else {
                    prevIsAlnum = false
                }
                if !prevIsAlnum {
                    var candidate = String()
                    var digitCount = 0
                    var j = i
                    var aborted = false
                    while j < count && candidate.count < 14 {
                        let c = bytes[j]
                        if c >= 0x30 && c <= 0x39 {
                            candidate.append(Character(UnicodeScalar(c)))
                            digitCount += 1
                            j += 1
                        } else if (c == 0x58 || c == 0x78) && digitCount == 9 {
                            candidate.append("X")
                            digitCount += 1
                            j += 1
                            break
                        } else if c == 0x2D || c == 0x20 {
                            j += 1
                        } else {
                            break
                        }
                        if digitCount == 13 {
                            break
                        }
                    }
                    if j < count {
                        let nxt = bytes[j]
                        if (nxt >= 0x30 && nxt <= 0x39) || (nxt >= 0x41 && nxt <= 0x5A) || (nxt >= 0x61 && nxt <= 0x7A) {
                            aborted = true
                        }
                    }
                    if !aborted && (candidate.count == 13 || candidate.count == 10) {
                        if candidate.count == 13 && isValidISBN13(candidate) {
                            return candidate
                        }
                        if candidate.count == 10 && firstISBN10 == nil && isValidISBN10(candidate) {
                            firstISBN10 = candidate
                        }
                    }
                }
                while i < count {
                    let c = bytes[i]
                    if (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) {
                        i += 1
                    } else {
                        break
                    }
                }
            } else {
                i += 1
            }
        }
        return firstISBN10
    }

    private static func isValidISBN13(_ digits: String) -> Bool {
        guard digits.count == 13, digits.hasPrefix("978") || digits.hasPrefix("979") else { return false }
        var sum = 0
        for (idx, ch) in digits.enumerated() {
            guard let val = ch.wholeNumberValue else { return false }
            sum += (idx % 2 == 0) ? val : val * 3
        }
        return sum % 10 == 0
    }

    private static func isValidISBN10(_ chars: String) -> Bool {
        guard chars.count == 10 else { return false }
        var sum = 0
        for (idx, ch) in chars.enumerated() {
            let val: Int
            if idx == 9 && ch == "X" {
                val = 10
            } else if let n = ch.wholeNumberValue {
                val = n
            } else {
                return false
            }
            sum += (10 - idx) * val
        }
        return sum % 11 == 0
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
