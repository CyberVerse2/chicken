import Foundation
import Testing
@testable import ChickenKit

struct ZipArchiveTests {
    @Test func readsStoredAndDeflatedEntries() throws {
        let text = String(repeating: "chicken reads quietly. ", count: 400)
        let url = try Fixtures.zip([
            "mimetype": Data("application/epub+zip".utf8),
            "folder/long.txt": Data(text.utf8),
        ])
        let archive = try ZipArchive(url: url)

        #expect(try archive.data(for: "mimetype") == Data("application/epub+zip".utf8))
        let long = try #require(archive.entry("folder/long.txt"))
        #expect(long.compressionMethod == 8)
        #expect(archive.string(for: "folder/long.txt") == text)
    }

    @Test func rejectsNonZipData() {
        #expect(throws: ZipArchive.ZipError.notAZip) {
            try ZipArchive(data: Data("not a zip".utf8))
        }
    }

    @Test func extractionRefusesPathTraversal() throws {
        let root = try Fixtures.temporaryDirectory()
        #expect(ZipArchive.safeDestination(for: "../escape.txt", in: root) == nil)
        #expect(ZipArchive.safeDestination(for: "/etc/passwd", in: root) == nil)
        #expect(ZipArchive.safeDestination(for: "OEBPS/a.xhtml", in: root) != nil)
    }
}

struct EPUBPackageTests {
    @Test func parsesMetadataSpineAndTOC() throws {
        let archive = try ZipArchive(url: try Fixtures.sampleEPUB())
        let package = try EPUBPackage(archive: archive)

        #expect(package.metadata.title == "The Quiet Room")
        #expect(package.metadata.author == "Ada Writer")
        #expect(package.metadata.publisher == "Small & Good Press")
        #expect(package.metadata.summary == "A book about reading.")

        // The CSS itemref is not a readable document and is skipped.
        #expect(package.spine.map(\.path) == ["OEBPS/Text/chapter 1.xhtml", "OEBPS/Text/chapter2.xhtml"])
        #expect(package.spine.map(\.title) == ["One Beginning", "Two"])
        #expect(package.spine.map(\.tocLevel) == [0, 1])
        #expect(package.coverImagePath == "OEBPS/Images/front.jpg")
    }

    @Test func locationHrefMatchesLegacyFormat() throws {
        let package = try EPUBPackage(archive: ZipArchive(url: try Fixtures.sampleEPUB()))
        #expect(package.spine[0].locationHref == "OEBPS/Text/chapter%201.xhtml")
    }

    @Test func fallsBackToNCXWhenNavIsMissing() throws {
        let opf = """
        <package xmlns="http://www.idpf.org/2007/opf" version="2.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Old</dc:title></metadata>
          <manifest>
            <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
            <item id="c1" href="a.html" media-type="application/xhtml+xml"/>
          </manifest>
          <spine toc="ncx"><itemref idref="c1"/></spine>
        </package>
        """
        let ncx = """
        <ncx><navMap><navPoint id="p1"><navLabel><text>Opening</text></navLabel><content src="a.html"/></navPoint></navMap></ncx>
        """
        let url = try Fixtures.zip([
            "mimetype": Data("application/epub+zip".utf8),
            "META-INF/container.xml": Data(#"<container><rootfiles><rootfile full-path="content.opf"/></rootfiles></container>"#.utf8),
            "content.opf": Data(opf.utf8),
            "toc.ncx": Data(ncx.utf8),
            "a.html": Data("<html><body>Hi</body></html>".utf8),
        ])
        let package = try EPUBPackage(archive: ZipArchive(url: url))
        #expect(package.spine.first?.title == "Opening")
        #expect(package.spine.first?.locationHref == "a.html")
    }

    @Test func combinedDocumentRewritesLinks() throws {
        let cache = try Fixtures.temporaryDirectory()
        let publication = try EPUBPublication.prepare(bookAt: try Fixtures.sampleEPUB(), cacheDirectory: cache)
        let html = try String(contentsOf: publication.documentURL, encoding: .utf8)

        #expect(html.contains(#"id="chapter-0" data-chicken-spine-index="0""#))
        #expect(html.contains(#"id="chapter-1" data-chicken-spine-index="1""#))
        // Cross-chapter link becomes an in-page anchor.
        #expect(html.contains(##"href="#part""##))
        // Images and stylesheets point at the unpacked files.
        #expect(html.contains("Images/front.jpg"))
        #expect(html.contains("Styles/book.css"))
        #expect(FileManager.default.fileExists(atPath: publication.rootURL.appendingPathComponent("OEBPS/Text/chapter2.xhtml").path))
    }
}

struct PathAndTextTests {
    @Test func resolvesRelativePaths() {
        #expect(EPUBPath.resolve("../Images/a%20b.png", relativeTo: "OEBPS/Text") == "OEBPS/Images/a b.png")
        #expect(EPUBPath.resolve("./c.xhtml#frag", relativeTo: "") == "c.xhtml")
        #expect(EPUBPath.split("c.xhtml#frag", relativeTo: "X").fragment == "frag")
    }

