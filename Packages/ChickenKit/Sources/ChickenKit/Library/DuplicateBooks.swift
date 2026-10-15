import Foundation

/// Finds the same file imported on more than one device. With iCloud sync
/// both copies arrive in every library; each device groups them the same
/// way and keeps the same one, so their merges agree without talking.
public enum DuplicateBooks {
    public struct Entry: Hashable, Sendable {
        public let id: UUID
        public let fileName: String
        public let fileSize: Int64
        public let importedAt: Date

        public init(id: UUID, fileName: String, fileSize: Int64, importedAt: Date) {
            self.id = id
            self.fileName = fileName
            self.fileSize = fileSize
            self.importedAt = importedAt
        }
    }

    /// Groups of two or more entries with the same file name and size, each
    /// ordered keeper first: the earliest import, ties broken by id.
    public static func groups(in entries: [Entry]) -> [[Entry]] {
        struct Key: Hashable {
            let name: String
            let size: Int64
        }
        let grouped = Dictionary(grouping: entries.filter { $0.fileSize > 0 && !$0.fileName.isEmpty }) {
            Key(name: $0.fileName, size: $0.fileSize)
        }
        return grouped.values
            .filter { $0.count > 1 }
            .map { $0.sorted(by: keeperFirst) }
            .sorted { keeperFirst($0[0], $1[0]) }
    }

    private static func keeperFirst(_ lhs: Entry, _ rhs: Entry) -> Bool {
        if lhs.importedAt != rhs.importedAt { return lhs.importedAt < rhs.importedAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
