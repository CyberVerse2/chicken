import ImageIO
import SwiftUI

enum BookCoverStyle {
    case hero
    case tile
    case mini

    var titleSize: CGFloat {
        switch self {
        case .hero: return 22
        case .tile: return 16
        case .mini: return 8
        }
    }

    var authorSize: CGFloat {
        switch self {
        case .hero: return 13
        case .tile: return 11
        case .mini: return 6
        }
    }

    var padding: CGFloat {
        switch self {
        case .hero: return 26
        case .tile: return 18
        case .mini: return 7
        }
    }

    /// Pixel size to decode covers at; tiles don't need full-resolution JPEGs.
    var decodeSize: Int {
        switch self {
        case .hero: return 900
        case .tile: return 600
        case .mini: return 240
        }
    }
}

/// A book's cover image, or a stylized typographic cover when the file has
/// none (or only has a landscape page that would crop badly).
struct BookCover: View {
    @Environment(LibraryStore.self) private var library
    let book: Book
    let style: BookCoverStyle
    @State private var image: CGImage?
    @State private var cacheGeneration = 0

    var body: some View {
        let preset = CoverPreset.preset(for: book.coverTintIndex)
        Rectangle()
            .fill(preset.background)
            .overlay {
                if let image, CGFloat(image.width) / CGFloat(max(image.height, 1)) <= 1.05 {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    StylizedCover(title: book.title, author: book.displayAuthor, preset: preset, style: style)
                }
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: style == .mini ? 3 : 5, style: .continuous))
            .task(id: "\(book.coverImageName ?? "")-\(cacheGeneration)") {
                guard let url = library.coverURL(for: book) else {
                    image = nil
                    return
                }
                image = await CoverImageCache.shared.image(for: url, maxPixelSize: style.decodeSize)
            }
            .onReceive(NotificationCenter.default.publisher(for: .chickenCoversInvalidated)) { _ in
                image = nil
                cacheGeneration += 1
            }
            .accessibilityHidden(true)
    }
}

private struct StylizedCover: View {
    let title: String
    let author: String
    let preset: CoverPreset
    let style: BookCoverStyle

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CoverMotif(kind: preset.motif, accent: preset.accent)
            VStack(alignment: .leading, spacing: style == .mini ? 3 : 8) {
                Rectangle()
                    .fill(preset.accent.opacity(0.5))
                    .frame(width: style.padding, height: 1)
                Text(title)
                    .font(.system(size: style.titleSize, weight: .medium, design: .serif))
                    .foregroundStyle(preset.accent)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                if style != .mini {
                    Text(author)
                        .font(.system(size: style.authorSize, design: .serif).italic())
                        .foregroundStyle(preset.accent.opacity(0.78))
                        .lineLimit(2)
                }
            }
            .padding(style.padding)
        }
    }
}

struct CoverPreset {
    let background: Color
    let accent: Color
    let motif: CoverMotifKind

    static let all: [CoverPreset] = [
        CoverPreset(background: .hex(0x1F3A4D), accent: .hex(0xD9B380), motif: .lines),
        CoverPreset(background: .hex(0x6B3E3A), accent: .hex(0xF4E4D0), motif: .frame),
        CoverPreset(background: .hex(0x2D4A2A), accent: .hex(0xD8C99B), motif: .tree),
        CoverPreset(background: .hex(0x1A1A1A), accent: .hex(0xC9A861), motif: .flourish),
        CoverPreset(background: .hex(0x3A3D40), accent: .hex(0xB8B0A0), motif: .crack),
        CoverPreset(background: .hex(0xB8902F), accent: .hex(0x2A2519), motif: .pattern),
    ]

    static func preset(for index: Int) -> CoverPreset {
        all[((index % all.count) + all.count) % all.count]
    }
}

enum CoverMotifKind { case lines, frame, tree, flourish, crack, pattern }

struct CoverMotif: View {
    let kind: CoverMotifKind
    let accent: Color

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            func line(_ points: [(CGFloat, CGFloat)], opacity: Double, width: CGFloat = 0.5) {
                var path = Path()
                path.addLines(points.map { CGPoint(x: w * $0.0, y: h * $0.1) })
                context.stroke(path, with: .color(accent.opacity(opacity)), lineWidth: width)
            }

            switch kind {
            case .lines:
                line([(0.10, 0.27), (0.90, 0.20)], opacity: 0.18)
                line([(0.20, 0.43), (0.85, 0.53)], opacity: 0.18)
                line([(0.10, 0.66), (0.80, 0.60)], opacity: 0.18)
                for (x, y) in [(0.30, 0.33), (0.70, 0.50), (0.45, 0.65)] {
                    context.fill(Path(ellipseIn: CGRect(x: w * x - 2, y: h * y - 2, width: 4, height: 4)), with: .color(accent.opacity(0.18)))
                }
            case .frame:
                context.stroke(Path(CGRect(x: 12, y: 12, width: w - 24, height: h - 24)), with: .color(accent.opacity(0.40)), lineWidth: 0.5)
                context.stroke(Path(CGRect(x: 16, y: 16, width: w - 32, height: h - 32)), with: .color(accent.opacity(0.24)), lineWidth: 0.3)
            case .tree:
                for x in [0.20, 0.50, 0.80] { line([(x, 0.20), (x, 0.80)], opacity: 0.18) }
                for x in [0.35, 0.65] { line([(x, 0.30), (x, 0.70)], opacity: 0.14, width: 0.4) }
            case .flourish:
                var path = Path()
                path.move(to: CGPoint(x: w * 0.2, y: h * 0.5))
                path.addQuadCurve(to: CGPoint(x: w * 0.5, y: h * 0.5), control: CGPoint(x: w * 0.35, y: h * 0.4))
                path.addQuadCurve(to: CGPoint(x: w * 0.8, y: h * 0.5), control: CGPoint(x: w * 0.65, y: h * 0.6))
                context.stroke(path, with: .color(accent.opacity(0.5)), lineWidth: 0.5)
                context.fill(Path(ellipseIn: CGRect(x: w * 0.5 - 1.5, y: h * 0.5 - 1.5, width: 3, height: 3)), with: .color(accent.opacity(0.5)))
            case .crack:
                line([(0.50, 0), (0.47, 0.20), (0.55, 0.37), (0.45, 0.57), (0.52, 0.77), (0.47, 1)], opacity: 0.18)
            case .pattern:
                let step: CGFloat = 18
                var x: CGFloat = 0
                while x < w + step {
                    var y: CGFloat = 0
                    while y < h + step {
                        context.stroke(Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6)), with: .color(accent.opacity(0.22)), lineWidth: 0.5)
                        context.fill(Path(ellipseIn: CGRect(x: x + step / 2 - 1, y: y + step / 2 - 1, width: 2, height: 2)), with: .color(accent.opacity(0.22)))
                        y += step
                    }
                    x += step
                }
            }
        }
    }
}

/// Decoded, downsampled cover images shared across views.
nonisolated final class CoverImageCache: @unchecked Sendable {
    static let shared = CoverImageCache()
    private let cache = NSCache<NSString, CGImage>()

    private init() {
        cache.countLimit = 600
        NotificationCenter.default.addObserver(forName: .chickenCoversInvalidated, object: nil, queue: nil) { [weak self] _ in
            self?.cache.removeAllObjects()
        }
    }

    nonisolated func image(for url: URL, maxPixelSize: Int) async -> CGImage? {
        let key = "\(url.path)@\(maxPixelSize)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image = await Task.detached(priority: .utility) { () -> CGImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }.value
        if let image { cache.setObject(image, forKey: key) }
        return image
    }
}
