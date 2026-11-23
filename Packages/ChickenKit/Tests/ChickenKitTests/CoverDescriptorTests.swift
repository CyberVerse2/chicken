import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Testing
import UniformTypeIdentifiers
@testable import ChickenKit

struct CoverDescriptorTests {
    @Test func coverOriginUpgradeHierarchyRespectsCustomCovers() {
        #expect(CoverOrigin.none.canBeReplacedAutomatically(by: .pdfFirstPage))
        #expect(CoverOrigin.pdfFirstPage.canBeReplacedAutomatically(by: .embedded))
        #expect(CoverOrigin.embedded.canBeReplacedAutomatically(by: .catalog))
        #expect(!CoverOrigin.catalog.canBeReplacedAutomatically(by: .embedded))
        #expect(!CoverOrigin.custom.canBeReplacedAutomatically(by: .catalog))
        #expect(!CoverOrigin.custom.canBeReplacedAutomatically(by: .custom))
        #expect(!CoverOrigin.none.isTrustedArtwork)
        #expect(!CoverOrigin.pdfFirstPage.isTrustedArtwork)
        #expect(CoverOrigin.embedded.isTrustedArtwork)
        #expect(CoverOrigin.catalog.isTrustedArtwork)
        #expect(CoverOrigin.custom.isTrustedArtwork)
    }

    @Test func aspectRatioClampingGuardsInvalidAndLandscapeRatios() {
        let fallback = CoverMetrics.defaultAspectRatio
        #expect(abs(CoverMetrics.clampedAspectRatio(nil) - fallback) < 0.0001)
        #expect(abs(CoverMetrics.clampedAspectRatio(0) - fallback) < 0.0001)
        #expect(abs(CoverMetrics.clampedAspectRatio(-0.5) - fallback) < 0.0001)
        #expect(abs(CoverMetrics.clampedAspectRatio(.nan) - fallback) < 0.0001)
        #expect(abs(CoverMetrics.clampedAspectRatio(1.4) - fallback) < 0.0001)
        #expect(abs(CoverMetrics.clampedAspectRatio(0.40) - CoverMetrics.shelfAspectRange.lowerBound) < 0.0001)
        #expect(abs(CoverMetrics.clampedAspectRatio(0.95) - CoverMetrics.shelfAspectRange.upperBound) < 0.0001)
        #expect(abs(CoverMetrics.clampedAspectRatio(0.72) - 0.72) < 0.0001)
    }

    @Test func saveRenderedCoverRejectsLandscapeAndGeneratesMetricsAndPreview() throws {
        let dir = try Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let landscapeData = try pngData(width: 400, height: 240, red: 0.8, green: 0.2, blue: 0.2)
        let rejected = CoverRenderer.saveRenderedCover(
            from: landscapeData,
            origin: .catalog,
            id: UUID(),
            in: dir,
            allowLandscape: false,
            detectText: false
        )
        #expect(rejected == nil)

        let portraitData = try pngData(width: 360, height: 480, red: 0.2, green: 0.45, blue: 0.75)
        let rendered = try #require(CoverRenderer.saveRenderedCover(
            from: portraitData,
            origin: .catalog,
            id: UUID(),
            in: dir,
            allowLandscape: false,
            detectText: false
        ))
        #expect(rendered.origin == .catalog)
        #expect(rendered.metrics.pixelWidth == 360)
        #expect(rendered.metrics.pixelHeight == 480)
        #expect(abs(rendered.metrics.aspectRatio - 0.75) < 0.01)

        let preview = try #require(rendered.previewData)
        #expect(!preview.isEmpty)
        let previewSource = try #require(CGImageSourceCreateWithData(preview as CFData, nil))
        let previewImage = try #require(CGImageSourceCreateImageAtIndex(previewSource, 0, nil))
        #expect(max(previewImage.width, previewImage.height) <= CoverRenderer.previewMaxPixelSize)
    }

    @Test func renderPDFCoverRejectsTextPagesAndLandscapePages() throws {
        let dir = try Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let landscapePDF = dir.appendingPathComponent("landscape.pdf")
        try writePDF(to: landscapePDF, bounds: CGRect(x: 0, y: 0, width: 792, height: 500)) { ctx in
            ctx.setFillColor(CGColor(red: 0.15, green: 0.25, blue: 0.45, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 792, height: 500))
        }
        #expect(CoverRenderer.renderPDFCover(for: landscapePDF, id: UUID(), in: dir, detectText: false) == nil)

        let textPDF = dir.appendingPathComponent("text.pdf")
        try writePDF(to: textPDF, bounds: CGRect(x: 0, y: 0, width: 612, height: 792)) { ctx in
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 612, height: 792))
            ctx.setFillColor(CGColor(gray: 0.15, alpha: 1))
            for y in stride(from: 80, to: 710, by: 24) {
                for x in stride(from: 70, to: 520, by: 40) {
                    ctx.fill(CGRect(x: x, y: y, width: 28, height: 2))
                }
            }
        }
        #expect(CoverRenderer.renderPDFCover(for: textPDF, id: UUID(), in: dir, detectText: false) == nil)
    }

    private func pngData(width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat) throws -> Data {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        ctx.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(ctx.makeImage())
        let data = try #require(CFDataCreateMutable(nil, 0))
        let dest = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
        return data as Data
    }

    private func writePDF(to url: URL, bounds: CGRect, draw: (CGContext) -> Void) throws {
        var box = bounds
        let consumer = try #require(CGDataConsumer(url: url as CFURL))
        let ctx = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        ctx.beginPDFPage(nil)
        draw(ctx)
        ctx.endPDFPage()
        ctx.closePDF()
    }
}
