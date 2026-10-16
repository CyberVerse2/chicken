import ChickenKit
import Foundation
import SwiftData
#if os(iOS)
import UIKit
#endif

/// Where each device is in each book. The book itself keeps whichever
/// position was saved last; these rows let a device notice that another
/// read further since it last had the book open.
extension LibraryStore {
    static var deviceKind: String {
        #if os(macOS)
        "Mac"
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
    }

    /// This device's row for the book, if it has read it.
    func position(for book: Book) -> ReadingPosition? {
        let device = preferences.deviceID
        return book.positions?.first { $0.device == device }
    }

    func recordPosition(for book: Book, progress: Double, location: String?) {
        let position = self.position(for: book) ?? {
            let position = ReadingPosition(device: preferences.deviceID, deviceKind: Self.deviceKind)
            position.book = book
            context.insert(position)
            return position
        }()
        position.progress = progress
        if let location {
            position.location = location
            position.chapterIndex = Self.chapterIndex(of: location)
        }
        position.updatedAt = Date()
    }

    /// Another device that read the book after `since` and got further than
    /// `progress`: the most recent if there are several.
    func furtherPosition(for book: Book, than progress: Double, since: Date) -> ReadingPosition? {
        let device = preferences.deviceID
        return (book.positions ?? [])
            .filter { $0.device != device && $0.updatedAt > since && $0.progress > progress + 0.005 && $0.location != nil }
            .max { $0.updatedAt < $1.updatedAt }
    }

    static func chapterIndex(of location: String) -> Int {
        EPUBLocation.decode(location)?.spineIndex ?? PDFLocation.decode(location)?.chapterIndex ?? 0
    }
}
