import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Produces cover JPEGs for imported books using only CoreGraphics and
/// ImageIO, so the same code runs on macOS, iPadOS, and iOS.
public enum CoverRenderer {
    /// Longest edge of a stored cover, in pixels.
    static let maxPixelSize = 720
    private static let sRGBColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp"]

    /// Writes `<id>.jpg` into `directory` and returns the file name, or nil
    /// when the document has no usable cover (the UI then draws a stylized one).
    public static func generateCover(for url: URL, format: BookFormat, id: UUID, in directory: URL) -> String? {
        switch format {
        case .pdf:
            return generatePDFCover(for: url, id: id, in: directory)
        case .epub:
            guard let archive = try? ZipArchive(url: url) else { return nil }
            let package = try? EPUBPackage(archive: archive)
            return generateEPUBCover(archive: archive, package: package, id: id, in: directory)
        case .text, .document, .unknown:
            return nil
        }
    }

    static func generatePDFCover(for url: URL, id: UUID, in directory: URL) -> String? {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let image = renderFirstPDFPage(url), !looksLikeTextPage(image) else { return nil }
        return writeCompressedCover(image, id: id, in: directory)
    }

    static func generateEPUBCover(archive: ZipArchive, package: EPUBPackage?, id: UUID, in directory: URL) -> String? {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard
            let data = epubCoverData(archive: archive, package: package),
            let image = downsampledImage(from: data)
        else { return nil }
        return writeCompressedCover(image, id: id, in: directory)
    }

    public static func saveCover(from imageData: Data, id: UUID, in directory: URL, minWidth: Int = 80, minHeight: Int = 80) -> String? {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let image = downsampledImage(from: imageData), image.width >= minWidth, image.height >= minHeight else {
            return nil
        }
        return writeCompressedCover(image, id: id, in: directory)
    }

    private static func writeCompressedCover(_ image: CGImage, id: UUID, in directory: URL) -> String? {
        let jpgName = "\(id.uuidString).jpg"
        let jpgURL = directory.appendingPathComponent(jpgName)
        return writeJPEG(image, to: jpgURL, quality: 0.72) ? jpgName : nil
    }

    // MARK: PDF

    static func renderFirstPDFPage(_ url: URL, width: CGFloat = 640) -> CGImage? {
        guard let document = CGPDFDocument(url as CFURL), let page = document.page(at: 1) else { return nil }
        let box = page.getBoxRect(.cropBox)
        guard box.width > 0, box.height > 0 else { return nil }

        let scale = width / box.width
        let height = min(max(box.height * scale, 1), width * 2)
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        guard let context = CGContext(
            data: nil,
            width: Int(width),
            height: Int(height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: sRGBColorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.concatenate(page.getDrawingTransform(.cropBox, rect: rect, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        return context.makeImage()
    }

    /// True when a rendered page is a page of text rather than a cover:
    /// nearly all pale, colorless paper, with no color and almost no heavy
    /// ink. At this size body text blurs to light grey, while covers keep
    /// some color, large dark type, or a picture. Tuned to keep minimal
    /// covers (a pencil, an apple, a bold title) and to err toward keeping.
    public static func looksLikeTextPage(_ image: CGImage) -> Bool {
        let width = 96
        let height = 144
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: sRGBColorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return false }

        var paper = 0
        var ink = 0
        var color = 0
        pixels.withUnsafeBufferPointer { buffer in
            var index = 0
            while index < buffer.count {
                let red = Int(buffer[index])
                let green = Int(buffer[index + 1])
                let blue = Int(buffer[index + 2])
                let luminance = (54 * red + 183 * green + 19 * blue) >> 8
                let chroma = max(red, max(green, blue)) - min(red, min(green, blue))
                if luminance > 204 && chroma < 31 { paper += 1 }
                if luminance < 77 { ink += 1 }
                if chroma > 51 { color += 1 }
                index += 4
            }
        }
        let total = width * height
        return paper * 100 >= total * 85
            && ink * 10000 < total * 25
            && color * 1000 < total * 3
    }

    // MARK: EPUB

    static func epubCoverData(archive: ZipArchive, package: EPUBPackage? = nil) -> Data? {
        if let resolved = package ?? (try? EPUBPackage(archive: archive)),
           let path = resolved.coverImagePath,
           let data = try? archive.data(for: path) {
            return data
        }
        return bestImageGuess(in: archive)
    }

    /// Fallback for EPUBs that don't declare a cover: prefer portrait images
    /// with cover-like names, then the largest image.
    private static func bestImageGuess(in archive: ZipArchive) -> Data? {
        let candidates = archive.entries
            .filter { imageExtensions.contains(($0.path as NSString).pathExtension.lowercased()) }
            .prefix(48)

        var best: (score: Double, data: Data)?
        for entry in candidates {
            guard
                let data = try? archive.data(for: entry),
                let source = CGImageSourceCreateWithData(data as CFData, nil),
                let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
                let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
                width >= 80, height >= 120
            else { continue }

            let aspect = height / max(width, 1)
            let portraitScore = (1.15...1.9).contains(aspect) ? 2_000_000.0 : 0
            let lower = entry.path.lowercased()
            let nameScore: Double
            if lower.contains("cover") || lower.contains("_cv") || lower.contains("-cv") {
                nameScore = 3_000_000
            } else if ["cvi", "cvt", "front", "ttlpg", "title"].contains(where: lower.contains) {
                nameScore = 1_500_000
            } else {
                nameScore = 0
            }
            let score = nameScore + portraitScore + min(width * height, 2_000_000)
            if score > (best?.score ?? -1) { best = (score, data) }
        }
        return best?.data
    }

    // MARK: Encoding

    private static func thumbnailOptions(maxPixelSize: Int) -> CFDictionary {
        [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
    }

    static func downsampledImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions(maxPixelSize: maxPixelSize))
    }

    private static func writeImage(_ image: CGImage, to url: URL, type: String, quality: Double) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil) else {
            return false
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }

    @discardableResult
    public static func writeJPEG(_ image: CGImage, to url: URL, quality: Double = 0.84) -> Bool {
        writeImage(image, to: url, type: UTType.jpeg.identifier, quality: quality)
    }

    /// Small JPEG used by the widget snapshot.
    public static func thumbnailJPEG(from url: URL, maxPixelSize: Int = 360) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        guard
            let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions(maxPixelSize: maxPixelSize)),
            let data = CFDataCreateMutable(nil, 0),
            let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
