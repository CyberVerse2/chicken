import ChickenKit
import SwiftUI

// MARK: - Reading themes

enum ReadingTheme: String, Codable, CaseIterable, Hashable, Identifiable {
    case paper
    case sepia
    case ink

    var id: String { rawValue }

    var tokens: SharedThemeTokens {
        switch self {
        case .paper: .paper
        case .sepia: .sepia
        case .ink: .ink
        }
    }

    var label: String { tokens.label }

    var systemImage: String {
        switch self {
        case .paper: "sun.max"
        case .sepia: "book.closed"
        case .ink: "moon"
        }
    }

    var next: ReadingTheme {
        let all = Self.allCases
        return all[((all.firstIndex(of: self) ?? 0) + 1) % all.count]
    }

    var colorScheme: ColorScheme { tokens.isDark ? .dark : .light }

    var palette: ReaderPalette { ReaderPalette(tokens: tokens) }
}

/// Theme colors, kept as hex values so the EPUB stylesheet can use the exact
/// same colors as the SwiftUI chrome.
nonisolated struct ReaderPalette: Equatable, Sendable {
    let backgroundHex: UInt32
    let surfaceHex: UInt32
    let surfaceAltHex: UInt32
    let textHex: UInt32
    let mutedHex: UInt32
    let faintHex: UInt32
    let ribbonHex: UInt32
    let isDark: Bool
    private let inkHex: UInt32
    private let borderOpacity: Double
    private let borderStrongOpacity: Double
    private let shadowOpacity: Double
    private let shadowIsBlack: Bool

    init(tokens: SharedThemeTokens) {
        backgroundHex = tokens.backgroundHex
        surfaceHex = tokens.surfaceHex
        surfaceAltHex = tokens.surfaceAltHex
        textHex = tokens.textHex
        mutedHex = tokens.mutedHex
        faintHex = tokens.faintHex
        inkHex = tokens.inkHex
        ribbonHex = tokens.ribbonHex
        isDark = tokens.isDark
        borderOpacity = tokens.borderOpacity
        borderStrongOpacity = tokens.borderStrongOpacity
        shadowOpacity = tokens.shadowOpacity
        shadowIsBlack = tokens.shadowIsBlack
    }

    var background: Color { .hex(backgroundHex) }
    var surface: Color { .hex(surfaceHex) }
    var surfaceAlt: Color { .hex(surfaceAltHex) }
    var text: Color { .hex(textHex) }
    var muted: Color { .hex(mutedHex) }
    var faint: Color { .hex(faintHex) }
    var ribbon: Color { .hex(ribbonHex) }
    var ribbonShade: Color { .hex(ribbonHex).mix(with: .black, by: 0.22) }
    var border: Color { .hex(inkHex, alpha: borderOpacity) }
    var borderStrong: Color { .hex(inkHex, alpha: borderStrongOpacity) }
    var shadow: Color { shadowIsBlack ? .black.opacity(shadowOpacity) : .hex(inkHex, alpha: shadowOpacity) }

    static func css(_ hex: UInt32) -> String { String(format: "#%06X", hex) }
}

enum ChickenMotion {
    static let micro = Animation.easeOut(duration: 0.16)
    static let standard = Animation.spring(response: 0.28, dampingFraction: 0.92)
    static let snappy = Animation.spring(response: 0.24, dampingFraction: 1.0)
    static let ribbonDrop = Animation.spring(response: 0.36, dampingFraction: 0.78)
    static let snap = Animation.spring(response: 0.28, dampingFraction: 1.0)
    static let momentum = Animation.spring(response: 0.36, dampingFraction: 0.82)
    static let press = Animation.easeOut(duration: 0.12)
    static let theme = Animation.easeInOut(duration: 0.24)
    static let reduced = Animation.easeInOut(duration: 0.14)

    static func spring(reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : snap
    }

    static func bouncy(reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : momentum
    }
}

// MARK: - Reading typefaces

/// Body faces for reflowable books. All ship with iOS and macOS.
nonisolated enum ReaderTypeface: String, CaseIterable, Identifiable, Sendable {
    case newYork
    case iowan
    case charter
    case athelas
    case sanFrancisco

    static let `default`: ReaderTypeface = .newYork

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newYork: "New York"
        case .iowan: "Iowan"
        case .charter: "Charter"
        case .athelas: "Athelas"
        case .sanFrancisco: "San Francisco"
        }
    }

    var cssFamily: String {
        switch self {
        case .newYork: "ui-serif, 'New York', Georgia, serif"
        case .iowan: "'Iowan Old Style', 'IowanOldStyle-Roman', Georgia, serif"
        case .charter: "Charter, 'Charter Roman', Georgia, serif"
        case .athelas: "Athelas, Georgia, serif"
        case .sanFrancisco: "-apple-system, system-ui, 'Helvetica Neue', sans-serif"
        }
    }

    func font(_ size: CGFloat) -> Font {
        switch self {
        case .newYork: .system(size: size, design: .serif)
        case .iowan: .custom("IowanOldStyle-Roman", size: size)
        case .charter: .custom("Charter-Roman", size: size)
        case .athelas: .custom("Athelas-Regular", size: size)
        case .sanFrancisco: .system(size: size)
        }
    }

    func platformFont(size: CGFloat, bold: Bool = false) -> PlatformFont {
        let name: String?
        switch self {
        case .iowan: name = bold ? "IowanOldStyle-Bold" : "IowanOldStyle-Roman"
        case .charter: name = bold ? "Charter-Bold" : "Charter-Roman"
        case .athelas: name = bold ? "Athelas-Bold" : "Athelas-Regular"
        case .newYork, .sanFrancisco: name = nil
        }
        if let name, let font = PlatformFont(name: name, size: size) { return font }
        let system = PlatformFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        guard self == .newYork, let descriptor = system.fontDescriptor.withDesign(.serif) else { return system }
        #if os(macOS)
        return PlatformFont(descriptor: descriptor, size: size) ?? system
        #else
        return PlatformFont(descriptor: descriptor, size: size)
        #endif
    }
}

