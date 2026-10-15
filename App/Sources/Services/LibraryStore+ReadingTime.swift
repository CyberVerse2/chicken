import ChickenKit
import Foundation
import SwiftData

/// Active reading time: counted while at least one reader is open and the
/// app is in the foreground, committed to `ReadingDay` rows every 30 seconds.
extension LibraryStore {
    func readerDidAppear() {
        openReaderCount += 1
        resumeReadingSession()
    }

    func readerDidDisappear() {
        openReaderCount = max(0, openReaderCount - 1)
        if openReaderCount == 0 { pauseReadingSession() }
    }

    func appDidBecomeActive() {
        if openReaderCount > 0 { resumeReadingSession() }
        recomputeReadingStats()
    }

    func appDidResignActive() {
        pauseReadingSession()
    }

    private func resumeReadingSession() {
        if sessionStart == nil { sessionStart = Date() }
        guard sessionTimer == nil else { return }
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.commitReadingSession(continuing: true) }
        }
        RunLoop.main.add(timer, forMode: .common)
        sessionTimer = timer
        recomputeReadingStats()
    }

    private func pauseReadingSession() {
        sessionTimer?.invalidate()
        sessionTimer = nil
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
    }

    func addReadingSeconds(_ seconds: Int, toDay day: String) {
        guard seconds > 0 else { return }
        var descriptor = FetchDescriptor<ReadingDay>(predicate: #Predicate { $0.day == day })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            existing.seconds += seconds
        } else {
            context.insert(ReadingDay(day: day, seconds: seconds))
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

        // Show the in-flight session too, clipped to today.
        let today = Calendar.current.startOfDay(for: Date())
        let live = sessionStart.map { max(0, Int(Date().timeIntervalSince(max($0, today)))) } ?? 0
        let todayKey = ReadingLog.dayKey(for: today)

        lastSevenDays = zip(days, keys).map { day, key in
            DayReading(dayStart: day, seconds: (secondsByDay[key] ?? 0) + (key == todayKey ? live : 0))
        }
        readingSecondsToday = (secondsByDay[todayKey] ?? 0) + live
    }

    func booksFinished(inYearOf date: Date = Date()) -> [Book] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .year, for: date) else { return [] }
        let descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.finishedAt != nil })
        return ((try? context.fetch(descriptor)) ?? [])
            .filter { $0.finishedAt.map(interval.contains) ?? false }
            .sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
    }
}
