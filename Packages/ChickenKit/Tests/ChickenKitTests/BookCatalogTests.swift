import ChickenKit
import Foundation
import Testing

struct BookCatalogTests {
    @Test func isbnExtractorValidatesAndNormalizes() {
        #expect(ISBNExtractor.normalize("urn:isbn:978-0-593-13520-4") == "9780593135204")
        #expect(ISBNExtractor.normalize("ISBN: 0-306-40615-2") == "0306406152")
        #expect(ISBNExtractor.normalize("043942089X") == "043942089X")
        #expect(ISBNExtractor.normalize("9780593135209") == nil)
        #expect(ISBNExtractor.normalize("1234567890") == nil)
    }

    @Test func isbnExtractorFindsPreferredISBN13FromText() {
        let noisy = """
        Copyright 2021 by Author Name.
        Print edition ISBN 0-306-40615-2.
        Electronic ISBN-13: 978-0-593-13520-4.
        """
        #expect(ISBNExtractor.extract(from: noisy) == "9780593135204")
        #expect(ISBNExtractor.extract(from: "Paperback 043942089x.") == "043942089X")
        #expect(ISBNExtractor.extract(from: "Order 9780000000000 only") == nil)
    }

    @Test func decodesHardcoverEditionsSearchAndBooksJSON() {
        let editionsJSON = """
        {
          "data": {
            "editions": [
              {
                "id": 42,
                "title": "Project Hail Mary",
                "isbn_13": "9780593135204",
                "pages": 496,
                "release_date": "2021-05-04",
                "publisher": { "name": "Ballantine Books" },
                "language": { "code2": "EN" },
                "image": { "url": "https://assets.hardcover.app/cover.jpg" },
                "book": {
                  "id": 77,
                  "title": "Project Hail Mary",
                  "description": "<p>Ryland Grace is the sole survivor.</p>",
                  "release_year": 2021,
                  "contributions": [{ "author": { "name": "Andy Weir" } }]
                }
              }
            ]
          }
        }
        """
        let editionMatches = BookCatalogClient.parseHardcoverEditionsJSON(Data(editionsJSON.utf8))
        #expect(editionMatches.count == 1)
        let first = editionMatches[0]
        #expect(first.source == .hardcover)
        #expect(first.title == "Project Hail Mary")
        #expect(first.authorLine == "Andy Weir")
        #expect(first.publisher == "Ballantine Books")
        #expect(first.language == "en")
        #expect(first.pageCount == 496)
        #expect(first.isbn == "9780593135204")
        #expect(first.releaseYear == 2021)
        #expect(first.summary == "Ryland Grace is the sole survivor.")
        #expect(first.coverURL?.absoluteString == "https://assets.hardcover.app/cover.jpg")

        let searchJSON = """
        {
          "data": {
            "search": {
              "results": {
                "hits": [
                  {
                    "document": {
                      "id": 99,
                      "title": "Dune",
                      "author_names": ["Frank Herbert"],
                      "description": "A desert planet story.",
                      "pages": 688,
                      "isbns": ["9780441172719"],
                      "release_year": 1965,
                      "image": { "url": "https://assets.hardcover.app/dune.jpg" }
                    }
                  }
                ]
              }
            }
          }
        }
        """
        let searchMatches = BookCatalogClient.parseHardcoverSearchJSON(Data(searchJSON.utf8))
        #expect(searchMatches.count == 1)
        #expect(searchMatches[0].title == "Dune")
        #expect(searchMatches[0].authorLine == "Frank Herbert")
        #expect(searchMatches[0].isbn == "9780441172719")

        let booksJSON = """
        {
          "data": {
            "books": [
              {
                "id": 101,
                "title": "Piranesi",
                "description": "The beauty of the House is immeasurable.",
                "pages": 245,
                "release_year": 2020,
                "contributions": [{ "author": { "name": "Susanna Clarke" } }],
                "editions": [{
                  "isbn_13": "9781635575637",
                  "publisher": { "name": "Bloomsbury" },
                  "language": { "code2": "en" },
                  "image": { "url": "https://assets.hardcover.app/piranesi.jpg" }
                }]
              }
            ]
          }
        }
        """
        let bookMatches = BookCatalogClient.parseHardcoverBooksJSON(Data(booksJSON.utf8))
        #expect(bookMatches.count == 1)
        #expect(bookMatches[0].publisher == "Bloomsbury")
        #expect(bookMatches[0].isbn == "9781635575637")
    }

    @Test func decodesOpenLibrarySearchAndWorkDescriptions() {
        let searchJSON = """
        {
          "docs": [
            {
              "key": "/works/OL45804W",
              "title": "The Left Hand of Darkness",
              "author_name": ["Ursula K. Le Guin"],
              "publisher": ["Ace Books"],
              "language": ["eng"],
              "number_of_pages_median": 304,
              "isbn": ["0441478123", "9780441478125"],
              "cover_i": 8231990,
              "first_publish_year": 1969
            }
          ]
        }
        """
        let matches = BookCatalogClient.parseOpenLibrarySearchJSON(Data(searchJSON.utf8))
        #expect(matches.count == 1)
        let match = matches[0]
        #expect(match.source == .openLibrary)
        #expect(match.workKey == "/works/OL45804W")
        #expect(match.language == "en")
        #expect(match.pageCount == 304)
        #expect(match.isbn == "9780441478125")
        #expect(match.coverURL?.absoluteString == "https://covers.openlibrary.org/b/id/8231990-L.jpg?default=false")

        let stringDesc = #"{"description": "Winter on Gethen."}"#
        let objDesc = #"{"description": {"type": "/type/text", "value": "<p>Winter on Gethen.</p>"}}"#
        #expect(BookCatalogClient.parseOpenLibraryWorkDescription(Data(stringDesc.utf8)) == "Winter on Gethen.")
        #expect(BookCatalogClient.parseOpenLibraryWorkDescription(Data(objDesc.utf8)) == "Winter on Gethen.")
    }

    @Test func epubPackageExtractsISBNFromIdentifier() throws {
        let customOPF = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>Test Book</dc:title>
            <dc:creator>Test Author</dc:creator>
            <dc:identifier id="id">urn:isbn:978-0-593-13520-4</dc:identifier>
          </metadata>
          <manifest>
            <item id="c1" href="Text/chapter%201.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="c1"/>
          </spine>
        </package>
        """
        let url = try Fixtures.sampleEPUB(extraFiles: ["OEBPS/content.opf": Data(customOPF.utf8)])
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let archive = try ZipArchive(url: url)
        let package = try EPUBPackage(archive: archive)
        #expect(package.metadata.isbn == "9780593135204")
    }
}
