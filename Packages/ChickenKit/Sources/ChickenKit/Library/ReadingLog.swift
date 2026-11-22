import Foundation

/// Calendar arithmetic for the daily reading-time log, keyed by `yyyy-MM-dd`.
public enum ReadingLog {
    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    /// A year of reading from `(dayKey, seconds)` rows, which may hold several
    /// rows per day (one per device). Rows from other years are ignored.
    public struct Year: Equatable, Sendable {
        public var totalSeconds = 0
        /// Seconds per month, January first.
        public var monthSeconds = Array(repeating: 0, count: 12)
        /// Days with any reading.
        public var daysRead = 0

        public init() {}
    }

    public static func year(_ year: Int, from rows: [(dayKey: String, seconds: Int)]) -> Year {
        let prefix = String(format: "%04d-", year)
        var byDay: [String: Int] = [:]
        for row in rows where row.dayKey.hasPrefix(prefix) && row.seconds > 0 {
            byDay[row.dayKey, default: 0] += row.seconds
        }
        var result = Year()
        for (key, seconds) in byDay {
            let month = Int(key.dropFirst(5).prefix(2)) ?? 0
            guard (1...12).contains(month) else { continue }
            result.monthSeconds[month - 1] += seconds
            result.totalSeconds += seconds
            result.daysRead += 1
        }
        return result
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
    public static let paceRange: ClosedRange<Double> = 0.6...4.5

    public static func duration(forPages pages: Int, minutesPerPage: Double = Self.minutesPerPage) -> String {
        if pages <= 0 { return "under 1 min" }
        let clampedPace = min(max(minutesPerPage, paceRange.lowerBound), paceRange.upperBound)
        let minutes = max(1, Int((Double(pages) * clampedPace).rounded(.up)))
        if minutes < 60 { return minutes == 1 ? "1 min" : "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 { return hours == 1 ? "1 hr" : "\(hours) hr" }
        return "\(hours)h \(remainder)m"
    }

    public static func calibratedMinutesPerPage(
        previous: Double,
        observedPages: Double,
        elapsedSeconds: Double
    ) -> Double {
        guard observedPages >= 1.5, elapsedSeconds >= 30, elapsedSeconds <= 1800 else {
            return min(max(previous, paceRange.lowerBound), paceRange.upperBound)
        }
        let sample = (elapsedSeconds / 60.0) / observedPages
        guard sample >= 0.35, sample <= 8.0 else {
            return min(max(previous, paceRange.lowerBound), paceRange.upperBound)
        }
        let clampedSample = min(max(sample, paceRange.lowerBound), paceRange.upperBound)
        let blended = previous * 0.78 + clampedSample * 0.22
        return min(max(blended, paceRange.lowerBound), paceRange.upperBound)
    }
}
