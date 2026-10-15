import Foundation
#if os(macOS)
import Security
#endif

/// The Books and Covers folders inside Chicken's iCloud container. iCloud
/// uploads what's put here and makes it appear on every device signed into
/// the same Apple Account; other devices download a book only when it's
/// opened. Everything here touches the file system and may block, so call
/// it off the main actor unless noted.
nonisolated struct CloudFolders: Sendable, Equatable {
    static let containerID = "iCloud.cyberverse.Chicken"

    let root: URL

    /// Whether this build is signed with Chicken's iCloud container. CloudKit
    /// stops the app if it's asked for a container the build isn't entitled
    /// to, as in an unsigned Mac build, so sync is only set up when it is.
    /// iOS apps can't run unsigned, and can't read their own entitlements.
    static let isEnabledInThisBuild: Bool = {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-container-identifiers" as CFString, nil)
        return (value as? [String])?.contains(containerID) == true
        #else
        return true
        #endif
    }()

    var books: URL { root.appendingPathComponent("Books", isDirectory: true) }
    var covers: URL { root.appendingPathComponent("Covers", isDirectory: true) }

    /// Nil when iCloud is signed out or turned off for Chicken. Blocks while
    /// the container is set up on first use.
    static func resolve() -> CloudFolders? {
        let fileManager = FileManager.default
        guard let container = fileManager.url(forUbiquityContainerIdentifier: containerID) else { return nil }
        // Development builds sync with CloudKit's development environment;
        // their files get a folder of their own to match. Neither lives in
        // Documents, so iCloud Drive doesn't show them as user files.
        #if DEBUG
        let folders = CloudFolders(root: container.appendingPathComponent("Development", isDirectory: true))
        #else
        let folders = CloudFolders(root: container.appendingPathComponent("Library", isDirectory: true))
        #endif
        do {
            for directory in [folders.root, folders.books, folders.covers] {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        } catch {
            return nil
        }
        return folders
    }

    /// Moves the files named in `names` from the local `source` folder into
    /// `destination` in iCloud. A file iCloud already has (same name) is a
    /// leftover copy and is removed. Returns the names of the files moved.
    @discardableResult
    static func moveIntoICloud(from source: URL, to destination: URL, only names: Set<String>) -> Set<String> {
        let fileManager = FileManager.default
        let files = (try? fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        var moved = Set<String>()
        for file in files where names.contains(file.lastPathComponent) {
            let target = destination.appendingPathComponent(file.lastPathComponent)
            if exists(target) {
                try? fileManager.removeItem(at: file)
                continue
            }
            do {
                try fileManager.setUbiquitous(true, itemAt: file, destinationURL: target)
                moved.insert(file.lastPathComponent)
            } catch {
                continue
            }
        }
        return moved
    }

    /// Whether iCloud knows the file, downloaded or not. Older iCloud
    /// clients leave a hidden `.name.icloud` stand-in for files not yet
    /// downloaded.
    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path) || FileManager.default.fileExists(atPath: placeholder(for: url).path)
    }

    /// Whether the file can be read now without waiting on the network.
    /// Cheap enough to call on the main actor.
    static func isDownloaded(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        guard values?.isUbiquitousItem == true else {
            return FileManager.default.fileExists(atPath: url.path)
        }
        return values?.ubiquitousItemDownloadingStatus == .current
    }

    /// Downloads the file if it isn't on this device yet, returning once it
    /// can be read. Throws if iCloud reports an error (offline, say) or the
    /// file is gone; stops when the calling task is cancelled.
    static func download(_ url: URL) async throws {
        if isDownloaded(url) { return }
        guard exists(url) else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
        while !isDownloaded(url) {
            try await Task.sleep(for: .milliseconds(400))
            let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingErrorKey])
            if let error = values?.ubiquitousItemDownloadingError { throw error }
            if !exists(url) { throw CocoaError(.fileNoSuchFile) }
        }
    }

    /// Deletes a file, coordinating with iCloud so the deletion reaches
    /// other devices.
    static func remove(_ url: URL) {
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { url in
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func placeholder(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).icloud")
    }
}
