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
    /// Seconds read on each of the last seven days, oldest first, today last.
    /// Optional so snapshots written by older builds still decode.
    public let lastSevenDays: [Int]?
    /// Books finished this calendar year, and the year's goal.
    public let finishedThisYear: Int?
    public let annualGoal: Int?
    /// The chapter you're in, when known.
    public let chapter: String?
    /// The day the snapshot was written, so a widget showing it the next
    /// morning knows "today" has started over.
    public let day: Date?

    public init(
        currentBook: CurrentBook?, secondsToday: Int, dailyGoalMinutes: Int, theme: String,
        lastSevenDays: [Int]? = nil, finishedThisYear: Int? = nil, annualGoal: Int? = nil, chapter: String? = nil,
        day: Date? = nil
    ) {
        self.currentBook = currentBook
        self.secondsToday = secondsToday
        self.dailyGoalMinutes = dailyGoalMinutes
        self.theme = theme
        self.lastSevenDays = lastSevenDays
        self.finishedThisYear = finishedThisYear
        self.annualGoal = annualGoal
        self.chapter = chapter
        self.day = day
    }

    /// Seconds read on each of the seven days ending on `date`, oldest
    /// first, with today's minutes zeroed when the snapshot is from an
    /// earlier day.
    public func week(endingOn date: Date, calendar: Calendar = .current) -> [Int] {
        let days = lastSevenDays ?? Array(repeating: 0, count: 6) + [secondsToday]
        guard let written = day else { return days }
        let shift = calendar.dateComponents([.day], from: calendar.startOfDay(for: written), to: calendar.startOfDay(for: date)).day ?? 0
        guard shift > 0 else { return days }
        return Array((days + Array(repeating: 0, count: min(shift, 7))).suffix(7))
    }

    /// Today's seconds, or zero when the snapshot is from an earlier day.
    public func secondsToday(on date: Date, calendar: Calendar = .current) -> Int {
        guard let written = day else { return secondsToday }
        return calendar.isDate(written, inSameDayAs: date) ? secondsToday : 0
    }

    public static let appGroupIdentifier = "group.cyberverse.Chicken"
    public static let widgetKind = "ChickenContinueReading"

    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    static var snapshotURL: URL? { containerURL?.appendingPathComponent("widget-snapshot.json") }
    public static var coverURL: URL? { containerURL?.appendingPathComponent("widget-cover.jpg") }

    public static func load() -> WidgetSnapshot? {
        guard let url = snapshotURL else { return nil }
        var loadedData: Data?
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinatorError) { readURL in
            loadedData = try? Data(contentsOf: readURL)
        }
        if let coordinatorError {
            ChickenLog.widgets.error("Failed to coordinate widget snapshot read: \(coordinatorError.localizedDescription, privacy: .public)")
        }
        guard let data = loadedData else { return nil }
        do {
            return try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        } catch {
            ChickenLog.widgets.error("Failed to decode widget snapshot: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    public func save(coverJPEG: Data?) {
        guard let url = Self.snapshotURL else { return }
        let data: Data
        do {
            data = try JSONEncoder().encode(self)
        } catch {
            ChickenLog.widgets.error("Failed to encode widget snapshot: \(error.localizedDescription, privacy: .public)")
            return
        }
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatorError) { writeURL in
            do {
                try data.write(to: writeURL, options: .atomic)
            } catch {
                ChickenLog.widgets.error("Failed to write widget snapshot: \(error.localizedDescription, privacy: .public)")
            }
            if let coverURL = Self.coverURL {
                if let coverJPEG {
                    do {
                        try coverJPEG.write(to: coverURL, options: .atomic)
                    } catch {
                        ChickenLog.widgets.error("Failed to write widget cover: \(error.localizedDescription, privacy: .public)")
                    }
                } else {
                    try? FileManager.default.removeItem(at: coverURL)
                }
            }
        }
        if let coordinatorError {
            ChickenLog.widgets.error("Failed to coordinate widget snapshot write: \(coordinatorError.localizedDescription, privacy: .public)")
        }
    }
}

/// `chicken://` deep links shared by the app, widget, and intents.
public enum ChickenLink {
    public static let scheme = "chicken"

    public static func book(_ id: UUID) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "book"
        components.path = "/\(id.uuidString)"
        return components.url ?? URL(fileURLWithPath: "/")
    }

    public static func highlight(_ id: UUID) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "highlight"
        components.path = "/\(id.uuidString)"
        return components.url ?? URL(fileURLWithPath: "/")
    }

    public static let continueReading: URL = {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "continue"
        return components.url ?? URL(fileURLWithPath: "/")
    }()

    public enum Destination: Equatable, Sendable {
        case book(UUID)
        case highlight(UUID)
        case continueReading
    }

    public static func destination(for url: URL) -> Destination? {
        guard url.scheme == scheme else { return nil }
        switch url.host() {
        case "book":
            return url.pathComponents.dropFirst().first.flatMap(UUID.init(uuidString:)).map(Destination.book)
        case "highlight":
            return url.pathComponents.dropFirst().first.flatMap(UUID.init(uuidString:)).map(Destination.highlight)
        case "continue":
            return .continueReading
        default:
            return nil
        }
    }
}
