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
        case .ink:   return "Ink"
        }
    }

    var palette: ReaderPalette {
        switch self {
        case .paper:
            return ReaderPalette(
                background:    .hex(0xF5F1E8),
                surface:       .hex(0xFFFFFF),
                surfaceAlt:    .hex(0xEDE7D9),
                text:          .hex(0x1F1B16),
                muted:         .hex(0x6B655B),
                faint:         .hex(0xA8A095),
                border:        Color(.sRGB, red: 0.122, green: 0.106, blue: 0.086, opacity: 0.10),
                borderStrong:  Color(.sRGB, red: 0.122, green: 0.106, blue: 0.086, opacity: 0.18),
                shadow:        Color(.sRGB, red: 0.122, green: 0.106, blue: 0.086, opacity: 0.08)
            )
        case .sepia:
            return ReaderPalette(
                background:    .hex(0xEFE3CC),
                surface:       .hex(0xF4EAD3),
                surfaceAlt:    .hex(0xE5D6B8),
                text:          .hex(0x3A2A18),
                muted:         .hex(0x7A5A40),
                faint:         .hex(0xA89070),
                border:        Color(.sRGB, red: 0.227, green: 0.165, blue: 0.094, opacity: 0.14),
                borderStrong:  Color(.sRGB, red: 0.227, green: 0.165, blue: 0.094, opacity: 0.22),
                shadow:        Color(.sRGB, red: 0.227, green: 0.165, blue: 0.094, opacity: 0.10)
            )
        case .ink:
            return ReaderPalette(
                background:    .hex(0x0F0F10),
                surface:       .hex(0x1A1A1B),
                surfaceAlt:    .hex(0x252527),
                text:          .hex(0xE8E6E1),
                muted:         .hex(0x9A968D),
                faint:         .hex(0x5A5851),
                border:        Color.white.opacity(0.08),
                borderStrong:  Color.white.opacity(0.14),
                shadow:        Color.black.opacity(0.40)
            )
        }
    }

    var preferredColorScheme: ColorScheme {
        self == .ink ? .dark : .light
    }
}

struct ReaderPalette: Equatable {
    let background: Color
    let surface: Color
    let surfaceAlt: Color
    let text: Color
    let muted: Color
    let faint: Color
    let border: Color
    let borderStrong: Color
    let shadow: Color
}

// MARK: - Highlight palette

enum HighlightColor: String, Codable, CaseIterable, Hashable, Identifiable {
    case amber
    case green
    case purple
    case coral

    var id: String { rawValue }

    /// Translucent fill for the inline highlight on the running text.
    var fill: Color {
        switch self {
        case .amber:  return Color(.sRGB, red: 0.937, green: 0.624, blue: 0.153, opacity: 0.30)
        case .green:  return Color(.sRGB, red: 0.388, green: 0.600, blue: 0.133, opacity: 0.28)
        case .purple: return Color(.sRGB, red: 0.498, green: 0.467, blue: 0.867, opacity: 0.28)
        case .coral:  return Color(.sRGB, red: 0.847, green: 0.353, blue: 0.188, opacity: 0.25)
        }
    }

    /// Solid bar tint for the highlight rail in the side panel.
    var bar: Color {
        switch self {
        case .amber:  return .hex(0xEF9F27)
        case .green:  return .hex(0x97C459)
        case .purple: return .hex(0xAFA9EC)
        case .coral:  return .hex(0xF0997B)
        }
    }
}

// MARK: - Theme environment

private struct ReaderThemeKey: EnvironmentKey {
    static let defaultValue: ReadingTheme = .paper
}

extension EnvironmentValues {
    var readingTheme: ReadingTheme {
        get { self[ReaderThemeKey.self] }
        set { self[ReaderThemeKey.self] = newValue }
    }

    var palette: ReaderPalette { readingTheme.palette }
}

// MARK: - Fonts

extension Font {
    /// Reading body, titles, drop caps. Uses the system serif (New York on macOS).
    static func chickenSerif(_ size: CGFloat, weight: Font.Weight = .regular, italic: Bool = false) -> Font {
        let base: Font = .system(size: size, weight: weight, design: .serif)
        return italic ? base.italic() : base
    }

    /// UI chrome: toolbars, buttons, side-panel labels.
    static func chickenUI(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// Tabular numbers / measurements that benefit from monospace.
    static func chickenMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Color helpers

extension Color {
    static func hex(_ value: UInt32, alpha: Double = 1) -> Color {
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8)  & 0xFF) / 255
        let b = Double( value        & 0xFF) / 255
        return Color(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

// MARK: - Small caps eyebrow modifier

extension View {
    /// Section labels, chapter eyebrows, metadata accents.
    func chickenEyebrow(_ palette: ReaderPalette) -> some View {
        self
            .font(.chickenUI(11, weight: .medium))
            .tracking(1.5)
            .textCase(.uppercase)
            .foregroundStyle(palette.muted)
    }
}
