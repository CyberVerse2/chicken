import Foundation
import Testing
@testable import ChickenKit

/// Opt-in smoke test against a real library folder:
/// `CHICKEN_REAL_LIBRARY=~/Library/Application\ Support/Chicken swift test`
/// It only reads files; nothing in the library is modified.
struct RealLibraryTests {
    static let root = ProcessInfo.processInfo.environment["CHICKEN_REAL_LIBRARY"].map {
        URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath, isDirectory: true)
    }

    @Test(.enabled(if: root != nil))
    func everyLegacyEPUBStillParses() throws {
        let root = try #require(Self.root)
        let legacy = try LegacyLibrary.load(from: root)
        let books = root.appendingPathComponent("Books")
        let epubs = legacy.books.filter { $0.format == .epub }

        var failures: [String] = []
        var unresolvedLocations: [String] = []
        for book in epubs {
            let url = books.appendingPathComponent(book.storedFileName)
            // Files that aren't ZIPs at all (e.g. a saved web page named
            // .epub) can't be books; the reader shows them as unreadable.
            guard let handle = try? FileHandle(forReadingFrom: url),
                  (try? handle.read(upToCount: 2)) == Data("PK".utf8) else { continue }
            guard let archive = try? ZipArchive(url: url), let package = try? EPUBPackage(archive: archive) else {
                failures.append(book.title)
                continue
            }
            if let location = EPUBLocation.decode(book.lastLocation),
               !package.spine.indices.contains(location.spineIndex) || package.spine[location.spineIndex].locationHref != location.href {
                unresolvedLocations.append(book.title)
            }
        }

        print("Parsed \(epubs.count - failures.count)/\(epubs.count) EPUBs; failures: \(failures)")
        print("Saved positions that no longer resolve: \(unresolvedLocations)")
        #expect(failures.isEmpty)
        #expect(unresolvedLocations.isEmpty)
    }
}
