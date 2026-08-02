import MomentumCore
import XCTest
@testable import Momentum

final class HistoryProjectionTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }

    func test_sixteenWeekWindowStartsMondayAndContains112Days() {
        let days = HistoryProjection.heatmapDays(
            endingOn: DomainDay(year: 2026, month: 8, day: 2),
            calendar: calendar
        )

        XCTAssertEqual(days.count, 112)
        XCTAssertEqual(days.first, DomainDay(year: 2026, month: 4, day: 13))
        XCTAssertEqual(days.last, DomainDay(year: 2026, month: 8, day: 2))
    }

    func test_allCategoryScoreWeightsWorkoutNutritionAndEachCareRoutineEqually() {
        let day = DomainDay(year: 2026, month: 8, day: 2)
        let facts = [
            HistoryAdherenceFact(day: day, category: .workouts, isCompleted: true),
            HistoryAdherenceFact(day: day, category: .nutrition, isCompleted: false),
            HistoryAdherenceFact(day: day, category: .care, isCompleted: true),
            HistoryAdherenceFact(day: day, category: .care, isCompleted: false)
        ]

        XCTAssertEqual(
            HistoryProjection.adherenceScore(on: day, facts: facts, category: .all),
            .score(completedCount: 2, dueCount: 4, percentage: 50)
        )
    }

    func test_measurementsAreFactsNotAdherenceObligations() {
        XCTAssertEqual(
            HistoryProjection.adherenceScore(
                on: DomainDay(year: 2026, month: 8, day: 2),
                facts: [],
                category: .measurements
            ),
            .noObligation
        )
    }

    func test_categoryStreaksUsePersistedOpportunityAndDailyFacts() {
        let facts = [
            HistoryAdherenceFact(day: day(1), category: .workouts, isCompleted: true),
            // Recovery day 2 has no workout fact and remains neutral.
            HistoryAdherenceFact(day: day(3), category: .workouts, isCompleted: true),
            HistoryAdherenceFact(day: day(1), category: .nutrition, isCompleted: true),
            HistoryAdherenceFact(day: day(2), category: .nutrition, isCompleted: false),
            HistoryAdherenceFact(day: day(3), category: .nutrition, isCompleted: true),
            HistoryAdherenceFact(day: day(1), category: .care, isCompleted: true),
            HistoryAdherenceFact(day: day(2), category: .care, isCompleted: false),
            HistoryAdherenceFact(day: day(3), category: .care, isCompleted: true)
        ]

        XCTAssertEqual(
            HistoryProjection.streaks(facts: facts, calendar: calendar),
            HistoryStreakSummary(workout: 2, nutrition: 1, care: 1)
        )
    }

    private func day(_ value: Int) -> DomainDay {
        DomainDay(year: 2026, month: 8, day: value)
    }

    @MainActor
    func test_workoutDeletionPreviewDoesNotMutateSessionAndShowsBeforeAfterSchedule() throws {
        let upperID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let lowerID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let targetID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        let sessions = [
            WorkoutSessionRecord(
                workoutTemplateID: upperID,
                workoutNameSnapshot: "Upper A",
                sequenceIndexSnapshot: 0,
                recoveryDaysAfterSnapshot: 0,
                nextWorkoutTemplateIDSnapshot: lowerID,
                scheduledDomainDay: "2026-08-01",
                startedAt: Date(timeIntervalSince1970: 10),
                finishedAt: Date(timeIntervalSince1970: 20),
                completionDomainDay: "2026-08-01"
            ),
            WorkoutSessionRecord(
                id: targetID,
                workoutTemplateID: lowerID,
                workoutNameSnapshot: "Lower A",
                sequenceIndexSnapshot: 1,
                recoveryDaysAfterSnapshot: 1,
                nextWorkoutTemplateIDSnapshot: upperID,
                scheduledDomainDay: "2026-08-02",
                startedAt: Date(timeIntervalSince1970: 30),
                finishedAt: Date(timeIntervalSince1970: 40),
                completionDomainDay: "2026-08-02"
            )
        ]
        let workouts = [
            WorkoutTemplateRecord(
                id: upperID,
                name: "Upper A",
                sequenceIndex: 0,
                recoveryDaysAfter: 0
            ),
            WorkoutTemplateRecord(
                id: lowerID,
                name: "Lower A",
                sequenceIndex: 1,
                recoveryDaysAfter: 1
            )
        ]
        let anchors = [CycleAnchorRecord(
            nextWorkoutTemplateID: upperID,
            firstDueDomainDay: "2026-08-01"
        )]

        let preview = try XCTUnwrap(HistoryCorrectionProjection.workoutDeletionPreview(
            sessionID: targetID,
            workouts: workouts,
            anchors: anchors,
            sessions: sessions,
            settings: [AppSettingsRecord(domainDayCutoffMinutes: 180)],
            now: calendar.date(from: DateComponents(
                year: 2026,
                month: 8,
                day: 3,
                hour: 12
            ))!,
            calendar: calendar
        ))

        XCTAssertEqual(preview.beforeSummary, "Upper A · due 2026-08-04")
        XCTAssertEqual(preview.afterSummary, "Lower A · due 2026-08-02")
        XCTAssertNil(sessions.last?.deletedAt)
    }
}
