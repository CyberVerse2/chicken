import Testing
@testable import ChickenKit

struct ReadingYearTests {
    @Test func sumsDevicesPerDayAndMonth() {
        let year = ReadingLog.year(2026, from: [
            ("2026-01-05", 600), ("2026-01-05", 300),   // two devices, one day
            ("2026-01-20", 120),
            ("2026-10-15", 1800),
        ])
        #expect(year.totalSeconds == 2820)
        #expect(year.monthSeconds[0] == 1020)
        #expect(year.monthSeconds[9] == 1800)
        #expect(year.daysRead == 3)
    }

    @Test func ignoresOtherYearsAndEmptyRows() {
        let year = ReadingLog.year(2026, from: [("2025-12-31", 900), ("2026-03-01", 0), ("garbage", 50)])
        #expect(year == ReadingLog.Year())
    }
}
