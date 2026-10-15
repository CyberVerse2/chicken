import ChickenKit
import ImageIO
import SwiftUI

enum BookCoverStyle {
    case hero
    case tile
    case mini

    var titleSize: CGFloat {
        switch self {
        case .hero: return 26
        case .tile: return 17
        case .mini: return 7
        }
    }

    var authorSize: CGFloat {
        switch self {
        case .hero: return 14
        case .tile: return 10.5
        case .mini: return 5
        }
    }

    var padding: CGFloat {
        switch self {
        case .hero: return 22
        case .tile: return 13
        case .mini: return 4
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .hero: return 4
        case .tile: return 3
        case .mini: return 2
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

/// A book's cover image, or a cloth-bound typographic cover when the file has
/// none (or only has a landscape page that would crop badly). Either way it
/// gets a hinge and a little light, so it reads as an object, not a picture.
struct BookCover: View {
    @Environment(LibraryStore.self) private var library
    let book: Book
    let style: BookCoverStyle
    /// False for a blank cloth board, where the title is shown alongside.
    var showsClothText = true
    @State private var image: CGImage?
    /// A PDF whose first page is just text gets a cloth cover instead.
    @State private var isTextPage = false
    @State private var cacheGeneration = 0

    var body: some View {
        let preset = CoverPreset.preset(for: book.coverTintIndex)
        Rectangle()
            .fill(preset.cloth)
            .overlay {
                if let image, !isTextPage, CGFloat(image.width) / CGFloat(max(image.height, 1)) <= 1.05 {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ClothCover(title: book.title, author: book.author, preset: preset, style: style, showsText: showsClothText)
                }
            }
            .overlay { CoverFinish(style: style) }
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: style.cornerRadius * 0.5,
                bottomLeadingRadius: style.cornerRadius * 0.5,
                bottomTrailingRadius: style.cornerRadius,
                topTrailingRadius: style.cornerRadius,
                style: .continuous
            ))
            .task(id: "\(book.coverImageName ?? "")-\(cacheGeneration)") {
                guard let url = library.coverURL(for: book) else {
                    image = nil
                    return
                }
                let loaded = await CoverImageCache.shared.image(for: url, maxPixelSize: style.decodeSize)
                if book.format == .pdf, let loaded {
                    isTextPage = await CoverImageCache.shared.isTextPage(loaded, at: url)
                }
                image = loaded
            }
            .onReceive(NotificationCenter.default.publisher(for: .chickenCoversInvalidated)) { _ in
                image = nil
                cacheGeneration += 1
            }
            .accessibilityHidden(true)
    }
}

/// The hinge where the board meets the spine, a soft fall of light across
/// the board, and a hairline edge.
private struct CoverFinish: View {
    let style: BookCoverStyle

