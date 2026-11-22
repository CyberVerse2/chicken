import Foundation

public struct SharedThemeTokens: Equatable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let isDark: Bool
    public let backgroundHex: UInt32
    public let surfaceHex: UInt32
    public let surfaceAltHex: UInt32
    public let textHex: UInt32
    public let mutedHex: UInt32
    public let faintHex: UInt32
    public let inkHex: UInt32
    public let ribbonHex: UInt32
    public let borderOpacity: Double
    public let borderStrongOpacity: Double
    public let shadowOpacity: Double
    public let shadowIsBlack: Bool

    public init(
        id: String,
        label: String,
        isDark: Bool,
        backgroundHex: UInt32,
        surfaceHex: UInt32,
        surfaceAltHex: UInt32,
        textHex: UInt32,
        mutedHex: UInt32,
        faintHex: UInt32,
        inkHex: UInt32,
        ribbonHex: UInt32,
        borderOpacity: Double,
        borderStrongOpacity: Double,
        shadowOpacity: Double,
        shadowIsBlack: Bool = false
    ) {
        self.id = id
        self.label = label
        self.isDark = isDark
        self.backgroundHex = backgroundHex
        self.surfaceHex = surfaceHex
        self.surfaceAltHex = surfaceAltHex
        self.textHex = textHex
        self.mutedHex = mutedHex
        self.faintHex = faintHex
        self.inkHex = inkHex
        self.ribbonHex = ribbonHex
        self.borderOpacity = borderOpacity
        self.borderStrongOpacity = borderStrongOpacity
        self.shadowOpacity = shadowOpacity
        self.shadowIsBlack = shadowIsBlack
    }

    public static let paper = SharedThemeTokens(
        id: "paper",
        label: "Paper",
        isDark: false,
        backgroundHex: 0xF4EEE4,
        surfaceHex: 0xFBF8F2,
        surfaceAltHex: 0xEAE2D5,
        textHex: 0x211D1C,
        mutedHex: 0x6E6259,
        faintHex: 0xA89C90,
        inkHex: 0x211D1C,
        ribbonHex: 0xB57631,
        borderOpacity: 0.10,
        borderStrongOpacity: 0.20,
        shadowOpacity: 0.10
    )

    public static let sepia = SharedThemeTokens(
        id: "sepia",
        label: "Sepia",
        isDark: false,
        backgroundHex: 0xEEDFC4,
        surfaceHex: 0xF6EBD6,
        surfaceAltHex: 0xE3D1B0,
        textHex: 0x3B2A1A,
        mutedHex: 0x77593C,
        faintHex: 0xA68B6A,
        inkHex: 0x3B2A1A,
        ribbonHex: 0xA9642A,
        borderOpacity: 0.14,
        borderStrongOpacity: 0.24,
        shadowOpacity: 0.12
    )

    public static let ink = SharedThemeTokens(
        id: "ink",
        label: "Ink",
        isDark: true,
        backgroundHex: 0x141211,
        surfaceHex: 0x1E1B19,
        surfaceAltHex: 0x292522,
        textHex: 0xF2E8DA,
        mutedHex: 0xA69A8D,
        faintHex: 0x6E645A,
        inkHex: 0xF2E8DA,
        ribbonHex: 0xD49345,
        borderOpacity: 0.10,
        borderStrongOpacity: 0.18,
        shadowOpacity: 0.50,
        shadowIsBlack: true
    )

    public static func forName(_ name: String?) -> SharedThemeTokens {
        switch name {
        case "sepia": .sepia
        case "ink": .ink
        default: .paper
        }
    }
}

public struct SharedCoverCloth: Equatable, Hashable, Sendable {
    public enum Layout: String, Sendable, Hashable {
        case editorial
        case framed
        case banded
    }

    public let clothHex: UInt32
    public let inkHex: UInt32
    public let accentHex: UInt32
    public let layout: Layout

    public static let all: [SharedCoverCloth] = [
        SharedCoverCloth(clothHex: 0x22201E, inkHex: 0xF2E7D8, accentHex: 0xD49243, layout: .editorial),
        SharedCoverCloth(clothHex: 0x2B3A42, inkHex: 0xE8DFCE, accentHex: 0xC89552, layout: .framed),
        SharedCoverCloth(clothHex: 0x3D4A3A, inkHex: 0xEAE2CF, accentHex: 0xC9985A, layout: .editorial),
        SharedCoverCloth(clothHex: 0x6B2D28, inkHex: 0xF3E2CC, accentHex: 0xD9A462, layout: .banded),
        SharedCoverCloth(clothHex: 0x6E533B, inkHex: 0xF5EBDC, accentHex: 0xDDA864, layout: .framed),
        SharedCoverCloth(clothHex: 0x944B2D, inkHex: 0xF6E8D6, accentHex: 0xE5BC86, layout: .editorial),
        SharedCoverCloth(clothHex: 0xC28A3F, inkHex: 0x201912, accentHex: 0x3B2D1E, layout: .banded),
        SharedCoverCloth(clothHex: 0xDDD3C2, inkHex: 0x211D1A, accentHex: 0x9E5E24, layout: .framed),
    ]

    public static func preset(for index: Int) -> SharedCoverCloth {
        all[((index % all.count) + all.count) % all.count]
    }

    public static func preset(forTitle title: String) -> SharedCoverCloth {
        preset(for: Int(title.stableChickenHash % UInt64(all.count)))
    }
}
