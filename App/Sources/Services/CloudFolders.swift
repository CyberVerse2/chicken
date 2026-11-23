import ChickenKit
import Foundation
import os
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
        #elseif targetEnvironment(simulator)
        return FileManager.default.ubiquityIdentityToken != nil
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
        let folderName = LibraryPaths.usesDevelopmentCloudEnvironment ? "Development" : "Library"
        let folders = CloudFolders(root: container.appendingPathComponent(folderName, isDirectory: true))
        do {
            for directory in [folders.root, folders.books, folders.covers] {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        } catch {
            ChickenLog.sync.error("Failed to create iCloud directories: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        return folders
    }

    @concurrent
    static func resolveAsync() async -> CloudFolders? {
        resolve()
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
                ChickenLog.sync.error("Failed to move \(file.lastPathComponent, privacy: .private) to iCloud: \(error.localizedDescription, privacy: .public)")
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
        var attempts = 0
        while !isDownloaded(url) {
            let delayMs = attempts < 20 ? 100 : 250
            attempts += 1
            try await Task.sleep(for: .milliseconds(delayMs))
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
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                ChickenLog.sync.error("Failed to delete file: \(error.localizedDescription, privacy: .public)")
            }
        }
        if let coordinationError {
            ChickenLog.sync.error("File coordination delete failed: \(coordinationError.localizedDescription, privacy: .public)")
        }
    }

    @concurrent
    static func removeAll(_ urls: [URL]) async {
        urls.forEach(remove)
    }

    @concurrent
    static func startDownloadingAll(_ urls: [URL]) async {
        for url in urls {
            do {
                try FileManager.default.startDownloadingUbiquitousItem(at: url)
            } catch {
                ChickenLog.sync.error("Failed to start download: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    @concurrent
    static func evictAll(_ urls: [URL]) async {
        for url in urls {
            do {
                try FileManager.default.evictUbiquitousItem(at: url)
            } catch {
                ChickenLog.sync.error("Failed to evict download: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func placeholder(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).icloud")
    }
}
