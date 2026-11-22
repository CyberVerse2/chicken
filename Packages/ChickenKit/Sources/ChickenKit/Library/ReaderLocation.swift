import Foundation

public protocol ReaderLocationCodable: Codable, Hashable, Sendable {
    static var typeTag: String { get }
    var type: String { get }
}

extension ReaderLocationCodable {
    public var encoded: String? { ReaderLocationCoding.encode(self) }

    public static func decode(_ value: String?) -> Self? {
        ReaderLocationCoding.decode(value).flatMap { $0.type == Self.typeTag ? $0 : nil }
    }
}

/// Saved EPUB position. The JSON shape is unchanged from earlier versions of
/// Chicken so stored `lastLocation` strings keep resolving.
public struct EPUBLocation: ReaderLocationCodable {
    public static let typeTag = "epub"
    public let type: String
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
        self.type = Self.typeTag
        self.href = href
        self.spineIndex = spineIndex
        self.progression = progression
        self.globalProgression = globalProgression
        self.pageNumber = pageNumber
        self.pageWithinSpine = pageWithinSpine
    }
}

public struct PDFLocation: ReaderLocationCodable {
    public static let typeTag = "pdf"
    public let type: String
    public let pageIndex: Int
    public let chapterIndex: Int

    public init(pageIndex: Int, chapterIndex: Int) {
        self.type = Self.typeTag
        self.pageIndex = pageIndex
        self.chapterIndex = chapterIndex
    }
}

/// Position within a plain text document.
public struct TextLocation: ReaderLocationCodable {
    public static let typeTag = "text"
    public let type: String
    public let progression: Double

    public init(progression: Double) {
        self.type = Self.typeTag
        self.progression = progression
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
    public var darkModePDF: Bool?

    public init(
        theme: String,
        fontSize: Double,
        lineHeight: Double,
        columnWidth: Double,
        readingMode: String,
        zenMode: Bool,
        typeface: String? = nil,
        darkModePDF: Bool? = nil
    ) {
        self.theme = theme
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self.columnWidth = columnWidth
        self.readingMode = readingMode
        self.zenMode = zenMode
        self.typeface = typeface
        self.darkModePDF = darkModePDF
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