    var body: some View {
        GeometryReader { geometry in
            let hinge = max(2, geometry.size.width * 0.045)
            ZStack(alignment: .leading) {
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.10), location: 0),
                        .init(color: .clear, location: 0.35),
                        .init(color: .black.opacity(0.10), location: 1),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                HStack(spacing: 0) {
                    LinearGradient(colors: [.black.opacity(0.24), .black.opacity(0.06)], startPoint: .leading, endPoint: .trailing)
                        .frame(width: hinge)
                    LinearGradient(colors: [.white.opacity(0.16), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: hinge * 0.8)
                    Spacer(minLength: 0)
                }
            }
            .overlay {
                Rectangle().strokeBorder(.black.opacity(0.10), lineWidth: 0.5)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Cloth covers

/// A typographic cover in the manner of a cloth-bound hardback: title set in
/// Superclarendon, author in Iowan italic, a rule, and the house egg as a
/// colophon at the foot.
struct ClothCover: View {
    let title: String
    let author: String?
    let preset: CoverPreset
    let style: BookCoverStyle
    var showsText = true

    var body: some View {
        ZStack {
            ClothWeave(color: preset.ink)
            if !showsText {
                blank
            } else {
                switch preset.layout {
                case .framed: framed
                case .banded: banded
                case .plain: plain
                }
            }
        }
        .foregroundStyle(preset.ink)
    }

    /// An untitled board: the binding's rules and the egg stamped in the
    /// middle, like a cloth hardback without its jacket.
    private var blank: some View {
        EggShape()
            .stroke(preset.ink.opacity(0.55), lineWidth: 1.25)
            .frame(width: style.titleSize * 0.9, height: style.titleSize * 1.15)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                Rectangle().strokeBorder(preset.ink.opacity(0.45), lineWidth: 0.75).padding(style.padding * 0.55)
                Rectangle().strokeBorder(preset.ink.opacity(0.25), lineWidth: 0.5).padding(style.padding * 0.55 + 3)
            }
    }

    private var titleText: some View {
        Text(Self.displayTitle(title))
            .font(.chickenDisplay(style.titleSize, weight: style == .hero ? .regular : .regular))
            .lineSpacing(style == .mini ? 0 : -style.titleSize * 0.08)
            .lineLimit(style == .mini ? 3 : 5)
            .minimumScaleFactor(0.55)
            .allowsTightening(true)
    }

    @ViewBuilder
    private var authorText: some View {
        if style != .mini, let author, !author.isEmpty {
            Text(author)
                .font(.chickenSerif(style.authorSize, italic: true))
                .opacity(0.82)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
    }

    @ViewBuilder
    private var colophon: some View {
        if style != .mini {
            EggShape()
                .stroke(preset.ink.opacity(0.7), lineWidth: style == .hero ? 1 : 0.75)
                .frame(width: style.titleSize * 0.42, height: style.titleSize * 0.55)
        }
    }

    /// Double-ruled frame, title centred: the classic library binding.
    private var framed: some View {
        let inset = style.padding * 0.55
        return VStack(spacing: style.padding * 0.5) {
            Spacer(minLength: 0)
            titleText.multilineTextAlignment(.center)
            if style != .mini {
                Rectangle().frame(width: style.titleSize * 1.2, height: 0.75).opacity(0.6)
            }
            authorText.multilineTextAlignment(.center)
            Spacer(minLength: 0)
            colophon
        }
        .padding(style.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if style != .mini {
                Rectangle().strokeBorder(preset.ink.opacity(0.5), lineWidth: 0.75).padding(inset)
                Rectangle().strokeBorder(preset.ink.opacity(0.28), lineWidth: 0.5).padding(inset + 3)
            }
        }
    }

    /// A contrasting label band across the upper third, like a paper spine label.
    private var banded: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: geometry.size.height * 0.16)
                VStack(alignment: .leading, spacing: style.padding * 0.35) {
                    titleText.multilineTextAlignment(.leading)
                    authorText
                }
                .foregroundStyle(preset.cloth)
                .padding(.horizontal, style.padding)
                .padding(.vertical, style.padding * 0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(preset.ink)
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    colophon
                    Spacer()
                }
                .padding(.bottom, style.padding)
            }
        }
    }

