import Foundation

/// Saved EPUB position. The JSON shape is unchanged from earlier versions of
/// Chicken so stored `lastLocation` strings keep resolving.
public struct EPUBLocation: Codable, Hashable, Sendable {
    public var type: String = "epub"
    public let href: String
    public let spineIndex: Int
    /// Progress within the spine document, 0...1.
    public let progression: Double
    /// Progress through the whole book, 0...1.
    public let globalProgression: Double
    /// 1-indexed page when the location was captured. Restore prefers this and
    /// falls back to spine + progression if pagination has since changed.
    public let pageNumber: Int?
    public let pageWithinSpine: Int?

    public init(
        href: String,
        spineIndex: Int,
        progression: Double,
        globalProgression: Double,
        pageNumber: Int? = nil,
        pageWithinSpine: Int? = nil
    ) {
        self.href = href
        self.spineIndex = spineIndex
        self.progression = progression
        self.globalProgression = globalProgression
        self.pageNumber = pageNumber
        self.pageWithinSpine = pageWithinSpine
    }

    public var encoded: String? { ReaderLocationCoding.encode(self) }

    public static func decode(_ value: String?) -> EPUBLocation? {
        ReaderLocationCoding.decode(value).flatMap { $0.type == "epub" ? $0 : nil }
    }
}

public struct PDFLocation: Codable, Hashable, Sendable {
    public var type: String = "pdf"
    public let pageIndex: Int
    public let chapterIndex: Int

    public init(pageIndex: Int, chapterIndex: Int) {
        self.pageIndex = pageIndex
        self.chapterIndex = chapterIndex
    }

    public var encoded: String? { ReaderLocationCoding.encode(self) }

    public static func decode(_ value: String?) -> PDFLocation? {
        ReaderLocationCoding.decode(value).flatMap { $0.type == "pdf" ? $0 : nil }
    }
}

/// Position within a plain text document.
public struct TextLocation: Codable, Hashable, Sendable {
    public var type: String = "text"
    public let progression: Double

    public init(progression: Double) {
        self.progression = progression
    }

    public var encoded: String? { ReaderLocationCoding.encode(self) }

    public static func decode(_ value: String?) -> TextLocation? {
        ReaderLocationCoding.decode(value).flatMap { $0.type == "text" ? $0 : nil }
    }
}

enum ReaderLocationCoding {
    static func encode<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode<T: Decodable>(_ value: String?) -> T? {
        guard let data = value?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

/// Per-book typography and flow settings.
public struct ReaderPreferences: Codable, Hashable, Sendable {
    public var theme: String
    public var fontSize: Double
    public var lineHeight: Double
    public var columnWidth: Double
    public var readingMode: String
    public var zenMode: Bool
    /// Body typeface for reflowable books; nil means the default. Optional
    /// so preferences saved before it existed still decode.
    public var typeface: String?

    public init(theme: String, fontSize: Double, lineHeight: Double, columnWidth: Double, readingMode: String, zenMode: Bool, typeface: String? = nil) {
        self.theme = theme
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self.columnWidth = columnWidth
        self.readingMode = readingMode
        self.zenMode = zenMode
        self.typeface = typeface
    }

    public static let fontSizeRange: ClosedRange<Double> = 13...28
    public static let lineHeightRange: ClosedRange<Double> = 1.4...2.2
    public static let columnWidthRange: ClosedRange<Double> = 480...820

    public static let `default` = ReaderPreferences(
        theme: "paper",
        fontSize: 17,
        lineHeight: 1.78,
        columnWidth: 620,
        readingMode: "scroll",
        zenMode: false
    )
}
