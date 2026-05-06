import Foundation

enum ChickenImportError: LocalizedError {
    case unsupportedFile(URL)
    case copyFailed(URL)
    case unreadableFile(URL)

    var errorDescription: String? {
        switch self {
        case .unsupportedFile(let url):
            return "\(url.lastPathComponent) is not a supported reading format yet."
        case .copyFailed(let url):
            return "Chicken could not copy \(url.lastPathComponent) into the local library."
        case .unreadableFile(let url):
            return "\(url.lastPathComponent) looks like a supported format, but Chicken could not read it."
        }
    }
}
