import Foundation
import XCTest
@testable import MomentumCore

final class ScheduleEngineTests: XCTestCase {
    func test_finishingUpperAMakesLowerADueNextDomainDay() {
        let upperAID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let lowerAID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

        let result = ScheduleEngine().evaluate(makeInput(
            completedWorkoutID: upperAID,
            currentDay: DomainDay(year: 2026, month: 8, day: 3),
            finishedAt: 10
        ))

        XCTAssertEqual(result, .due(
            workoutID: lowerAID,
            dueDay: DomainDay(year: 2026, month: 8, day: 3),
            overdueBy: 0
        ))
    }

    func test_finishingUpperAUsesActualCompletionDomainDay() {
        let upperAID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let lowerAID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let input = makeInput(
            completedWorkoutID: upperAID,
            currentDay: DomainDay(year: 2026, month: 8, day: 5),
            finishedAt: 20,
            completionDay: DomainDay(year: 2026, month: 8, day: 4)
        )

        let result = ScheduleEngine().evaluate(input)

        XCTAssertEqual(result, .due(
            workoutID: lowerAID,
            dueDay: DomainDay(year: 2026, month: 8, day: 5),
            overdueBy: 0
        ))
    }

    func test_finishingLowerARequiresOneRecoveryDayBeforeUpperB() {
        let lowerAID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let upperBID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let completionDay = DomainDay(year: 2026, month: 8, day: 2)

        let result = ScheduleEngine().evaluate(makeInput(
            completedWorkoutID: lowerAID,
            currentDay: DomainDay(year: 2026, month: 8, day: 3),
            finishedAt: 20
        ))

        XCTAssertEqual(result, .recovery(
            nextWorkoutID: upperBID,
            eligibleDay: completionDay.adding(
                days: 2,
                calendar: Calendar(identifier: .gregorian)
            ),
            daysRemaining: 1
        ))
    }

    func test_finishingUpperBRequiresNoRecoveryDayBeforeLowerB() {
        let upperBID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let lowerBID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!

        let result = ScheduleEngine().evaluate(makeInput(
            completedWorkoutID: upperBID,
            currentDay: DomainDay(year: 2026, month: 8, day: 3),
            finishedAt: 20
        ))

        XCTAssertEqual(result, .due(
            workoutID: lowerBID,
            dueDay: DomainDay(year: 2026, month: 8, day: 3),
            overdueBy: 0
        ))
    }

    func test_finishingLowerBRequiresTwoRecoveryDaysBeforeUpperA() {
        let lowerBID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        let upperAID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

        let result = ScheduleEngine().evaluate(makeInput(
            completedWorkoutID: lowerBID,
            currentDay: DomainDay(year: 2026, month: 8, day: 4),
            finishedAt: 20
        ))

        XCTAssertEqual(result, .recovery(
            nextWorkoutID: upperAID,
            eligibleDay: DomainDay(year: 2026, month: 8, day: 5),
            daysRemaining: 1
        ))
    }

    func test_unsortedCompletedSessionsUseTheLatestFinishedSession() {
        let upperAID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let lowerAID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let completionDay = DomainDay(year: 2026, month: 8, day: 2)
        let input = makeInput(
            completedWorkoutID: upperAID,
            currentDay: DomainDay(year: 2026, month: 8, day: 3),
            finishedAt: 20,
            additionalSessions: [CompletedWorkoutSession(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
                workoutTemplateID: lowerAID,
                completionDomainDay: completionDay,
                finishedAt: Date(timeIntervalSince1970: 10)
            )]
        )

        let result = ScheduleEngine().evaluate(input)

        XCTAssertEqual(result, .due(
            workoutID: lowerAID,
            dueDay: DomainDay(year: 2026, month: 8, day: 3),
            overdueBy: 0
        ))
    }

    func test_deletedOlderWorkoutDoesNotInvalidateLatestSchedule() {
        let upperAID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let deletedWorkout = CompletedWorkoutSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
            workoutTemplateID: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!,
            completionDomainDay: DomainDay(year: 2026, month: 8, day: 1),
            finishedAt: Date(timeIntervalSince1970: 10)
        )
        let input = makeInput(
            completedWorkoutID: upperAID,
            currentDay: DomainDay(year: 2026, month: 8, day: 3),
            finishedAt: 20,
            additionalSessions: [deletedWorkout]
        )

