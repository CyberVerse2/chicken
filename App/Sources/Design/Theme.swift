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
                background: 0xF4EEE4, surface: 0xFBF8F2, surfaceAlt: 0xEAE2D5,
                text: 0x211D1C, muted: 0x6E6259, faint: 0xA89C90,
                ink: 0x211D1C, ribbon: 0xB57631, borderOpacity: 0.10, borderStrongOpacity: 0.20, shadowOpacity: 0.10
            )
        case .sepia:
            return ReaderPalette(
                background: 0xEEDFC4, surface: 0xF6EBD6, surfaceAlt: 0xE3D1B0,
                text: 0x3B2A1A, muted: 0x77593C, faint: 0xA68B6A,
                ink: 0x3B2A1A, ribbon: 0xA9642A, borderOpacity: 0.14, borderStrongOpacity: 0.24, shadowOpacity: 0.12
            )
        case .ink:
            // The icon's own colors: soot ground, linen hen, ochre ribbon.
            return ReaderPalette(
                background: 0x171413, surface: 0x211D1C, surfaceAlt: 0x2D2826,
                text: 0xF2E6D6, muted: 0xA89B8C, faint: 0x6D6359,
                ink: 0xF2E6D6, ribbon: 0xCB8D45, borderOpacity: 0.09, borderStrongOpacity: 0.16, shadowOpacity: 0.45, shadowIsBlack: true
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
    /// Ochre silk bookmark: the one brand accent, used only to mark "your
    /// place" (progress, bookmarks, the book you're in).
    let ribbonHex: UInt32
    private let inkHex: UInt32
    private let borderOpacity: Double
    private let borderStrongOpacity: Double
    private let shadowOpacity: Double
    private let shadowIsBlack: Bool

    init(
        background: UInt32, surface: UInt32, surfaceAlt: UInt32,
        text: UInt32, muted: UInt32, faint: UInt32,
        ink: UInt32, ribbon: UInt32, borderOpacity: Double, borderStrongOpacity: Double, shadowOpacity: Double,
        shadowIsBlack: Bool = false
    ) {
        backgroundHex = background
        surfaceHex = surface
        surfaceAltHex = surfaceAlt
        textHex = text
        mutedHex = muted
        faintHex = faint
        inkHex = ink
        ribbonHex = ribbon
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
    var ribbon: Color { .hex(ribbonHex) }
    /// A deeper fold of the ribbon, for the shaded half of the silk.
    var ribbonShade: Color { .hex(ribbonHex).mix(with: .black, by: 0.22) }
    var border: Color { .hex(inkHex, alpha: borderOpacity) }
    var borderStrong: Color { .hex(inkHex, alpha: borderStrongOpacity) }
    var shadow: Color { shadowIsBlack ? .black.opacity(shadowOpacity) : .hex(inkHex, alpha: shadowOpacity) }

    static func css(_ hex: UInt32) -> String { String(format: "#%06X", hex) }
}

// MARK: - Reading typefaces

/// Body faces for reflowable books. All ship with iOS and macOS.
enum ReaderTypeface: String, CaseIterable, Identifiable {
    case newYork
    case iowan
    case charter
    case athelas
    case sanFrancisco

    static let `default`: ReaderTypeface = .newYork

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newYork: return "New York"
        case .iowan: return "Iowan"
        case .charter: return "Charter"
        case .athelas: return "Athelas"
        case .sanFrancisco: return "San Francisco"
        }
    }

    /// CSS font stack for EPUBs.
    var cssFamily: String {
        switch self {
        case .newYork: return "ui-serif, 'New York', Georgia, serif"
        case .iowan: return "'Iowan Old Style', 'IowanOldStyle-Roman', Georgia, serif"
        case .charter: return "Charter, 'Charter Roman', Georgia, serif"
        case .athelas: return "Athelas, Georgia, serif"
        case .sanFrancisco: return "-apple-system, system-ui, 'Helvetica Neue', sans-serif"
        }
    }

    /// The face for SwiftUI previews of the setting.
    func font(_ size: CGFloat) -> Font {
        switch self {
        case .newYork: return .system(size: size, design: .serif)
        case .iowan: return .custom("IowanOldStyle-Roman", size: size)
        case .charter: return .custom("Charter-Roman", size: size)
        case .athelas: return .custom("Athelas-Regular", size: size)
        case .sanFrancisco: return .system(size: size)
        }
    }

    /// The face for the native text reader.
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
    /// Display face: Superclarendon, a sturdy 19th-century Clarendon with
    /// ball terminals — the voice of almanacs and county-fair posters. Used
    /// with restraint: greetings, page titles, the book you're in, numbers
    /// worth celebrating. Ships with both iOS and macOS.
    static func chickenDisplay(_ size: CGFloat, weight: DisplayWeight = .regular, italic: Bool = false) -> Font {
        .custom(weight.postScriptName(italic: italic), size: size, relativeTo: .chickenStyle(for: size))
    }

    enum DisplayWeight {
        case light, regular, bold, black

        func postScriptName(italic: Bool) -> String {
            let base: String
            switch self {
            case .light: base = "Superclarendon-Light"
            case .regular: base = "Superclarendon-Regular"
            case .bold: base = "Superclarendon-Bold"
            case .black: base = "Superclarendon-Black"
            }
            guard italic else { return base }
            return self == .regular ? "Superclarendon-Italic" : base + "Italic"
        }
    }

    /// Book face: Iowan Old Style, for titles in lists, authors (italic),
    /// quotations, and anything that should read like a page.
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

    /// UI chrome: toolbars, buttons, labels. On iPhone and iPad this is the
    /// nearest system text style, so it follows the reader's text size; the
    /// Mac keeps exact sizes.
    static func chickenUI(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        #if os(macOS)
        .system(size: size, weight: weight)
        #else
        .system(.chickenStyle(for: size), weight: weight)
        #endif
    }

    /// Measurements and counts: the UI face with even-width figures.
    static func chickenMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        chickenUI(size, weight: weight).monospacedDigit()
    }
}

extension Font.TextStyle {
    /// The text style a fixed size stands in for, so Chicken's type scales
    /// with Dynamic Type from the size it was designed at.
    static func chickenStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<11.5: return .caption2
        case ..<12.5: return .caption
        case ..<13.5: return .footnote
        case ..<15.5: return .subheadline
        case ..<16.5: return .callout
        case ..<18.5: return .body
        case ..<21: return .title3
        case ..<25: return .title2
        case ..<31: return .title
        default: return .largeTitle
        }
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
        font(.chickenUI(10.5, weight: .semibold))
            .tracking(1.6)
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
