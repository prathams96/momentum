import Foundation
import MomentumCore
import SwiftData
import XCTest
@testable import Momentum

@MainActor
final class HistoryCorrectionTransactionTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func test_workoutTimestampCorrectionMovesAdherenceFactAndRecalculatesScheduleInOneTransaction() throws {
        let container = try ModelContainerFactory.makePreview()
        let context = container.mainContext
        let upperID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let lowerID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let settings = AppSettingsRecord(domainDayCutoffMinutes: 180)
        let upper = WorkoutTemplateRecord(
            id: upperID,
            name: "Upper A",
            sequenceIndex: 0,
            recoveryDaysAfter: 0
        )
        let lower = WorkoutTemplateRecord(
            id: lowerID,
            name: "Lower A",
            sequenceIndex: 1,
            recoveryDaysAfter: 1
        )
        let anchor = CycleAnchorRecord(
            nextWorkoutTemplateID: upperID,
            firstDueDomainDay: "2026-08-01"
        )
        let first = completedSession(
            workoutID: upperID,
            name: "Upper A",
            sequence: 0,
            recovery: 0,
            nextID: lowerID,
            day: 1,
            hour: 11
        )
        let corrected = completedSession(
            workoutID: lowerID,
            name: "Lower A",
            sequence: 1,
            recovery: 1,
            nextID: upperID,
            day: 2,
            hour: 11
        )
        context.insert(settings)
        context.insert(upper)
        context.insert(lower)
        context.insert(anchor)
        context.insert(first)
        context.insert(corrected)
        try context.save()

        let proposed = date(day: 4, hour: 11)
        try HistoryCorrectionService.updateWorkoutCompletion(
            sessionID: corrected.id,
            finishedAt: proposed,
            in: context,
            now: date(day: 5, hour: 12),
            calendar: calendar
        )

