import Foundation
import Testing
@testable import ChickenKit

struct WidgetSnapshotTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let written = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(days: [Int]?, today: Int, day: Date?) -> WidgetSnapshot {
        WidgetSnapshot(
            currentBook: nil, secondsToday: today, dailyGoalMinutes: 30, theme: "paper",
            lastSevenDays: days, day: day
        )
    }

    @Test func sameDayShowsTheWeekAsWritten() {
        let week = [1, 2, 3, 4, 5, 6, 7]
        let snap = snapshot(days: week, today: 7, day: written)
        #expect(snap.week(endingOn: written, calendar: calendar) == week)
        #expect(snap.secondsToday(on: written, calendar: calendar) == 7)
    }

    @Test func nextMorningStartsTodayAtZero() {
        let snap = snapshot(days: [1, 2, 3, 4, 5, 6, 7], today: 7, day: written)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: written)!
        #expect(snap.week(endingOn: tomorrow, calendar: calendar) == [2, 3, 4, 5, 6, 7, 0])
        #expect(snap.secondsToday(on: tomorrow, calendar: calendar) == 0)
    }

    @Test func aWeekLaterIsAllZero() {
        let snap = snapshot(days: [1, 2, 3, 4, 5, 6, 7], today: 7, day: written)
        let later = calendar.date(byAdding: .day, value: 9, to: written)!
        #expect(snap.week(endingOn: later, calendar: calendar) == Array(repeating: 0, count: 7))
    }

    @Test func olderSnapshotsWithoutAWeekStillDecode() throws {
        let json = #"{"secondsToday":600,"dailyGoalMinutes":30,"theme":"ink"}"#
        let snap = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(json.utf8))
        #expect(snap.week(endingOn: written) == [0, 0, 0, 0, 0, 0, 600])
        #expect(snap.secondsToday(on: written) == 600)
    }
}