// MARK: - Highlight colors

nonisolated enum HighlightColor: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case amber
    case green
    case purple
    case coral

    var id: String { rawValue }

    var label: String { rawValue.capitalized }

    var fill: Color {
        switch self {
        case .amber: .hex(0xEF9F27, alpha: 0.28)
        case .green: .hex(0x639922, alpha: 0.25)
        case .purple: .hex(0x7F77DD, alpha: 0.25)
        case .coral: .hex(0xD85A30, alpha: 0.23)
        }
    }

    var cssFill: String {
        switch self {
        case .amber: "rgba(239, 159, 39, 0.28)"
        case .green: "rgba(99, 153, 34, 0.25)"
        case .purple: "rgba(127, 119, 221, 0.25)"
        case .coral: "rgba(216, 90, 48, 0.23)"
        }
    }

    var bar: Color {
        switch self {
        case .amber: .hex(0xEF9F27)
        case .green: .hex(0x88BA4B)
        case .purple: .hex(0x9E96E5)
        case .coral: .hex(0xE88262)
        }
    }
}

// MARK: - Environment

extension EnvironmentValues {
    @Entry var readingTheme: ReadingTheme = .paper
}

extension EnvironmentValues {
    var palette: ReaderPalette { readingTheme.palette }
}

// MARK: - Type

extension Font {
    enum DisplayWeight {
        case light, regular, semibold, bold, black

        var swiftUIWeight: Font.Weight {
            switch self {
            case .light: .light
            case .regular: .semibold
            case .semibold: .semibold
            case .bold: .bold
            case .black: .heavy
            }
        }
    }

    static func chickenDisplay(_ size: CGFloat, weight: DisplayWeight = .regular, italic: Bool = false) -> Font {
        let base = Font.system(size: size, weight: weight.swiftUIWeight, design: .serif)
        return italic ? base.italic() : base
    }

    static func chickenSerif(_ size: CGFloat, weight: Font.Weight = .regular, italic: Bool = false) -> Font {
        let bold = weight == .semibold || weight == .bold || weight == .heavy || weight == .black
        let name: String
        switch (bold, italic) {
        case (false, false): name = "IowanOldStyle-Roman"
        case (false, true): name = "IowanOldStyle-Italic"
        case (true, false): name = "IowanOldStyle-Bold"
        case (true, true): name = "IowanOldStyle-BoldItalic"
        }
        return .custom(name, size: size, relativeTo: .chickenStyle(for: size))
    }

    static func chickenUI(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        #if os(macOS)
        .system(size: size, weight: weight)
        #else
        .system(.chickenStyle(for: size), weight: weight)
        #endif
    }

    static func chickenMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        chickenUI(size, weight: weight).monospacedDigit()
    }
}

extension Font.TextStyle {
    nonisolated static func chickenStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<11.5: .caption2
        case ..<12.5: .caption
        case ..<13.5: .footnote
        case ..<15.5: .subheadline
        case ..<16.5: .callout
        case ..<18.5: .body
        case ..<21: .title3
        case ..<25: .title2
        case ..<31: .title
        default: .largeTitle
        }
    }
}

extension Color {
    nonisolated static func hex(_ value: UInt32, alpha: Double = 1) -> Color {
        Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: alpha
        )
    }
}

extension View {
    func chickenEyebrow(_ palette: ReaderPalette, color: Color? = nil) -> some View {
        font(.chickenUI(11, weight: .semibold))
            .tracking(1.1)
            .textCase(.uppercase)
            .foregroundStyle(color ?? palette.muted)
    }

    func opticalDisplayTracking(for size: CGFloat) -> some View {
        tracking(size >= 34 ? -size * 0.024 : (size >= 22 ? -size * 0.016 : -0.15))
    }

    func readingTheme(_ theme: ReadingTheme) -> some View {
        environment(\.readingTheme, theme)
            .preferredColorScheme(theme.colorScheme)
            .tint(theme.palette.text)
    }
}
