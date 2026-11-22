import ChickenKit
import Foundation
import SwiftData

/// Active reading time: counted while at least one reader is open and the
/// app is in the foreground, committed to `ReadingDay` rows every 30 seconds.
extension LibraryStore {
    func appDidBecomeActive() {
        isAppActive = true
        if !openBookIDs.isEmpty { resumeReadingSession() }
        recomputeReadingStats()
    }

    func appDidResignActive() {
        isAppActive = false
        pauseReadingSession()
        save()
    }

    func resumeReadingSession() {
        guard isAppActive, !openBookIDs.isEmpty else { return }
        if sessionStart == nil { sessionStart = Date() }
        guard sessionTask == nil else { return }
        sessionTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self else { break }
                self.commitReadingSession(continuing: true)
            }
        }
        recomputeReadingStats()
    }

    func pauseReadingSession() {
        sessionTask?.cancel()
        sessionTask = nil
        commitReadingSession(continuing: false)
    }

    private func commitReadingSession(continuing: Bool) {
        guard let start = sessionStart else { return }
        let now = Date()
        for chunk in ReadingLog.split(from: start, to: now) {
            addReadingSeconds(chunk.seconds, toDay: chunk.dayKey)
        }
        sessionStart = continuing ? now : nil
        save()
        recomputeReadingStats()
        publishWidgetSnapshot()
        #if os(iOS)
        ReadingActivityController.shared.refresh()
        #endif
    }

    func addReadingSeconds(_ seconds: Int, toDay day: String) {
        guard seconds > 0 else { return }
        let device: String? = preferences.deviceID
        var descriptor = FetchDescriptor<ReadingDay>(predicate: #Predicate { $0.day == day && $0.device == device })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            existing.seconds += seconds
        } else {
            context.insert(ReadingDay(day: day, seconds: seconds, device: device))
        }
    }

    func recomputeReadingStats() {
        let days = ReadingLog.recentDays(7)
        let keys = days.map { ReadingLog.dayKey(for: $0) }
        let descriptor = FetchDescriptor<ReadingDay>(predicate: #Predicate { keys.contains($0.day) })
        var secondsByDay: [String: Int] = [:]
        for row in (try? context.fetch(descriptor)) ?? [] {
            secondsByDay[row.day, default: 0] += row.seconds
        }

        let today = Calendar.current.startOfDay(for: Date())
        let live = sessionStart.map { max(0, Int(Date().timeIntervalSince(max($0, today)))) } ?? 0
        let todayKey = ReadingLog.dayKey(for: today)

        lastSevenDays = zip(days, keys).map { day, key in
            DayReading(dayStart: day, seconds: (secondsByDay[key] ?? 0) + (key == todayKey ? live : 0))
        }
        readingSecondsToday = (secondsByDay[todayKey] ?? 0) + live
    }

    /// This year's reading on every device, including a session still
    /// running, which isn't in the stored rows yet.
    func readingYear(of date: Date = Date()) -> ReadingLog.Year {
        recomputeReadingStats()
        let rows = ((try? context.fetch(FetchDescriptor<ReadingDay>())) ?? []).map { (dayKey: $0.day, seconds: $0.seconds) }
        let calendar = Calendar.current
        var year = ReadingLog.year(calendar.component(.year, from: date), from: rows)
        let todayKey = ReadingLog.dayKey(for: date)
        let stored = rows.filter { $0.dayKey == todayKey }.reduce(0) { $0 + $1.seconds }
        let live = readingSecondsToday - stored
        if live > 0 {
            year.totalSeconds += live
            year.monthSeconds[calendar.component(.month, from: date) - 1] += live
            if stored == 0 { year.daysRead += 1 }
        }
        return year
    }

    func booksFinished(inYearOf date: Date = Date()) -> [Book] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .year, for: date) else { return [] }
        let descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.finishedAt != nil })
        return ((try? context.fetch(descriptor)) ?? [])
            .filter { $0.finishedAt.map(interval.contains) ?? false }
            .sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
    }

    func recordReadingPace(pagesRead: Double, elapsedSeconds: Double) {
        preferences.minutesPerPage = ReadingEstimate.calibratedMinutesPerPage(
            previous: preferences.minutesPerPage,
            observedPages: pagesRead,
            elapsedSeconds: elapsedSeconds
        )
    }
}
