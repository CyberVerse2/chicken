#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation

/// The reading session shown in the Dynamic Island and on the Lock Screen
/// while a book is open in Chicken. The app starts it when a book opens,
/// updates it as you read, and ends it when the book closes; the widget
/// extension draws it.
public struct ReadingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        /// Chapter you're in, if the book has chapters.
        public var chapter: String?
        /// 0...1 through the book.
        public var progress: Double
        /// Minutes read today, across every book.
        public var minutesToday: Int
        public var goalMinutes: Int
        /// True while Chicken is reading the book aloud.
        public var isReadingAloud: Bool

        public init(chapter: String?, progress: Double, minutesToday: Int, goalMinutes: Int, isReadingAloud: Bool) {
            self.chapter = chapter
            self.progress = progress
            self.minutesToday = minutesToday
            self.goalMinutes = goalMinutes
            self.isReadingAloud = isReadingAloud
        }

        public var goalFraction: Double {
            goalMinutes > 0 ? min(1, Double(minutesToday) / Double(goalMinutes)) : 0
        }
    }

    public let bookID: UUID
    public let title: String
    public let author: String
    /// Index into the cloth-cover palette, for books without cover art and
    /// for the Lock Screen banner's colour.
    public let coverTintIndex: Int
    /// The reading theme's name (paper, sepia, ink).
    public let theme: String

    public init(bookID: UUID, title: String, author: String, coverTintIndex: Int, theme: String) {
        self.bookID = bookID
        self.title = title
        self.author = author
        self.coverTintIndex = coverTintIndex
        self.theme = theme
    }

    /// A small copy of the book's cover in the shared App Group container,
    /// which the extension reads for the island and the Lock Screen.
    public static func coverURL(for bookID: UUID) -> URL? {
        WidgetSnapshot.containerURL?.appendingPathComponent("activity-cover-\(bookID.uuidString).jpg")
    }
}
#endif