    /// Flush-left title high on the board, a short rule, author below.
    private var plain: some View {
        VStack(alignment: .leading, spacing: style.padding * 0.45) {
            Rectangle().frame(width: style.padding * 1.3, height: style == .mini ? 0.5 : 1.25)
            titleText.multilineTextAlignment(.leading)
            authorText
            Spacer(minLength: 0)
            colophon
        }
        .padding(style.padding)
        .padding(.leading, style.padding * 0.25)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Long subtitles ("Moby-Dick; or, The Whale") make covers shout; the
    /// cover shows the main title only.
    static func displayTitle(_ title: String) -> String {
        for separator in [": ", "; "] {
            if let range = title.range(of: separator), title.distance(from: title.startIndex, to: range.lowerBound) >= 4 {
                return String(title[..<range.lowerBound])
            }
        }
        return title
    }
}

/// The faint crosshatch of bookcloth.
private struct ClothWeave: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 2.5
            var path = Path()
            var x: CGFloat = 0
            while x < size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            var y: CGFloat = 0
            while y < size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            context.stroke(path, with: .color(color.opacity(0.022)), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

enum CoverLayout { case framed, banded, plain }

/// Bookcloth colors drawn from the icon (soot, linen, cocoa, ochre) plus a
/// few classic binding shades so a shelf of cloth covers doesn't look cloned.
struct CoverPreset {
    let clothHex: UInt32
    let ink: Color
    let layout: CoverLayout

    var cloth: Color { .hex(clothHex) }

    static let all: [CoverPreset] = [
        CoverPreset(clothHex: 0x2A2523, ink: .hex(0xE9D9C2), layout: .framed),  // soot
        CoverPreset(clothHex: 0x76593F, ink: .hex(0xF2E6D6), layout: .plain),   // cocoa
        CoverPreset(clothHex: 0xC48C44, ink: .hex(0x2A2118), layout: .banded),  // ochre
        CoverPreset(clothHex: 0x45503A, ink: .hex(0xE6DCC0), layout: .framed),  // moss
        CoverPreset(clothHex: 0x6E2C27, ink: .hex(0xEFD9BE), layout: .plain),   // oxblood
        CoverPreset(clothHex: 0xE6D9C4, ink: .hex(0x2A2523), layout: .banded),  // linen
        CoverPreset(clothHex: 0x2F3E4A, ink: .hex(0xDCCBA8), layout: .plain),   // slate
        CoverPreset(clothHex: 0x9A4E2E, ink: .hex(0xF4E3CB), layout: .framed),  // rust
    ]

    static func preset(for index: Int) -> CoverPreset {
        all[((index % all.count) + all.count) % all.count]
    }

    static func preset(forTitle title: String) -> CoverPreset {
        preset(for: Int(title.stableChickenHash % UInt64(all.count)))
    }
}

// MARK: - The ribbon

/// A silk bookmark ribbon with a swallowtail end.
nonisolated struct RibbonShape: Shape {
    var notch: CGFloat = 0.9

    func path(in rect: CGRect) -> Path {
        let depth = min(rect.width * notch, rect.height * 0.5)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - depth))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Two-tone ribbon: the silk catches light on one side of its fold.
struct Ribbon: View {
    @Environment(\.palette) private var palette
    var color: Color?

    var body: some View {
        let base = color ?? palette.ribbon
        RibbonShape()
            .fill(base)
            .overlay {
                RibbonShape()
                    .fill(.black.opacity(0.16))
                    .mask(alignment: .trailing) {
                        GeometryReader { geometry in
                            Rectangle().frame(width: geometry.size.width / 2).frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
            }
    }
}

extension View {
    /// Hangs a ribbon out of the foot of a cover when the book is in
    /// progress, the way a real bookmark hangs out of a book you're reading.
    func coverRibbon(_ visible: Bool, length: CGFloat = 16, width: CGFloat = 7) -> some View {
        overlay(alignment: .bottomTrailing) {
            if visible {
                Ribbon()
                    .frame(width: width, height: length)
                    .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
                    .offset(x: -width * 2.2, y: length * 0.72)
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - The egg

/// Chicken's house mark, used as a colophon and for the yearly "clutch".
nonisolated struct EggShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = 72
        for index in 0...steps {
            let t = Double(index) / Double(steps) * 2 * .pi
            let y = -cos(t)
            let x = sin(t) * (1 + 0.16 * y) / 1.16
            let point = CGPoint(x: rect.midX + x * rect.width / 2, y: rect.midY + y * rect.height / 2)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

/// Decoded, downsampled cover images shared across views.
nonisolated final class CoverImageCache: @unchecked Sendable {
    static let shared = CoverImageCache()
    private let cache = NSCache<NSString, CGImage>()
    private let textPages = NSCache<NSString, NSNumber>()

    private init() {
        cache.countLimit = 600
        NotificationCenter.default.addObserver(forName: .chickenCoversInvalidated, object: nil, queue: nil) { [weak self] _ in
            self?.cache.removeAllObjects()
            self?.textPages.removeAllObjects()
        }
    }

    /// Whether a stored PDF cover is really a page of text. Covers saved
    /// before Chicken checked this at import are judged here instead.
    nonisolated func isTextPage(_ image: CGImage, at url: URL) async -> Bool {
        let key = url.path as NSString
        if let cached = textPages.object(forKey: key) { return cached.boolValue }
        let verdict = await Task.detached(priority: .utility) {
            CoverRenderer.looksLikeTextPage(image)
        }.value
        textPages.setObject(NSNumber(value: verdict), forKey: key)
        return verdict
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
