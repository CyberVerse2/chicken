import Foundation
import Testing
@testable import ChickenKit

struct CoreHardeningTests {
    @Test func zipLookupIsCaseInsensitiveAndHandlesMissingEntries() throws {
        let url = try Fixtures.zip([
            "mimetype": Data("application/epub+zip".utf8),
            "OEBPS/Text/Chapter1.xhtml": Data("<p>Hello</p>".utf8),
        ])
        let archive = try ZipArchive(url: url)
        #expect(archive.entry("oebps/text/chapter1.xhtml") != nil)
        #expect(throws: ZipArchive.ZipError.missingEntry("missing.txt")) {
            try archive.data(for: "missing.txt")
        }
    }

    @Test func zipRejectsCorruptZip64Locator() {
        var bytes = Data(repeating: 0, count: 64)
        let eocd = 42
        bytes[eocd] = 0x50
        bytes[eocd + 1] = 0x4B
        bytes[eocd + 2] = 0x05
        bytes[eocd + 3] = 0x06
        bytes[eocd + 10] = 0xFF
        bytes[eocd + 11] = 0xFF
        bytes[eocd + 16] = 0xFF
        bytes[eocd + 17] = 0xFF
        bytes[eocd + 18] = 0xFF
        bytes[eocd + 19] = 0xFF
        #expect(throws: ZipArchive.ZipError.corrupt) {
            try ZipArchive(data: bytes)
        }
    }

    @Test func htmlTextDecodesUppercaseHexAndPreservesUnknownEntities() {
        #expect(HTMLText.decodeEntities("&#X2014; &euro; &deg; &unknownEntity;") == "\u{2014} \u{20AC} \u{00B0} &unknownEntity;")
        #expect(HTMLText.numericEntities(in: "a &nbsp; &notAnEntity; b", dropUnknown: true) == "a &#160;  b")
    }

    @Test func epubCombinedDocumentUsesRelativeResourcePaths() throws {
        let cache = try Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: cache) }
        let publication = try EPUBPublication.prepare(bookAt: try Fixtures.sampleEPUB(), cacheDirectory: cache)
        let html = try String(contentsOf: publication.documentURL, encoding: .utf8)

        #expect(!html.contains("file://"))
        #expect(html.contains(#"src="OEBPS/Images/front.jpg""#))
        #expect(html.contains(#"href="OEBPS/Styles/book.css""#))
        #expect(html.contains(#"data-chicken-target-chapter="1""#))
    }

    @Test func discoveryDoesNotPenalizeBooksContainingNegativeSubstrings() {
        let information = BookDiscovery.score(
            url: URL(fileURLWithPath: "/Users/reader/Downloads/The Information.pdf"),
            format: .pdf,
            fileSize: 3_500_000,
            metadata: DocumentMetadata(title: "The Information", author: "James Gleick", pageCount: 540)
        )
        let taxForm = BookDiscovery.score(
            url: URL(fileURLWithPath: "/Users/reader/Downloads/tax-form-2026.pdf"),
            format: .pdf,
            fileSize: 90_000,
            metadata: DocumentMetadata(pageCount: 2)
        )
        #expect(information >= 70)
        #expect(taxForm < 25)
    }

    @Test func bookImporterImportsEPUBAndRejectsCorruptFile() throws {
        let root = try Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = LibraryPaths(root: root)

        let epubURL = try Fixtures.sampleEPUB()
        let imported = try BookImporter.importFile(at: epubURL, paths: paths)
        #expect(imported.format == .epub)
        #expect(imported.title == "The Quiet Room")
        #expect(imported.metadata.author == "Ada Writer")
        #expect(FileManager.default.fileExists(atPath: paths.bookFile(named: imported.storedFileName).path))

        let badURL = root.appendingPathComponent("broken.epub")
        try Data("not an epub".utf8).write(to: badURL)
        #expect(throws: BookImportError.unreadableFile("broken.epub")) {
            try BookImporter.importFile(at: badURL, paths: paths)
        }
    }

    @Test func deepLinksSupportHighlightsAndTextLocationsRoundTrip() {
        let id = UUID()
        #expect(ChickenLink.destination(for: ChickenLink.highlight(id)) == .highlight(id))
        let textLoc = TextLocation(progression: 0.37)
        #expect(TextLocation.decode(textLoc.encoded) == textLoc)
        #expect(EPUBLocation.decode(textLoc.encoded) == nil)
        #expect(ReadingEstimate.duration(forPages: 0) == "under 1 min")
        #expect(ReadingEstimate.duration(forPages: 10) == "13 min")
        #expect(ReadingEstimate.duration(forPages: 48) == "1 hr")
    }

    @Test func sharedThemeTokensResolveAllThemes() {
        #expect(SharedThemeTokens.forName("paper") == .paper)
        #expect(SharedThemeTokens.forName("sepia") == .sepia)
        #expect(SharedThemeTokens.forName("ink") == .ink)
        #expect(SharedThemeTokens.forName(nil) == .paper)
        #expect(SharedCoverCloth.preset(for: -1) == SharedCoverCloth.all.last)
    }

    @Test func readingPaceCalibrationClampsAndBlends() {
        let faster = ReadingEstimate.calibratedMinutesPerPage(previous: 1.25, observedPages: 4, elapsedSeconds: 180)
        #expect(faster < 1.25)
        #expect(faster >= ReadingEstimate.paceRange.lowerBound)
        let ignoredOutlier = ReadingEstimate.calibratedMinutesPerPage(previous: 1.25, observedPages: 10, elapsedSeconds: 15)
        #expect(ignoredOutlier == 1.25)
        #expect(ReadingEstimate.duration(forPages: 10, minutesPerPage: 2.0) == "20 min")
    }
}
