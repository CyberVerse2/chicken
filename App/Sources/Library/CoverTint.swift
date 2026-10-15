import ChickenKit
import CoreGraphics
import SwiftUI

/// A book's colour, taken from its cover: the cloth of a typographic cover,
/// or the average of real cover art. Each details card washes its top in
/// a shade of it, so every book's card has its own character.
nonisolated struct CoverHue: Equatable, Sendable {
    let hue: Double
    let saturation: Double

    /// The card colour for a theme: light enough under dark text in Paper
    /// and Sepia, deep enough under light text in Ink, but clearly the
    /// cover's hue either way.
    func wash(for theme: ReadingTheme) -> Color {
        let saturation = min(self.saturation, 0.7)
        switch theme {
        case .paper: return Color(hue: hue, saturation: saturation * 0.55, brightness: 0.9)
        case .sepia: return Color(hue: hue, saturation: saturation * 0.6, brightness: 0.85)
        case .ink: return Color(hue: hue, saturation: saturation * 0.75, brightness: 0.3)
        }
    }

    /// A strong band of the cover's colour that carries light text in any
    /// theme, as the header of a card on the Mac.
    var band: Color {
        let saturation = min(max(self.saturation * 1.3, 0), 0.72)
        return Color(hue: hue, saturation: saturation, brightness: saturation < 0.12 ? 0.3 : 0.4)
    }

    init(hue: Double, saturation: Double) {
        self.hue = hue
        self.saturation = saturation
    }

    init(red: Double, green: Double, blue: Double) {
        let high = max(red, green, blue)
        let low = min(red, green, blue)
        let delta = high - low
        saturation = high > 0 ? delta / high : 0
        guard delta > 0 else {
            hue = 0
            return
        }
        var value: Double
        if high == red {
            value = (green - blue) / delta
        } else if high == green {
            value = (blue - red) / delta + 2
        } else {
            value = (red - green) / delta + 4
        }
        value /= 6
        hue = value < 0 ? value + 1 : value
    }

    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension CoverImageCache {
    /// The average colour of a cover image, or nil if it can't be read.
    nonisolated func hue(for url: URL) async -> CoverHue? {
        guard let image = await image(for: url, maxPixelSize: 64) else { return nil }
        return await Task.detached(priority: .utility) { () -> CoverHue? in
            var pixel = [UInt8](repeating: 0, count: 4)
            let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(
                    data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                ) else { return false }
                context.interpolationQuality = .medium
                context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                return true
            }
            guard drawn else { return nil }
            return CoverHue(red: Double(pixel[0]) / 255, green: Double(pixel[1]) / 255, blue: Double(pixel[2]) / 255)
        }.value
    }
}

/// Loads a book's cover colour for its details card.
struct CoverTintModifier: ViewModifier {
    @Environment(LibraryStore.self) private var library
    @Environment(\.readingTheme) private var theme
    @Environment(\.palette) private var palette
    let book: Book
    @State private var coverHue: CoverHue?

    func body(content: Content) -> some View {
        content
            .background {
                // The card is filled with the book's colour, settling a
                // little toward the page further down.
                let fill = coverHue?.wash(for: theme) ?? palette.surface
                LinearGradient(
                    colors: [fill, fill.mix(with: palette.background, by: 0.45)],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.35), value: coverHue)
            }
            .task(id: "\(book.id)-\(book.coverImageName ?? "")") {
                coverHue = await Self.hue(for: book, library: library)
            }
    }

    @MainActor
    static func hue(for book: Book, library: LibraryStore) async -> CoverHue {
        let cloth = CoverHue(hex: CoverPreset.preset(for: book.coverTintIndex).clothHex)
        guard let url = library.coverURL(for: book) else { return cloth }
        if book.format == .pdf,
           let image = await CoverImageCache.shared.image(for: url, maxPixelSize: 600),
           await CoverImageCache.shared.isTextPage(image, at: url) {
            return cloth
        }
        return await CoverImageCache.shared.hue(for: url) ?? cloth
    }
}