    @Test func plainTextStripsMarkupAndEntities() {
        #expect(HTMLText.plainText(from: "<p>Fish &amp; chips&nbsp;&#8212; <i>good</i></p>") == "Fish & chips \u{2014} good")
    }
}

struct LibraryLogicTests {
    @Test func splitsSessionsAcrossMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 23, minute: 50)))
        let end = start.addingTimeInterval(20 * 60)
        let chunks = ReadingLog.split(from: start, to: end, calendar: calendar)
        #expect(chunks.map(\.dayKey) == ["2026-03-01", "2026-03-02"])
        #expect(chunks.map(\.seconds) == [600, 600])
    }

    @Test func scoresEPUBsAboveReceipts() {
        let epub = BookDiscovery.score(url: URL(fileURLWithPath: "/Books/novel.epub"), format: .epub, fileSize: 3_000_000, metadata: .empty)
        let receipt = BookDiscovery.score(url: URL(fileURLWithPath: "/Downloads/receipt-0042.pdf"), format: .pdf, fileSize: 40_000, metadata: .empty)
        #expect(epub >= 70)
        #expect(receipt < 25)
    }

    @Test func parsesDeepLinks() {
        let id = UUID()
        #expect(ChickenLink.destination(for: ChickenLink.book(id)) == .book(id))
        #expect(ChickenLink.destination(for: ChickenLink.continueReading) == .continueReading)
        #expect(ChickenLink.destination(for: URL(string: "https://example.com")!) == nil)
    }

    @Test func readerPreferencesSavedBeforeTypefaceStillDecode() throws {
        let json = #"{"theme":"paper","fontSize":18,"lineHeight":1.8,"columnWidth":620,"readingMode":"paged","zenMode":false}"#
        let preferences = try JSONDecoder().decode(ReaderPreferences.self, from: Data(json.utf8))
        #expect(preferences.fontSize == 18)
        #expect(preferences.typeface == nil)

        var updated = preferences
        updated.typeface = "iowan"
        let roundTripped = try JSONDecoder().decode(ReaderPreferences.self, from: JSONEncoder().encode(updated))
        #expect(roundTripped.typeface == "iowan")
    }

    @Test func decodesLegacyLocations() {
        let legacy = #"{"href":"OEBPS\/c01.htm","spineIndex":7,"globalProgression":0.01,"progression":0,"type":"epub","pageNumber":12,"pageWithinSpine":3}"#
        let location = EPUBLocation.decode(legacy)
        #expect(location?.spineIndex == 7)
        #expect(location?.pageNumber == 12)
        #expect(PDFLocation.decode(legacy) == nil)
        #expect(PDFLocation.decode(PDFLocation(pageIndex: 4, chapterIndex: 1).encoded)?.pageIndex == 4)
    }

    @Test func loadsLegacyLibraryFiles() throws {
        let root = try Fixtures.temporaryDirectory()
        let bookID = UUID()
        let catalog = """
        [{"id":"\(bookID.uuidString)","title":"Dictators","author":"Richard Overy","format":"epub",
          "originalFileName":"d.epub","storedFileName":"\(bookID.uuidString).epub","importedAt":799000000,
          "progress":0.42,"lastLocation":null},
         {"id":"broken"}]
        """
        try Data(catalog.utf8).write(to: root.appendingPathComponent("library.json"))
        try Data(#"{"2026-05-07":49848}"#.utf8).write(to: root.appendingPathComponent("reading-log.json"))
        let prefs = #"["\#(bookID.uuidString)",{"fontSize":24,"zenMode":false,"columnWidth":620,"lineHeight":1.78,"readingMode":"spread","theme":"ink"}]"#
        try Data(prefs.utf8).write(to: root.appendingPathComponent("reader-preferences.json"))

        let legacy = try LegacyLibrary.load(from: root)
        #expect(legacy.books.count == 1)
        #expect(legacy.books.first?.progress == 0.42)
        #expect(legacy.readingLog["2026-05-07"] == 49848)
        #expect(legacy.readerPreferences[bookID]?.theme == "ink")
        #expect(legacy.highlights.isEmpty)
    }
}
