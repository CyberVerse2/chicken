import Foundation
import Testing
@testable import ChickenKit

struct DuplicateBooksTests {
    private let early = Date(timeIntervalSince1970: 1_000)
    private let late = Date(timeIntervalSince1970: 2_000)

    private func entry(_ id: String, _ name: String, size: Int64 = 100, at date: Date) -> DuplicateBooks.Entry {
        DuplicateBooks.Entry(id: UUID(uuidString: id)!, fileName: name, fileSize: size, importedAt: date)
    }

    @Test func groupsTheSameFileImportedTwice() {
        let mac = entry("00000000-0000-0000-0000-00000000000B", "Dune.epub", at: late)
        let iPad = entry("00000000-0000-0000-0000-00000000000A", "Dune.epub", at: early)
        let other = entry("00000000-0000-0000-0000-00000000000C", "Emma.epub", at: early)

        let groups = DuplicateBooks.groups(in: [mac, other, iPad])
        #expect(groups == [[iPad, mac]])
    }

    @Test func keepsTheEarliestImportAndBreaksTiesByID() {
        let first = entry("00000000-0000-0000-0000-000000000001", "Dune.epub", at: early)
        let second = entry("00000000-0000-0000-0000-000000000002", "Dune.epub", at: early)
        #expect(DuplicateBooks.groups(in: [second, first]) == [[first, second]])
        #expect(DuplicateBooks.groups(in: [first, second]) == [[first, second]])
    }

    @Test func sameNameDifferentSizeIsADifferentBook() {
        let one = entry("00000000-0000-0000-0000-000000000001", "Notes.pdf", size: 100, at: early)
        let two = entry("00000000-0000-0000-0000-000000000002", "Notes.pdf", size: 200, at: late)
        #expect(DuplicateBooks.groups(in: [one, two]).isEmpty)
    }

    @Test func ignoresBooksWithoutAKnownSize() {
        let one = entry("00000000-0000-0000-0000-000000000001", "Notes.pdf", size: 0, at: early)
        let two = entry("00000000-0000-0000-0000-000000000002", "Notes.pdf", size: 0, at: late)
        #expect(DuplicateBooks.groups(in: [one, two]).isEmpty)
    }
}
