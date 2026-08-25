import XCTest
@testable import MomentumCore

final class HydrationStreakTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> DomainDay {
        DomainDay(year: year, month: month, day: day)
    }

    func testHydrationStreakCountsConsecutiveDaysWithTargetReached() {
        let engine = AdherenceEngine()
        let days = [
            HydrationAdherenceDay(day: day(2026, 8, 1), isTargetReached: true),
            HydrationAdherenceDay(day: day(2026, 8, 2), isTargetReached: true),
            HydrationAdherenceDay(day: day(2026, 8, 3), isTargetReached: false),
            HydrationAdherenceDay(day: day(2026, 8, 4), isTargetReached: true),
        ]

        XCTAssertEqual(engine.hydrationStreak(days: days, calendar: calendar), 1)
    }

    func testHydrationStreakBreaksAcrossCalendarGaps() {
        let engine = AdherenceEngine()
        let days = [
            HydrationAdherenceDay(day: day(2026, 8, 1), isTargetReached: true),
            HydrationAdherenceDay(day: day(2026, 8, 10), isTargetReached: true),
        ]

        XCTAssertEqual(engine.hydrationStreak(days: days, calendar: calendar), 1)
    }

    func testDisabledIntervalDaysPauseWithoutBreakingTheStreak() {
        // Disabled-module days are recorded as paused (neutral): they neither
        // extend nor reset the Category Streak.
        let engine = AdherenceEngine()
        let days = [
            HydrationAdherenceDay(day: day(2026, 8, 1), isTargetReached: true),
            HydrationAdherenceDay(day: day(2026, 8, 2), isTargetReached: false, isPaused: true),
            HydrationAdherenceDay(day: day(2026, 8, 3), isTargetReached: true),
            HydrationAdherenceDay(day: day(2026, 8, 4), isTargetReached: true),
        ]

        XCTAssertEqual(engine.hydrationStreak(days: days, calendar: calendar), 3)
    }

    func testEmptyHistoryHasNoStreak() {
        let engine = AdherenceEngine()
        XCTAssertEqual(engine.hydrationStreak(days: [], calendar: calendar), 0)
    }
}
