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
                  "slug": "project-hail-mary",
                  "title": "Project Hail Mary",
                  "description": "<p>Ryland Grace is the sole survivor.</p>",
                  "release_year": 2021,
                  "rating": 4.62,
                  "ratings_count": 12450,
                  "cached_tags": {
                    "Genre": [{ "tag": "Science Fiction" }, { "tag": "Space Opera" }],
                    "Mood": [{ "tag": "Hopeful" }, { "tag": "Tense" }]
                  },
                  "book_series": [{ "position": 1, "series": { "name": "Hail Mary" } }],
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
        #expect(first.seriesName == "Hail Mary")
        #expect(first.seriesPosition == 1)
        #expect(first.seriesBadgeText == "Hail Mary · Book 1")
        #expect(first.genres == ["Science Fiction", "Space Opera"])
        #expect(first.moods == ["Hopeful", "Tense"])
        #expect(first.rating == 4.62)
        #expect(first.ratingsCount == 12450)
        #expect(first.hardcoverBookID == 77)
        #expect(first.catalogSlug == "project-hail-mary")
        #expect(first.catalogURL?.absoluteString == "https://hardcover.app/books/project-hail-mary")

        let searchJSON = """
        {
          "data": {
            "search": {
              "results": {
                "hits": [
                  {
                    "document": {
                      "id": 99,
                      "slug": "dune",
                      "title": "Dune",
                      "author_names": ["Frank Herbert"],
                      "description": "A desert planet story.",
                      "pages": 688,
                      "isbns": ["9780441172719"],
                      "release_year": 1965,
                      "rating": 4.35,
                      "ratings_count": 50000,
                      "genres": ["Science Fiction", "Classics"],
                      "featured_series": { "position": 1, "series": { "name": "Dune Chronicles" } },
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
        #expect(searchMatches[0].seriesName == "Dune Chronicles")
        #expect(searchMatches[0].seriesPosition == 1)
        #expect(searchMatches[0].genres == ["Science Fiction", "Classics"])
        #expect(searchMatches[0].catalogURL?.absoluteString == "https://hardcover.app/books/dune")

        let booksJSON = """
        {
          "data": {
            "books": [
              {
                "id": 101,
                "slug": "piranesi",
                "title": "Piranesi",
                "description": "The beauty of the House is immeasurable.",
                "pages": 245,
                "release_year": 2020,
                "rating": 4.28,
                "ratings_count": 9000,
                "cached_tags": { "Genre": [{ "tag": "Fantasy" }] },
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
        #expect(bookMatches[0].genres == ["Fantasy"])
        #expect(bookMatches[0].rating == 4.28)
        #expect(bookMatches[0].hardcoverBookID == 101)
    }

    @Test func decodesOpenLibrarySearchWorkDetailsAndFiltersNoise() {
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
              "first_publish_year": 1969,
              "subject": [
                "Protected DAISY",
                "Accessible book",
                "Science fiction",
                "FICTION / Science Fiction / General",
                "Hugo Award Winner",
                "Feminist fiction"
              ],
              "ratings_average": 4.15,
              "ratings_count": 320
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
        #expect(match.genres.contains("Science Fiction"))
        #expect(!match.genres.contains(where: { $0.localizedCaseInsensitiveContains("DAISY") }))
        #expect(!match.genres.contains(where: { $0.localizedCaseInsensitiveContains("Accessible") }))
        #expect(!match.genres.contains(where: { $0.localizedCaseInsensitiveContains("Award") }))
        #expect(match.rating == 4.15)
        #expect(match.ratingsCount == 320)
        #expect(match.catalogURL?.absoluteString == "https://openlibrary.org/works/OL45804W")

        let stringDesc = #"{"description": "Winter on Gethen."}"#
        let objDesc = #"{"description": {"type": "/type/text", "value": "<p>Winter on Gethen.</p>"}, "subjects": ["Accessible book", "Speculative Fiction"]}"#
        #expect(BookCatalogClient.parseOpenLibraryWorkDescription(Data(stringDesc.utf8)) == "Winter on Gethen.")
        let details = BookCatalogClient.parseOpenLibraryWorkDetails(Data(objDesc.utf8))
        #expect(details.description == "Winter on Gethen.")
        #expect(details.genres == ["Speculative Fiction"])
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

    @Test func physicalFormatBehavesAsPrintBook() {
        #expect(BookFormat.physical.rawValue == "physical")
        #expect(BookFormat.physical.label == "Print")
        #expect(BookFormat.physical.isPhysical)
        #expect(!BookFormat.epub.isPhysical)
        #expect(!BookFormat.physical.supportsFlowModes)
        #expect(!BookImporter.canOpen(URL(fileURLWithPath: "/nonexistent"), format: .physical))
    }
}
