import Foundation
import XCTest
@testable import MomentumCore

final class AdherenceEngineTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func test_noDueActivitiesIsNoObligationRatherThanZeroPercent() {
        XCTAssertEqual(AdherenceEngine().dailyScore(activities: []), .noObligation)
    }

    func test_eachDueActivityHasEqualWeight() {
        let result = AdherenceEngine().dailyScore(activities: [
            .init(kind: .workout, isCompleted: true),
            .init(kind: .nutritionFinalization, isCompleted: true),
            .init(kind: .morningCare, isCompleted: false),
            .init(kind: .nightCare, isCompleted: false)
        ])

        XCTAssertEqual(result, .score(completedCount: 2, dueCount: 4, percentage: 50))
    }

    func test_recoveryAddsNoWorkoutObligation() {
        let result = AdherenceEngine().dailyScore(activities: [
            .init(kind: .nutritionFinalization, isCompleted: true),
            .init(kind: .morningCare, isCompleted: true),
            .init(kind: .nightCare, isCompleted: false)
        ])

        guard case let .score(completedCount, dueCount, percentage) = result else {
            return XCTFail("Expected a scored adherence day")
        }
        XCTAssertEqual(completedCount, 2)
        XCTAssertEqual(dueCount, 3)
        XCTAssertEqual(percentage, 66.66666666666667, accuracy: 0.000_000_1)
    }

    func test_workoutStreakCountsDueOpportunitiesAndRecoveryIsNeutral() {
        let opportunities: [WorkoutAdherenceOutcome] = [
            .finished,
            .finished,
            // Recovery days are intentionally absent from this opportunity stream.
            .finished
        ]

        XCTAssertEqual(AdherenceEngine().workoutStreak(opportunities: opportunities), 3)
    }

    func test_missedOrSkippedWorkoutBreaksWorkoutStreak() {
        XCTAssertEqual(
            AdherenceEngine().workoutStreak(opportunities: [.finished, .missed, .finished]),
            1
        )
        XCTAssertEqual(
            AdherenceEngine().workoutStreak(opportunities: [.finished, .skipped]),
            0
        )
    }

    func test_nutritionStreakRequiresFinalizationOnConsecutiveDomainDays() {
        let days = [
            NutritionAdherenceDay(day: day(1), isFinalized: true),
            NutritionAdherenceDay(day: day(2), isFinalized: false),
            NutritionAdherenceDay(day: day(3), isFinalized: true),
            NutritionAdherenceDay(day: day(4), isFinalized: true)
        ]

        XCTAssertEqual(AdherenceEngine().nutritionStreak(days: days, calendar: calendar), 2)
    }

    func test_nutritionStreakHandlesMoreThanEighteenMonthsAndCalendarGaps() {
        let start = DomainDay(year: 2025, month: 1, day: 1)
        let longRun = (0..<550).map {
            NutritionAdherenceDay(
                day: start.adding(days: $0, calendar: calendar),
                isFinalized: true
            )
        }
        XCTAssertEqual(
            AdherenceEngine().nutritionStreak(days: longRun, calendar: calendar),
            550
        )

        let gap = [
            NutritionAdherenceDay(day: day(1), isFinalized: true),
            NutritionAdherenceDay(day: day(3), isFinalized: true)
        ]
        XCTAssertEqual(AdherenceEngine().nutritionStreak(days: gap, calendar: calendar), 1)
    }

    func test_careStreakRequiresEveryDueRoutineAndNoObligationDayIsNeutral() {
        let days = [
            CareAdherenceDay(day: day(1), dueCount: 3, completedCount: 3),
            CareAdherenceDay(day: day(2), dueCount: 0, completedCount: 0),
            CareAdherenceDay(day: day(3), dueCount: 4, completedCount: 4)
        ]

        XCTAssertEqual(AdherenceEngine().careStreak(days: days, calendar: calendar), 2)
    }

    func test_incompleteCareDayBreaksCareStreakEvenWhenHairRollsForward() {
        let days = [
            CareAdherenceDay(day: day(1), dueCount: 3, completedCount: 3),
            CareAdherenceDay(day: day(2), dueCount: 3, completedCount: 2),
            CareAdherenceDay(day: day(3), dueCount: 4, completedCount: 4)
        ]

        XCTAssertEqual(AdherenceEngine().careStreak(days: days, calendar: calendar), 1)
    }

    private func day(_ day: Int) -> DomainDay {
        DomainDay(year: 2026, month: 8, day: day)
    }
}
