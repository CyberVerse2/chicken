import Foundation

public enum CoverOrigin: String, Codable, Sendable, Hashable, CaseIterable {
    case none
    case pdfFirstPage
    case embedded
    case catalog
    case custom

    public var priority: Int {
        switch self {
        case .none: 0
        case .pdfFirstPage: 1
        case .embedded: 2
        case .catalog: 3
        case .custom: 4
        }
    }

    public func canBeReplacedAutomatically(by incoming: CoverOrigin) -> Bool {
        guard self != .custom else { return false }
        return incoming.priority >= priority
    }

    public var isTrustedArtwork: Bool {
        switch self {
        case .embedded, .catalog, .custom: true
        case .none, .pdfFirstPage: false
        }
    }
}

public struct CoverColor: Codable, Sendable, Hashable {
    public let hue: Double
    public let saturation: Double
    public let brightness: Double
    public let hex: UInt32

    public var isDark: Bool { brightness < 0.45 }

    public init(red: Double, green: Double, blue: Double) {
        let r = min(max(red, 0), 1)
        let g = min(max(green, 0), 1)
        let b = min(max(blue, 0), 1)

        let high = max(r, g, b)
        let low = min(r, g, b)
        let delta = high - low

        self.brightness = high
        self.saturation = high > 0 ? delta / high : 0
        if delta > 0 {
            var value: Double
            if high == r {
                value = (g - b) / delta
            } else if high == g {
                value = (b - r) / delta + 2
            } else {
                value = (r - g) / delta + 4
            }
            value /= 6
            self.hue = value < 0 ? value + 1 : value
        } else {
            self.hue = 0
        }

        let ri = UInt32((r * 255).rounded()) & 0xFF
        let gi = UInt32((g * 255).rounded()) & 0xFF
        let bi = UInt32((b * 255).rounded()) & 0xFF
        self.hex = (ri << 16) | (gi << 8) | bi
    }

    public init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}

public struct CoverMetrics: Codable, Sendable, Hashable {
    public static let defaultAspectRatio: Double = 2.0 / 3.0
    public static let shelfAspectRange: ClosedRange<Double> = 0.58...0.86
    public static let maxAcceptedAspectRatio: Double = 1.05

    public let pixelWidth: Int
    public let pixelHeight: Int
    public let aspectRatio: Double
    public let dominantColor: CoverColor
    public let hasLegibleText: Bool?

    public init(
        pixelWidth: Int,
        pixelHeight: Int,
        dominantColor: CoverColor,
        hasLegibleText: Bool? = nil
    ) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.aspectRatio = Double(pixelWidth) / Double(max(pixelHeight, 1))
        self.dominantColor = dominantColor
        self.hasLegibleText = hasLegibleText
    }

    public static func clampedAspectRatio(_ ratio: Double?) -> Double {
        guard let ratio, ratio.isFinite, ratio > 0, ratio <= maxAcceptedAspectRatio else {
            return defaultAspectRatio
        }
        return min(max(ratio, shelfAspectRange.lowerBound), shelfAspectRange.upperBound)
    }
}

public struct RenderedCover: Sendable, Hashable {
    public let fileName: String
    public let origin: CoverOrigin
    public let metrics: CoverMetrics
    public let previewData: Data?

    public init(
        fileName: String,
        origin: CoverOrigin,
        metrics: CoverMetrics,
        previewData: Data?
    ) {
        self.fileName = fileName
        self.origin = origin
        self.metrics = metrics
        self.previewData = previewData
    }
}
