import SwiftUI

// MARK: - Reading themes

enum ReadingTheme: String, Codable, CaseIterable, Hashable, Identifiable {
    case paper
    case sepia
    case ink

    var id: String { rawValue }

    var label: String {
        switch self {
        case .paper: return "Paper"
        case .sepia: return "Sepia"
        case .ink: return "Ink"
        }
    }

    var systemImage: String {
        switch self {
        case .paper: return "sun.max"
        case .sepia: return "book.closed"
        case .ink: return "moon"
        }
    }

    var next: ReadingTheme {
        let all = Self.allCases
        return all[((all.firstIndex(of: self) ?? 0) + 1) % all.count]
    }

    /// Glass and system controls follow this, so Ink gets dark glass.
    var colorScheme: ColorScheme { self == .ink ? .dark : .light }

    var palette: ReaderPalette {
        switch self {
        case .paper:
            return ReaderPalette(
                background: 0xF5F1E8, surface: 0xFFFFFF, surfaceAlt: 0xEDE7D9,
                text: 0x1F1B16, muted: 0x6B655B, faint: 0xA8A095,
                ink: 0x1F1B16, borderOpacity: 0.10, borderStrongOpacity: 0.18, shadowOpacity: 0.08
            )
        case .sepia:
            return ReaderPalette(
                background: 0xEFE3CC, surface: 0xF4EAD3, surfaceAlt: 0xE5D6B8,
                text: 0x3A2A18, muted: 0x7A5A40, faint: 0xA89070,
                ink: 0x3A2A18, borderOpacity: 0.14, borderStrongOpacity: 0.22, shadowOpacity: 0.10
            )
        case .ink:
            return ReaderPalette(
                background: 0x0F0F10, surface: 0x1A1A1B, surfaceAlt: 0x252527,
                text: 0xE8E6E1, muted: 0x9A968D, faint: 0x5A5851,
                ink: 0xFFFFFF, borderOpacity: 0.08, borderStrongOpacity: 0.14, shadowOpacity: 0.40, shadowIsBlack: true
            )
        }
    }
}

/// Theme colors, kept as hex values so the EPUB stylesheet can use the exact
/// same colors as the SwiftUI chrome.
struct ReaderPalette: Equatable {
    let backgroundHex: UInt32
    let surfaceHex: UInt32
    let surfaceAltHex: UInt32
    let textHex: UInt32
    let mutedHex: UInt32
    let faintHex: UInt32
    private let inkHex: UInt32
    private let borderOpacity: Double
    private let borderStrongOpacity: Double
    private let shadowOpacity: Double
    private let shadowIsBlack: Bool

    init(
        background: UInt32, surface: UInt32, surfaceAlt: UInt32,
        text: UInt32, muted: UInt32, faint: UInt32,
        ink: UInt32, borderOpacity: Double, borderStrongOpacity: Double, shadowOpacity: Double,
        shadowIsBlack: Bool = false
    ) {
        backgroundHex = background
        surfaceHex = surface
        surfaceAltHex = surfaceAlt
        textHex = text
        mutedHex = muted
        faintHex = faint
        inkHex = ink
        self.borderOpacity = borderOpacity
        self.borderStrongOpacity = borderStrongOpacity
        self.shadowOpacity = shadowOpacity
        self.shadowIsBlack = shadowIsBlack
    }

    var background: Color { .hex(backgroundHex) }
    var surface: Color { .hex(surfaceHex) }
    var surfaceAlt: Color { .hex(surfaceAltHex) }
    var text: Color { .hex(textHex) }
    var muted: Color { .hex(mutedHex) }
    var faint: Color { .hex(faintHex) }
    var border: Color { .hex(inkHex, alpha: borderOpacity) }
    var borderStrong: Color { .hex(inkHex, alpha: borderStrongOpacity) }
    var shadow: Color { shadowIsBlack ? .black.opacity(shadowOpacity) : .hex(inkHex, alpha: shadowOpacity) }

    static func css(_ hex: UInt32) -> String { String(format: "#%06X", hex) }
}

// MARK: - Highlight colors

enum HighlightColor: String, Codable, CaseIterable, Hashable, Identifiable {
    case amber
    case green
    case purple
    case coral

    var id: String { rawValue }

    var label: String { rawValue.capitalized }

    /// Translucent fill on the running text.
    var fill: Color {
        switch self {
        case .amber: return .hex(0xEF9F27, alpha: 0.30)
        case .green: return .hex(0x639922, alpha: 0.28)
        case .purple: return .hex(0x7F77DD, alpha: 0.28)
        case .coral: return .hex(0xD85A30, alpha: 0.25)
        }
    }

    /// CSS equivalent of `fill` for highlights drawn inside EPUBs.
    var cssFill: String {
        switch self {
        case .amber: return "rgba(239, 159, 39, 0.30)"
        case .green: return "rgba(99, 153, 34, 0.28)"
        case .purple: return "rgba(127, 119, 221, 0.28)"
        case .coral: return "rgba(216, 90, 48, 0.25)"
        }
    }

    /// Solid bar in the highlights rail.
    var bar: Color {
        switch self {
        case .amber: return .hex(0xEF9F27)
        case .green: return .hex(0x97C459)
        case .purple: return .hex(0xAFA9EC)
        case .coral: return .hex(0xF0997B)
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
    /// Reading body, titles, drop caps: the system serif (New York).
    static func chickenSerif(_ size: CGFloat, weight: Font.Weight = .regular, italic: Bool = false) -> Font {
        let base = Font.system(size: size, weight: weight, design: .serif)
        return italic ? base.italic() : base
    }

    /// UI chrome: toolbars, buttons, labels.
    static func chickenUI(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// Measurements and counts.
    static func chickenMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension Color {
    static func hex(_ value: UInt32, alpha: Double = 1) -> Color {
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
    /// Small-caps section label: sans, 11pt, tracked, uppercase, muted.
    func chickenEyebrow(_ palette: ReaderPalette, color: Color? = nil) -> some View {
        font(.chickenUI(11, weight: .medium))
            .tracking(1.5)
            .textCase(.uppercase)
            .foregroundStyle(color ?? palette.muted)
    }

    /// Applies the reading theme to a subtree: palette, glass color scheme,
    /// and a smooth cross-fade when the theme changes.
    func readingTheme(_ theme: ReadingTheme) -> some View {
        environment(\.readingTheme, theme)
            .preferredColorScheme(theme.colorScheme)
            .tint(theme.palette.text)
    }
}
