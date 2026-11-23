import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
#if canImport(Vision)
import Vision
#endif

/// Produces cover JPEGs for imported books using only CoreGraphics and
/// ImageIO, so the same code runs on macOS, iPadOS, and iOS.
public enum CoverRenderer {
    static let maxPixelSize = 1080
    public static let previewMaxPixelSize = 180
    private static let sRGBColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp"]

    public static func generateCover(for url: URL, format: BookFormat, id: UUID, in directory: URL) -> String? {
        renderCover(for: url, format: format, id: id, in: directory, detectText: false)?.fileName
    }

    public static func renderCover(
        for url: URL,
        format: BookFormat,
        id: UUID,
        in directory: URL,
        detectText: Bool = true
    ) -> RenderedCover? {
        switch format {
        case .pdf:
            return renderPDFCover(for: url, id: id, in: directory, detectText: detectText)
        case .epub:
            guard let archive = try? ZipArchive(url: url) else { return nil }
            let package = try? EPUBPackage(archive: archive)
            return renderEPUBCover(archive: archive, package: package, id: id, in: directory, detectText: detectText)
        case .text, .document, .physical, .unknown:
            return nil
        }
    }

    static func generatePDFCover(for url: URL, id: UUID, in directory: URL) -> String? {
        renderPDFCover(for: url, id: id, in: directory, detectText: false)?.fileName
    }

    public static func renderPDFCover(
        for url: URL,
        id: UUID,
        in directory: URL,
        detectText: Bool = true
    ) -> RenderedCover? {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let image = renderFirstPDFPage(url) else { return nil }
        let ratio = Double(image.width) / Double(max(image.height, 1))
        guard ratio <= CoverMetrics.maxAcceptedAspectRatio, !looksLikeTextPage(image) else { return nil }
        return persistRenderedCover(image, origin: .pdfFirstPage, id: id, in: directory, detectText: detectText)
    }

    static func generateEPUBCover(archive: ZipArchive, package: EPUBPackage?, id: UUID, in directory: URL) -> String? {
        renderEPUBCover(archive: archive, package: package, id: id, in: directory, detectText: false)?.fileName
    }

    public static func renderEPUBCover(
        archive: ZipArchive,
        package: EPUBPackage?,
        id: UUID,
        in directory: URL,
        detectText: Bool = true
    ) -> RenderedCover? {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard
            let data = epubCoverData(archive: archive, package: package),
            let image = downsampledImage(from: data)
        else { return nil }
        let ratio = Double(image.width) / Double(max(image.height, 1))
        guard ratio <= CoverMetrics.maxAcceptedAspectRatio else { return nil }
        return persistRenderedCover(image, origin: .embedded, id: id, in: directory, detectText: detectText)
    }

    public static func saveCover(from imageData: Data, id: UUID, in directory: URL, minWidth: Int = 80, minHeight: Int = 80) -> String? {
        saveRenderedCover(
            from: imageData,
            origin: .catalog,
            id: id,
            in: directory,
            minWidth: minWidth,
            minHeight: minHeight,
            allowLandscape: false,
            detectText: false
        )?.fileName
    }

    public static func saveRenderedCover(
        from imageData: Data,
        origin: CoverOrigin,
        id: UUID,
        in directory: URL,
        minWidth: Int = 80,
        minHeight: Int = 80,
        allowLandscape: Bool = false,
        detectText: Bool = true
    ) -> RenderedCover? {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let image = downsampledImage(from: imageData), image.width >= minWidth, image.height >= minHeight else {
            return nil
        }
        let ratio = Double(image.width) / Double(max(image.height, 1))
        if !allowLandscape && ratio > CoverMetrics.maxAcceptedAspectRatio {
            return nil
        }
        return persistRenderedCover(image, origin: origin, id: id, in: directory, detectText: detectText)
    }

    public static func inspectCover(
        at url: URL,
        origin: CoverOrigin,
        detectText: Bool = true
    ) -> (metrics: CoverMetrics, previewData: Data?, looksLikeTextPage: Bool)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions(maxPixelSize: 600))
        else { return nil }
        let isTextPage = origin == .pdfFirstPage ? looksLikeTextPage(image) : false
        let metrics = analyze(image, detectText: detectText)
        let preview = isTextPage ? nil : previewJPEG(from: image)
        return (metrics, preview, isTextPage)
    }

    public static func analyze(_ image: CGImage, detectText: Bool = true) -> CoverMetrics {
        CoverMetrics(
            pixelWidth: image.width,
            pixelHeight: image.height,
            dominantColor: averageColor(of: image),
            hasLegibleText: detectText ? detectLegibleText(in: image) : nil
        )
    }

    public static func averageColor(of image: CGImage) -> CoverColor {
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: sRGBColorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return CoverColor(red: 0.2, green: 0.2, blue: 0.2) }
        return CoverColor(
            red: Double(pixel[0]) / 255.0,
            green: Double(pixel[1]) / 255.0,
            blue: Double(pixel[2]) / 255.0
        )
    }

    public static func detectLegibleText(in image: CGImage) -> Bool? {
        #if canImport(Vision)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.035
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
            let observations = request.results ?? []
            return observations.contains { observation in
                guard let candidate = observation.topCandidates(1).first,
                      candidate.confidence >= 0.35
                else { return false }
                let alphanumerics = candidate.string.unicodeScalars.filter(CharacterSet.alphanumerics.contains)
                return alphanumerics.count >= 2
            }
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    public static func previewJPEG(from image: CGImage) -> Data? {
        let longest = max(image.width, image.height)
        guard longest > 0 else { return nil }
        let targetImage: CGImage
        if longest > previewMaxPixelSize {
            let scale = Double(previewMaxPixelSize) / Double(longest)
            let w = max(1, Int((Double(image.width) * scale).rounded()))
            let h = max(1, Int((Double(image.height) * scale).rounded()))
            guard let context = CGContext(
                data: nil,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: sRGBColorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return nil }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            guard let scaled = context.makeImage() else { return nil }
            targetImage = scaled
        } else {
            targetImage = image
        }
        guard let data = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, targetImage, [kCGImageDestinationLossyCompressionQuality: 0.55] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private static func persistRenderedCover(
        _ image: CGImage,
        origin: CoverOrigin,
        id: UUID,
        in directory: URL,
        detectText: Bool
    ) -> RenderedCover? {
        guard let fileName = writeCompressedCover(image, id: id, in: directory) else { return nil }
        let metrics = analyze(image, detectText: detectText)
        let preview = previewJPEG(from: image)
        return RenderedCover(fileName: fileName, origin: origin, metrics: metrics, previewData: preview)
    }

    private static func writeCompressedCover(_ image: CGImage, id: UUID, in directory: URL) -> String? {
        let jpgName = "\(id.uuidString).jpg"
        let jpgURL = directory.appendingPathComponent(jpgName)
        return writeJPEG(image, to: jpgURL, quality: 0.78) ? jpgName : nil
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
