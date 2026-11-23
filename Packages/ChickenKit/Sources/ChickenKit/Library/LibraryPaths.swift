import Foundation
#if os(macOS)
import Security
#endif

public struct LibraryPaths: Sendable {
    public let root: URL
    public let syncsWithICloud: Bool

    public init(root: URL, syncsWithICloud: Bool = false) {
        self.root = root
        self.syncsWithICloud = syncsWithICloud
    }

    public static let usesDevelopmentCloudEnvironment: Bool = {
        #if os(macOS)
        if let task = SecTaskCreateFromSelf(nil) {
            if let env = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-container-environment" as CFString, nil) as? String {
                return env.caseInsensitiveCompare("Production") != .orderedSame
            }
            if let aps = SecTaskCopyValueForEntitlement(task, "com.apple.developer.aps-environment" as CFString, nil) as? String {
                return aps.caseInsensitiveCompare("development") == .orderedSame
            }
        }
        #if DEBUG
        return true
        #else
        return false
        #endif
        #elseif targetEnvironment(simulator)
        #if DEBUG
        return true
        #else
        return false
        #endif
        #else
        if let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
           let data = try? Data(contentsOf: url),
           let isDev = isDevelopmentProvisioningProfile(data) {
            return isDev
        }
        return false
        #endif
    }()

    public static func isDevelopmentProvisioningProfile(_ data: Data) -> Bool? {
        let startMarker = Data("<?xml".utf8)
        let endMarker = Data("</plist>".utf8)
        guard let start = data.range(of: startMarker)?.lowerBound,
              let end = data.range(of: endMarker, in: start..<data.endIndex)?.upperBound,
              let plist = try? PropertyListSerialization.propertyList(from: data[start..<end], format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any] else {
            return nil
        }
        if let aps = entitlements["aps-environment"] as? String {
            return aps.caseInsensitiveCompare("development") == .orderedSame
        }
        if let getTaskAllow = entitlements["get-task-allow"] as? Bool {
            return getTaskAllow
        }
        return false
    }

    public static func standard(fileManager: FileManager = .default) -> LibraryPaths {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["CHICKEN_LIBRARY_ROOT"], !override.isEmpty {
            return LibraryPaths(root: URL(fileURLWithPath: override, isDirectory: true))
        }
        #endif
        let folder = usesDevelopmentCloudEnvironment ? "Chicken Development" : "Chicken"
        return LibraryPaths(root: base.appendingPathComponent(folder, isDirectory: true), syncsWithICloud: true)
    }

    public var books: URL { root.appendingPathComponent("Books", isDirectory: true) }
    public var covers: URL { root.appendingPathComponent("Covers", isDirectory: true) }
    public var store: URL { root.appendingPathComponent("Library.store") }

    public var epubCache: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("Chicken/EPUBCache", isDirectory: true)
    }

    public func bookFile(named storedFileName: String) -> URL {
        books.appendingPathComponent(storedFileName)
    }

    public func coverFile(named coverImageName: String) -> URL {
        covers.appendingPathComponent(coverImageName)
    }

    public func createDirectories() throws {
        let fileManager = FileManager.default
        for directory in [root, books, covers] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
