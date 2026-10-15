import Foundation

/// What the Home Screen / desktop widget shows. The app writes it into the
/// shared App Group container whenever reading state changes; the widget
/// only reads it, so it never needs to open the library database.
public struct WidgetSnapshot: Codable, Sendable, Hashable {
    public struct CurrentBook: Codable, Sendable, Hashable {
        public let id: UUID
        public let title: String
        public let author: String
        public let progress: Double
        public let coverTintIndex: Int
        public let hasCover: Bool

        public init(id: UUID, title: String, author: String, progress: Double, coverTintIndex: Int, hasCover: Bool) {
            self.id = id
            self.title = title
            self.author = author
            self.progress = progress
            self.coverTintIndex = coverTintIndex
            self.hasCover = hasCover
        }
    }

    public let currentBook: CurrentBook?
    public let secondsToday: Int
    public let dailyGoalMinutes: Int
    public let theme: String
    public let updatedAt: Date

    public init(currentBook: CurrentBook?, secondsToday: Int, dailyGoalMinutes: Int, theme: String, updatedAt: Date = Date()) {
        self.currentBook = currentBook
        self.secondsToday = secondsToday
        self.dailyGoalMinutes = dailyGoalMinutes
        self.theme = theme
        self.updatedAt = updatedAt
    }

    public static let appGroupIdentifier = "group.cyberverse.Chicken"
    public static let widgetKind = "ChickenContinueReading"

    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    static var snapshotURL: URL? { containerURL?.appendingPathComponent("widget-snapshot.json") }
    public static var coverURL: URL? { containerURL?.appendingPathComponent("widget-cover.jpg") }

    public static func load() -> WidgetSnapshot? {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    public func save(coverJPEG: Data?) {
        guard let url = Self.snapshotURL, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
        if let coverURL = Self.coverURL {
            if let coverJPEG {
                try? coverJPEG.write(to: coverURL, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: coverURL)
            }
        }
    }
}

/// `chicken://` deep links shared by the app, widget, and intents.
public enum ChickenLink {
    public static let scheme = "chicken"

    public static func book(_ id: UUID) -> URL {
        URL(string: "\(scheme)://book/\(id.uuidString)")!
    }

    public static let continueReading = URL(string: "\(scheme)://continue")!

    public enum Destination: Equatable, Sendable {
        case book(UUID)
        case continueReading
    }

    public static func destination(for url: URL) -> Destination? {
        guard url.scheme == scheme else { return nil }
        switch url.host() {
        case "book":
            return url.pathComponents.dropFirst().first.flatMap(UUID.init(uuidString:)).map(Destination.book)
        case "continue":
            return .continueReading
        default:
            return nil
        }
    }
}
