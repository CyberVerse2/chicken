import ChickenKit
import ImageIO
import SwiftUI

enum BookCoverStyle {
    case hero
    case tile
    case mini

    var titleSize: CGFloat {
        switch self {
        case .hero: 24
        case .tile: 16
        case .mini: 7
        }
    }

    var authorSize: CGFloat {
        switch self {
        case .hero: 13.5
        case .tile: 10.5
        case .mini: 5
        }
    }

    var padding: CGFloat {
        switch self {
        case .hero: 20
        case .tile: 12
        case .mini: 4
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .hero: 6
        case .tile: 4
        case .mini: 2.5
        }
    }

    var decodeSize: Int {
        switch self {
        case .hero: 900
        case .tile: 600
        case .mini: 240
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
    var showsClothText = true
    @State private var image: CGImage?
    @State private var isTextPage = false

    private var reloadKey: String {
        "\(book.coverImageName ?? "")-\(library.coversGeneration)-\(image == nil ? library.cloudFilesGeneration : 0)"
    }

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
                    ClothCover(
                        title: book.displayTitle,
                        author: book.author,
                        preset: preset,
                        style: style,
                        showsText: showsClothText
                    )
                }
            }
            .overlay { CoverFinish(style: style) }
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: style.cornerRadius * 0.45,
                bottomLeadingRadius: style.cornerRadius * 0.45,
                bottomTrailingRadius: style.cornerRadius,
                topTrailingRadius: style.cornerRadius,
                style: .continuous
            ))
            .task(id: reloadKey) {
                guard let url = library.coverURL(for: book) else {
                    image = nil
                    isTextPage = false
                    return
                }
                let loaded = await CoverImageCache.shared.image(for: url, maxPixelSize: style.decodeSize)
                if book.format == .pdf, let loaded {
                    isTextPage = await CoverImageCache.shared.isTextPage(loaded, at: url)
                } else {
                    isTextPage = false
                }
                image = loaded
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
            let hinge = max(2.5, geometry.size.width * 0.05)
            ZStack(alignment: .leading) {
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.11), location: 0),
                        .init(color: .clear, location: 0.32),
                        .init(color: .black.opacity(0.12), location: 1),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                HStack(spacing: 0) {
                    LinearGradient(colors: [.black.opacity(0.28), .black.opacity(0.08)], startPoint: .leading, endPoint: .trailing)
                        .frame(width: hinge)
                    Rectangle()
                        .fill(.white.opacity(0.18))
                        .frame(width: 0.75)
                    LinearGradient(colors: [.black.opacity(0.09), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: hinge * 0.7)
                    Spacer(minLength: 0)
                }
            }
            .overlay {
                Rectangle().strokeBorder(.white.opacity(0.09), lineWidth: 0.5)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Cloth covers

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
                monogramBoard
            } else {
                switch preset.layout {
                case .editorial: editorial
                case .framed: framed
                case .banded: banded
                }
            }
        }
        .foregroundStyle(preset.ink)
    }

    private var monogramBoard: some View {
        let inset = style.padding * 0.55
        let initial = String(Self.displayTitle(title).prefix(1)).uppercased()
        return VStack(spacing: style.padding * 0.45) {
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .strokeBorder(preset.accent.opacity(0.55), lineWidth: 1)
                    .frame(width: style.titleSize * 2.1, height: style.titleSize * 2.1)
                Text(initial.isEmpty ? "C" : initial)
                    .font(.chickenDisplay(style.titleSize * 1.1, weight: .bold))
                    .foregroundStyle(preset.ink.opacity(0.9))
            }
            Rectangle()
                .fill(preset.accent.opacity(0.5))
                .frame(width: style.titleSize * 1.1, height: 1)
            Spacer(minLength: 0)
            colophon
        }
        .padding(style.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            Rectangle().strokeBorder(preset.ink.opacity(0.32), lineWidth: 0.75).padding(inset)
            Rectangle().strokeBorder(preset.ink.opacity(0.16), lineWidth: 0.5).padding(inset + 3.5)
        }
    }

    private var titleText: some View {
        Text(Self.displayTitle(title))
            .font(.chickenDisplay(style.titleSize, weight: .bold))
            .opticalDisplayTracking(for: style.titleSize)
            .lineSpacing(style == .mini ? 0 : -style.titleSize * 0.06)
            .lineLimit(style == .mini ? 3 : 5)
            .minimumScaleFactor(0.55)
            .allowsTightening(true)
    }

    @ViewBuilder
    private var authorText: some View {
        if style != .mini, let author, !author.isEmpty {
            Text(author)
                .font(.chickenSerif(style.authorSize, italic: true))
                .opacity(0.84)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
    }

    @ViewBuilder
    private var colophon: some View {
        if style != .mini {
            EggShape()
                .stroke(preset.accent.opacity(0.72), lineWidth: style == .hero ? 1.1 : 0.8)
                .frame(width: style.titleSize * 0.42, height: style.titleSize * 0.55)
        }
    }

    private var editorial: some View {
        VStack(alignment: .leading, spacing: style.padding * 0.42) {
            HStack(spacing: 5) {
                Rectangle().fill(preset.accent).frame(width: style.padding * 1.1, height: style == .mini ? 0.8 : 1.5)
                Spacer(minLength: 0)
            }
            titleText.multilineTextAlignment(.leading)
            authorText
            Spacer(minLength: 0)
            HStack {
                colophon
                Spacer()
            }
        }
        .padding(style.padding)
        .padding(.leading, style.padding * 0.25)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var framed: some View {
        let inset = style.padding * 0.55
        return VStack(spacing: style.padding * 0.48) {
            Spacer(minLength: 0)
            titleText.multilineTextAlignment(.center)
            if style != .mini {
                Rectangle().fill(preset.accent).frame(width: style.titleSize * 1.2, height: 1).opacity(0.8)
            }
            authorText.multilineTextAlignment(.center)
            Spacer(minLength: 0)
            colophon
        }
        .padding(style.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if style != .mini {
                Rectangle().strokeBorder(preset.ink.opacity(0.40), lineWidth: 0.75).padding(inset)
                Rectangle().strokeBorder(preset.ink.opacity(0.18), lineWidth: 0.5).padding(inset + 3)
            }
        }
    }

    private var banded: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: geometry.size.height * 0.14)
                VStack(alignment: .leading, spacing: style.padding * 0.35) {
                    titleText.multilineTextAlignment(.leading)
                    authorText
                }
                .foregroundStyle(preset.cloth)
                .padding(.horizontal, style.padding)
                .padding(.vertical, style.padding * 0.78)
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

    static func displayTitle(_ title: String) -> String {
        for separator in [": ", "; "] {
            if let range = title.range(of: separator), title.distance(from: title.startIndex, to: range.lowerBound) >= 4 {
                return String(title[..<range.lowerBound])
            }
        }
        return title
    }
}

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
            context.stroke(path, with: .color(color.opacity(0.025)), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

struct CoverPreset {
    let shared: SharedCoverCloth

    var clothHex: UInt32 { shared.clothHex }
    var cloth: Color { .hex(shared.clothHex) }
    var ink: Color { .hex(shared.inkHex) }
    var accent: Color { .hex(shared.accentHex) }
    var layout: SharedCoverCloth.Layout { shared.layout }

    static let all: [CoverPreset] = SharedCoverCloth.all.map(CoverPreset.init)

    static func preset(for index: Int) -> CoverPreset {
        CoverPreset(shared: SharedCoverCloth.preset(for: index))
    }

    static func preset(forTitle title: String) -> CoverPreset {
        CoverPreset(shared: SharedCoverCloth.preset(forTitle: title))
    }
}

// MARK: - The ribbon

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
    func coverRibbon(_ visible: Bool, length: CGFloat = 16, width: CGFloat = 7) -> some View {
        overlay(alignment: .bottomTrailing) {
            if visible {
                Ribbon()
                    .frame(width: width, height: length)
                    .shadow(color: .black.opacity(0.22), radius: 1.5, y: 1)
                    .offset(x: -width * 2.2, y: length * 0.72)
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - The egg

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

nonisolated final class CoverImageCache: @unchecked Sendable {
    static let shared = CoverImageCache()
    private let cache = NSCache<NSString, CGImage>()
    private let textPages = NSCache<NSString, NSNumber>()

    private init() {
        cache.countLimit = 600
    }

    func invalidate() {
        cache.removeAllObjects()
        textPages.removeAllObjects()
    }

    func isTextPage(_ image: CGImage, at url: URL) async -> Bool {
        let key = url.path as NSString
        if let cached = textPages.object(forKey: key) { return cached.boolValue }
        let verdict = await Self.evaluateTextPage(image)
        textPages.setObject(NSNumber(value: verdict), forKey: key)
        return verdict
    }

    func image(for url: URL, maxPixelSize: Int) async -> CGImage? {
        let key = "\(url.path)@\(maxPixelSize)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image = await Self.decodeThumbnail(at: url, maxPixelSize: maxPixelSize)
        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    @concurrent
    private static func evaluateTextPage(_ image: CGImage) async -> Bool {
        CoverRenderer.looksLikeTextPage(image)
    }

    @concurrent
    private static func decodeThumbnail(at url: URL, maxPixelSize: Int) async -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