        XCTAssertEqual(corrected.finishedAt, proposed)
        XCTAssertEqual(corrected.completionDomainDay, "2026-08-04")
        let facts = HistoryProjection.facts(
            sessions: [first, corrected],
            workoutEvents: [],
            nutritionDays: [],
            careOccurrences: []
        )
        XCTAssertFalse(facts.contains { $0.day == day(2) })
        XCTAssertTrue(facts.contains { $0.day == day(4) && $0.isCompleted })
        XCTAssertEqual(
            ScheduleProjection.evaluate(
                workouts: [upper, lower],
                anchors: [anchor],
                sessions: [first, corrected],
                settings: [settings],
                now: date(day: 5, hour: 12),
                calendar: calendar
            ),
            .recovery(
                nextWorkoutID: upperID,
                eligibleDay: day(6),
                daysRemaining: 1
            )
        )
    }

    func test_invalidWorkoutCorrectionRollsBackWithoutPartialMutation() throws {
        let container = try ModelContainerFactory.makePreview()
        let context = container.mainContext
        let session = WorkoutSessionRecord(
            workoutNameSnapshot: "Upper A",
            scheduledDomainDay: "2026-08-02",
            startedAt: date(day: 2, hour: 10),
            finishedAt: date(day: 2, hour: 11),
            completionDomainDay: "2026-08-02"
        )
        context.insert(session)
        try context.save()

        XCTAssertThrowsError(try HistoryCorrectionService.updateWorkoutCompletion(
            sessionID: UUID(),
            finishedAt: date(day: 1, hour: 11),
            in: context,
            now: date(day: 3, hour: 12),
            calendar: calendar
        )) { error in
            XCTAssertEqual(error as? HistoryCorrectionError, .workoutNotFound)
        }
        XCTAssertEqual(session.finishedAt, date(day: 2, hour: 11))
        XCTAssertEqual(session.completionDomainDay, "2026-08-02")
    }

    func test_nutritionFinalizeAndReopenUpdateSnapshotsAdherenceAndStreak() throws {
        let container = try ModelContainerFactory.makePreview()
        let context = container.mainContext
        context.insert(AppSettingsRecord(domainDayCutoffMinutes: 180))
        context.insert(NutritionTargetRecord(
            effectiveFrom: "2026-08-01",
            calorieDisplayTarget: 2_400,
            calorieMinimum: 2_300,
            calorieMaximum: 2_500,
            proteinMinimumGrams: 150
        ))
        try context.save()

        try HistoryCorrectionService.toggleNutritionFinalization(
            domainDay: day(2),
            in: context,
            now: date(day: 2, hour: 20),
            calendar: calendar
        )
        let record = try XCTUnwrap(
            context.fetch(FetchDescriptor<NutritionDayRecord>()).first
        )
        XCTAssertNotNil(record.finalizedAt)
        XCTAssertEqual(record.calorieMinimumSnapshot, 2_300)
        XCTAssertEqual(record.proteinMinimumSnapshot, 150)
        var facts = HistoryProjection.facts(
            sessions: [],
            workoutEvents: [],
            nutritionDays: [record],
            careOccurrences: []
        )
        XCTAssertEqual(
            HistoryProjection.streaks(facts: facts, calendar: calendar).nutrition,
            1
        )

        try HistoryCorrectionService.toggleNutritionFinalization(
            domainDay: day(2),
            in: context,
            now: date(day: 2, hour: 21),
            calendar: calendar
        )
        XCTAssertNil(record.finalizedAt)
        facts = HistoryProjection.facts(
            sessions: [],
            workoutEvents: [],
            nutritionDays: [record],
            careOccurrences: []
        )
        XCTAssertEqual(
            HistoryProjection.streaks(facts: facts, calendar: calendar).nutrition,
            0
        )
    }

    func test_careUndoRestoresTasksRecurrenceAndAdherenceTogether() throws {
        let container = try ModelContainerFactory.makePreview()
        let context = container.mainContext
        let originalPayload = "original-recurrence"
        let routine = CareRoutineTemplateRecord(
            name: "Hair care",
            routineRoleRaw: "hair",
            recurrenceKindRaw: "alternatingInterval",
            recurrencePayload: "advanced-recurrence",
            notificationMinutes: 8 * 60,
            rollsForwardWhenMissed: true
        )
        let occurrence = CareOccurrenceRecord(
            routineTemplateID: routine.id,
            routineNameSnapshot: routine.name,
            routineRoleRaw: routine.routineRoleRaw,
            dueDomainDay: "2026-08-02",
            dueAt: date(day: 2, hour: 8),
            statusRaw: "completed",
            completedAt: date(day: 2, hour: 8),
            recurrencePayloadBeforeCompletion: originalPayload
        )
        let task = CareTaskCompletionRecord(
            occurrenceID: occurrence.id,
            labelSnapshot: "Wash scalp",
            statusRaw: "completed",
            completedAt: date(day: 2, hour: 8)
        )
        context.insert(AppSettingsRecord(domainDayCutoffMinutes: 180))
        context.insert(routine)
        context.insert(occurrence)
        context.insert(task)
        try context.save()

        try HistoryCorrectionService.undoCareCompletion(
            occurrenceID: occurrence.id,
            in: context,
            now: date(day: 2, hour: 12),
            calendar: calendar
        )

        XCTAssertEqual(occurrence.statusRaw, "pending")
        XCTAssertNil(occurrence.completedAt)
        XCTAssertEqual(task.statusRaw, "pending")
        XCTAssertNil(task.completedAt)
        XCTAssertEqual(routine.recurrencePayload, originalPayload)
        XCTAssertNil(occurrence.recurrencePayloadBeforeCompletion)
        let facts = HistoryProjection.facts(
            sessions: [],
            workoutEvents: [],
            nutritionDays: [],
            careOccurrences: [occurrence]
        )
        XCTAssertEqual(
            HistoryProjection.streaks(facts: facts, calendar: calendar).care,
            0
        )
    }

    private func completedSession(
        workoutID: UUID,
        name: String,
        sequence: Int,
        recovery: Int,
        nextID: UUID,
        day: Int,
        hour: Int
    ) -> WorkoutSessionRecord {
        WorkoutSessionRecord(
            workoutTemplateID: workoutID,
            workoutNameSnapshot: name,
            sequenceIndexSnapshot: sequence,
            recoveryDaysAfterSnapshot: recovery,
            nextWorkoutTemplateIDSnapshot: nextID,
            scheduledDomainDay: "2026-08-\(String(format: "%02d", day))",
            startedAt: date(day: day, hour: hour - 1),
            finishedAt: date(day: day, hour: hour),
            completionDomainDay: "2026-08-\(String(format: "%02d", day))"
        )
    }

    private func day(_ value: Int) -> DomainDay {
        DomainDay(year: 2026, month: 8, day: value)
    }

    private func date(day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: day,
            hour: hour
        ))!
    }
}
