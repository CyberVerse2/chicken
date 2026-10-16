import Foundation
import SwiftData

/// Collections: groups of books you make. Removing a collection leaves its
/// books in the library.
extension LibraryStore {
    func allCollections() -> [BookCollection] {
        let collections = (try? context.fetch(FetchDescriptor<BookCollection>())) ?? []
        return collections.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// A new collection holding `books`, or the existing one with that name.
    @discardableResult
    func createCollection(named name: String, with books: [Book] = []) -> BookCollection? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let collection = allCollections().first { $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame } ?? {
            let collection = BookCollection(name: trimmed)
            context.insert(collection)
            return collection
        }()
        add(books, to: collection)
        return collection
    }

    func rename(_ collection: BookCollection, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != collection.name else { return }
        collection.name = trimmed
        save()
    }

    func delete(_ collection: BookCollection) {
        context.delete(collection)
        save()
    }

    func add(_ books: [Book], to collection: BookCollection) {
        let present = Set((collection.books ?? []).map(\.id))
        let adding = books.filter { !present.contains($0.id) }
        guard !adding.isEmpty else { return }
        if collection.books == nil { collection.books = [] }
        collection.books?.append(contentsOf: adding)
        save()
    }

    func remove(_ books: [Book], from collection: BookCollection) {
        let ids = Set(books.map(\.id))
        collection.books?.removeAll { ids.contains($0.id) }
        save()
    }

    func contains(_ book: Book, in collection: BookCollection) -> Bool {
        (collection.books ?? []).contains { $0.id == book.id }
    }

    /// Two devices can each make "To read" before syncing; fold them into
    /// the one made first, so every device keeps the same one.
    func mergeDuplicateCollections() {
        let groups = Dictionary(grouping: allCollections()) { $0.name.lowercased() }.values.filter { $0.count > 1 }
        guard !groups.isEmpty else { return }
        for group in groups {
            let ordered = group.sorted {
                $0.createdAt != $1.createdAt ? $0.createdAt < $1.createdAt : $0.id.uuidString < $1.id.uuidString
            }
            guard let keeper = ordered.first else { continue }
            for duplicate in ordered.dropFirst() {
                add(duplicate.books ?? [], to: keeper)
                context.delete(duplicate)
            }
        }
        save()
    }
}
