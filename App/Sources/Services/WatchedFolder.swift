import ChickenKit
import Foundation

/// A folder the user has shared with Chicken for discovering books. Stored as
/// a security-scoped bookmark so access survives relaunches inside the App
/// Store sandbox. Device-local by nature, so it lives in a small JSON file
/// beside the library rather than in the (eventually synced) database.
nonisolated struct WatchedFolder: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var path: String
    var bookmark: Data
    let addedAt: Date

    init?(url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let bookmark = try? url.bookmarkData(options: Self.creationOptions, includingResourceValuesForKeys: nil, relativeTo: nil) else {
            return nil
        }
        id = UUID()
        name = FileManager.default.displayName(atPath: url.path)
        path = url.path
        self.bookmark = bookmark
        addedAt = Date()
    }

    /// Resolves the bookmark and opens its security scope. The caller must
    /// balance with `stopAccessingSecurityScopedResource()`.
    func startAccessing() -> URL? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: Self.resolutionOptions, relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return nil
        }
        return url.startAccessingSecurityScopedResource() ? url : nil
    }

    var isReachable: Bool {
        guard let url = startAccessing() else { return false }
        url.stopAccessingSecurityScopedResource()
        return true
    }

    #if os(macOS)
    private static let creationOptions: URL.BookmarkCreationOptions = [.withSecurityScope, .securityScopeAllowOnlyReadAccess]
    private static let resolutionOptions: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI]
    #else
    private static let creationOptions: URL.BookmarkCreationOptions = []
    private static let resolutionOptions: URL.BookmarkResolutionOptions = [.withoutUI]
    #endif

    // MARK: Persistence

    private static func fileURL(in paths: LibraryPaths) -> URL {
        paths.root.appendingPathComponent("folders.json")
    }

    static func load(from paths: LibraryPaths) -> [WatchedFolder] {
        guard let data = try? Data(contentsOf: fileURL(in: paths)) else { return [] }
        return (try? JSONDecoder().decode([WatchedFolder].self, from: data)) ?? []
    }

    static func save(_ folders: [WatchedFolder], to paths: LibraryPaths) {
        guard let data = try? JSONEncoder().encode(folders) else { return }
        try? data.write(to: fileURL(in: paths), options: .atomic)
    }
}
