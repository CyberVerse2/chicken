import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Produces cover JPEGs for imported books using only CoreGraphics and
/// ImageIO, so the same code runs on macOS, iPadOS, and iOS.
public enum CoverRenderer {
    /// Longest edge of a stored cover, in pixels.
    static let maxPixelSize = 1200

    /// Writes `<id>.jpg` into `directory` and returns the file name, or nil
    /// when the document has no usable cover (the UI then draws a stylized one).
    public static func generateCover(for url: URL, format: BookFormat, id: UUID, in directory: URL) -> String? {
        let name = "\(id.uuidString).jpg"
        let destination = directory.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        switch format {
        case .pdf:
            guard let image = renderFirstPDFPage(url) else { return nil }
            return writeJPEG(image, to: destination) ? name : nil
        case .epub:
            guard
                let archive = try? ZipArchive(url: url),
                let data = epubCoverData(archive: archive),
                let image = downsampledImage(from: data)
            else { return nil }
            return writeJPEG(image, to: destination) ? name : nil
        case .text, .document, .unknown:
            return nil
        }
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
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.concatenate(page.getDrawingTransform(.cropBox, rect: rect, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        return context.makeImage()
    }

    // MARK: EPUB

    static func epubCoverData(archive: ZipArchive) -> Data? {
        if let package = try? EPUBPackage(archive: archive),
           let path = package.coverImagePath,
           let data = try? archive.data(for: path) {
            return data
        }
        return bestImageGuess(in: archive)
    }

    /// Fallback for EPUBs that don't declare a cover: prefer portrait images
    /// with cover-like names, then the largest image.
    private static func bestImageGuess(in archive: ZipArchive) -> Data? {
        let candidates = archive.entries
            .filter { $0.path.range(of: #"\.(jpe?g|png|webp)$"#, options: [.regularExpression, .caseInsensitive]) != nil }
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

    static func downsampledImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    @discardableResult
    public static func writeJPEG(_ image: CGImage, to url: URL, quality: Double = 0.84) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            return false
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }

    /// Small JPEG used by the widget snapshot.
    public static func thumbnailJPEG(from url: URL, maxPixelSize: Int = 360) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard
            let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
            let data = CFDataCreateMutable(nil, 0),
            let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
