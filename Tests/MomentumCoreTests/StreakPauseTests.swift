import XCTest
@testable import MomentumCore

/// Parent-spec §3.3: days on which a module is disabled are ineligible for
/// its Category Streak — the streak pauses and resumes on re-enable rather
/// than breaking. Disabled days arrive at the engine as neutral entries.
final class StreakPauseTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> DomainDay {
        DomainDay(year: year, month: month, day: day)
    }

    func testWorkoutStreakIgnoresPausedOpportunities() {
        let engine = AdherenceEngine()
        let streak = engine.workoutStreak(opportunities: [
            .finished,
            .paused,
            .finished,
            .missed,
            .finished,
        ])
        XCTAssertEqual(streak, 1)
    }

    func testNutritionStreakContinuesAcrossPausedDay() {
        let engine = AdherenceEngine()
        let streak = engine.nutritionStreak(
            days: [
                NutritionAdherenceDay(day: day(2026, 8, 1), isFinalized: true),
                NutritionAdherenceDay(day: day(2026, 8, 2), isFinalized: false, isPaused: true),
                NutritionAdherenceDay(day: day(2026, 8, 3), isFinalized: true),
                NutritionAdherenceDay(day: day(2026, 8, 4), isFinalized: true),
            ],
            calendar: calendar
        )
        XCTAssertEqual(streak, 3)
    }

    func testCareStreakContinuesAcrossPausedDay() {
        let engine = AdherenceEngine()
        let streak = engine.careStreak(
            days: [
                CareAdherenceDay(day: day(2026, 8, 1), dueCount: 2, completedCount: 2),
                CareAdherenceDay(day: day(2026, 8, 2), dueCount: 0, completedCount: 0, isPaused: true),
                CareAdherenceDay(day: day(2026, 8, 3), dueCount: 1, completedCount: 1),
            ],
            calendar: calendar
        )
        XCTAssertEqual(streak, 2)
    }

    func testUnrecordedGapStillBreaksNutritionStreak() {
        // Pause semantics apply only to days explicitly marked paused; an
        // unexplained calendar gap still resets.
        let engine = AdherenceEngine()
        let streak = engine.nutritionStreak(
            days: [
                NutritionAdherenceDay(day: day(2026, 8, 1), isFinalized: true),
                NutritionAdherenceDay(day: day(2026, 8, 5), isFinalized: true),
            ],
            calendar: calendar
        )
        XCTAssertEqual(streak, 1)
    }
}
