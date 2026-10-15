import Foundation

/// The result of copying a file into the managed library. A plain value so it
/// can be produced off the main actor and turned into a model object there.
public struct ImportedBook: Sendable, Hashable {
    public let id: UUID
    public let title: String
    public let format: BookFormat
    public let originalFileName: String
    public let storedFileName: String
    public let fileSize: Int64
    public let metadata: DocumentMetadata
    public let coverImageName: String?
}

public enum BookImportError: LocalizedError, Equatable {
    case unsupportedFile(String)
    case copyFailed(String)
    case unreadableFile(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFile(let name):
            return "\(name) is not a format Chicken can read yet."
        case .copyFailed(let name):
            return "Chicken could not copy \(name) into your library."
        case .unreadableFile(let name):
            return "\(name) looks like a supported format, but Chicken could not open it. It may be damaged or DRM-protected."
        }
    }
}

public enum BookImporter {
    /// Copies `url` into the library, validates it opens, and extracts
    /// metadata and a cover. Handles security-scoped URLs from file pickers.
    public static func importFile(
        at url: URL,
        knownMetadata: DocumentMetadata? = nil,
        paths: LibraryPaths
    ) throws -> ImportedBook {
        let fileExtension = url.pathExtension.lowercased()
        let name = url.lastPathComponent
        guard BookFormat.importableExtensions.contains(fileExtension) else {
            throw BookImportError.unsupportedFile(name)
        }

        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let fileManager = FileManager.default
        try? paths.createDirectories()
        let id = UUID()
        let storedFileName = "\(id.uuidString).\(fileExtension)"
        let destination = paths.bookFile(named: storedFileName)

        do {
            try fileManager.copyItem(at: url, to: destination)
        } catch {
            throw BookImportError.copyFailed(name)
        }

        let format = BookFormat(fileExtension: fileExtension)
        guard canOpen(destination, format: format) else {
            try? fileManager.removeItem(at: destination)
            throw BookImportError.unreadableFile(name)
        }

        let fresh = DocumentMetadataReader.metadata(for: destination, format: format)
        let metadata = fresh.mergingFallbacks(from: knownMetadata)
        let fileSize = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let cover = CoverRenderer.generateCover(for: destination, format: format, id: id, in: paths.covers)

        return ImportedBook(
            id: id,
            title: metadata.title ?? DocumentMetadataReader.title(fromFileName: url),
            format: format,
            originalFileName: name,
            storedFileName: storedFileName,
            fileSize: fileSize,
            metadata: metadata,
            coverImageName: cover
        )
    }

    public static func canOpen(_ url: URL, format: BookFormat) -> Bool {
        switch format {
        case .pdf:
            return PDFMetadataReader.canOpen(url)
        case .epub:
            guard let archive = try? ZipArchive(url: url) else { return false }
            return (try? EPUBPackage(archive: archive)) != nil
        case .text:
            return FileManager.default.isReadableFile(atPath: url.path)
        case .document, .unknown:
            return false
        }
    }
}