        let result = ScheduleEngine().evaluate(input)

        XCTAssertEqual(result, .due(
            workoutID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            dueDay: DomainDay(year: 2026, month: 8, day: 3),
            overdueBy: 0
        ))
    }

    func test_longGapLeavesTheSameWorkoutDueWithoutCatchUp() {
        let upperAID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

        let result = ScheduleEngine().evaluate(makeInput(
            completedWorkoutID: upperAID,
            currentDay: DomainDay(year: 2026, month: 8, day: 10),
            finishedAt: 20
        ))

        XCTAssertEqual(result, .due(
            workoutID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            dueDay: DomainDay(year: 2026, month: 8, day: 3),
            overdueBy: 7
        ))
    }

    func test_initialAnchorMakesUpperADueOnItsFirstDueDomainDay() {
        let upperAID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let firstDueDay = DomainDay(year: 2026, month: 8, day: 2)
        let input = makeInput(
            completedWorkoutID: upperAID,
            currentDay: firstDueDay,
            finishedAt: 20
        )
        let initialInput = ScheduleInput(
            activeWorkoutTemplates: input.activeWorkoutTemplates,
            cycleAnchor: input.cycleAnchor,
            completedSessions: [],
            currentDomainDay: firstDueDay
        )

        let result = ScheduleEngine().evaluate(initialInput)

        XCTAssertEqual(result, .due(
            workoutID: upperAID,
            dueDay: firstDueDay,
            overdueBy: 0
        ))
    }

    func test_activeSessionTakesPrecedenceOverScheduleState() {
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000020")!
        var input = makeInput(
            completedWorkoutID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            currentDay: DomainDay(year: 2026, month: 8, day: 2),
            finishedAt: 20
        )
        input = ScheduleInput(
            activeWorkoutTemplates: input.activeWorkoutTemplates,
            cycleAnchor: input.cycleAnchor,
            completedSessions: input.completedSessions,
            currentDomainDay: input.currentDomainDay,
            activeSessionID: sessionID
        )

        XCTAssertEqual(ScheduleEngine().evaluate(input), .active(sessionID: sessionID))
    }

    func test_nonContiguousSequenceNeedsRepair() {
        let input = ScheduleInput(
            activeWorkoutTemplates: [
                WorkoutTemplate(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                    name: "Upper A",
                    sequenceIndex: 0,
                    recoveryDaysAfter: 0
                ),
                WorkoutTemplate(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                    name: "Lower A",
                    sequenceIndex: 2,
                    recoveryDaysAfter: 1
                )
            ],
            cycleAnchor: CycleAnchor(
                nextWorkoutID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                firstDueDomainDay: DomainDay(year: 2026, month: 8, day: 2)
            ),
            completedSessions: [],
            currentDomainDay: DomainDay(year: 2026, month: 8, day: 2)
        )

        XCTAssertEqual(
            ScheduleEngine().evaluate(input),
            .needsRepair(reason: .invalidSequenceIndices)
        )
    }

    func test_archivedLatestCompletedTemplateUsesSessionSnapshots() {
        let lowerAID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let upperBID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let lowerBID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        let completionDay = DomainDay(year: 2026, month: 8, day: 2)
        let input = ScheduleInput(
            activeWorkoutTemplates: [
                WorkoutTemplate(id: lowerAID, name: "Lower A", sequenceIndex: 0, recoveryDaysAfter: 1),
                WorkoutTemplate(id: upperBID, name: "Upper B", sequenceIndex: 1, recoveryDaysAfter: 0),
                WorkoutTemplate(id: lowerBID, name: "Lower B", sequenceIndex: 2, recoveryDaysAfter: 2)
            ],
            cycleAnchor: CycleAnchor(
                nextWorkoutID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                firstDueDomainDay: completionDay
            ),
            completedSessions: [CompletedWorkoutSession(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
                workoutTemplateID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                completionDomainDay: completionDay,
                finishedAt: Date(timeIntervalSince1970: 20),
                sequenceIndexSnapshot: 0,
                recoveryDaysAfterSnapshot: 0
            )],
            currentDomainDay: DomainDay(year: 2026, month: 8, day: 3)
        )

        XCTAssertEqual(ScheduleEngine().evaluate(input), .due(
            workoutID: lowerAID,
            dueDay: DomainDay(year: 2026, month: 8, day: 3),
            overdueBy: 0
        ))
    }

    func test_reorderedCycleUsesSnapshottedSuccessorWhenCompletedTemplateWasRemoved() {
        let upperBID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let lowerBID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        let completionDay = DomainDay(year: 2026, month: 8, day: 2)
        let input = ScheduleInput(
            activeWorkoutTemplates: [
                WorkoutTemplate(id: lowerBID, name: "Lower B", sequenceIndex: 0, recoveryDaysAfter: 2),
                WorkoutTemplate(id: upperBID, name: "Upper B", sequenceIndex: 1, recoveryDaysAfter: 0)
            ],
            cycleAnchor: CycleAnchor(
                nextWorkoutID: lowerBID,
                firstDueDomainDay: completionDay
            ),
            completedSessions: [CompletedWorkoutSession(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
                workoutTemplateID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                completionDomainDay: completionDay,
                finishedAt: Date(timeIntervalSince1970: 20),
                sequenceIndexSnapshot: 1,
                recoveryDaysAfterSnapshot: 1,
                nextWorkoutTemplateIDSnapshot: upperBID
            )],
            currentDomainDay: DomainDay(year: 2026, month: 8, day: 3)
        )

        XCTAssertEqual(ScheduleEngine().evaluate(input), .recovery(
            nextWorkoutID: upperBID,
            eligibleDay: DomainDay(year: 2026, month: 8, day: 4),
            daysRemaining: 1
        ))
    }

    func test_missingLatestTemplateWithoutRequiredSnapshotsStillNeedsRepair() {
        var input = makeInput(
            completedWorkoutID: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!,
            currentDay: DomainDay(year: 2026, month: 8, day: 3),
            finishedAt: 20
        )
        input = ScheduleInput(
            activeWorkoutTemplates: input.activeWorkoutTemplates,
            cycleAnchor: input.cycleAnchor,
            completedSessions: input.completedSessions,
            currentDomainDay: input.currentDomainDay
        )

        XCTAssertEqual(
            ScheduleEngine().evaluate(input),
            .needsRepair(reason: .completedSessionReferencesMissingWorkout)
        )
    }

    private func makeInput(
        completedWorkoutID: UUID,
        currentDay: DomainDay,
        finishedAt: TimeInterval,
        completionDay: DomainDay = DomainDay(year: 2026, month: 8, day: 2),
        additionalSessions: [CompletedWorkoutSession] = []
    ) -> ScheduleInput {
        let sessions = [CompletedWorkoutSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            workoutTemplateID: completedWorkoutID,
            completionDomainDay: completionDay,
            finishedAt: Date(timeIntervalSince1970: finishedAt)
        )] + additionalSessions
        let upperAID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let lowerAID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let upperBID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let lowerBID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!

        return ScheduleInput(
            activeWorkoutTemplates: [
                WorkoutTemplate(id: lowerBID, name: "Lower B", sequenceIndex: 3, recoveryDaysAfter: 2),
                WorkoutTemplate(id: upperBID, name: "Upper B", sequenceIndex: 2, recoveryDaysAfter: 0),
                WorkoutTemplate(id: upperAID, name: "Upper A", sequenceIndex: 0, recoveryDaysAfter: 0),
                WorkoutTemplate(id: lowerAID, name: "Lower A", sequenceIndex: 1, recoveryDaysAfter: 1)
            ],
            cycleAnchor: CycleAnchor(
                nextWorkoutID: upperAID,
                firstDueDomainDay: completionDay
            ),
            completedSessions: sessions,
            currentDomainDay: currentDay
        )
    }
}
