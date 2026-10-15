import Foundation

/// Calendar arithmetic for the daily reading-time log, keyed by `yyyy-MM-dd`.
public enum ReadingLog {
    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    public static func date(forDayKey key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// Splits a reading session into per-day seconds so a session that
    /// crosses midnight credits each day honestly.
    public static func split(from start: Date, to end: Date, calendar: Calendar = .current) -> [(dayKey: String, seconds: Int)] {
        guard end > start else { return [] }
        var result: [(String, Int)] = []
        var cursor = start
        while cursor < end {
            let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: cursor)) ?? end
            let chunkEnd = min(nextDay, end)
            let seconds = Int(chunkEnd.timeIntervalSince(cursor))
            if seconds > 0 { result.append((dayKey(for: cursor, calendar: calendar), seconds)) }
            cursor = chunkEnd
        }
        return result
    }

    /// Start-of-day dates for the last `count` days, oldest first, ending today.
    public static func recentDays(_ count: Int, endingAt date: Date = Date(), calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: date)
        return (0..<count).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }
}

/// Reading-time estimate used by the reader and library ("12 min left").
public enum ReadingEstimate {
    public static let minutesPerPage = 1.25

    public static func duration(forPages pages: Int) -> String {
        if pages <= 0 { return "under 1 min" }
        let minutes = max(1, Int((Double(pages) * minutesPerPage).rounded(.up)))
        if minutes < 60 { return minutes == 1 ? "1 min" : "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 { return hours == 1 ? "1 hr" : "\(hours) hr" }
        return "\(hours)h \(remainder)m"
    }
}
